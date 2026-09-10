use std::fs::File;
use std::io::ErrorKind;
use std::path::Path;

use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error as SymphoniaError;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use std::f32;

/// Ventana de análisis: ~11,6 ms a 44,1 kHz.
pub const HOP: usize = 512;

/// Número de bandas espectrales para el visualizador.
pub const SPECTRAL_BANDS: usize = 32;

/// Análisis espectral: bandas de frecuencia por ventana.
#[flutter_rust_bridge::frb]
pub struct SpectralAnalysis {
    /// Energía normalizada 0–1 por banda (frecuencia) y por ventana.
    /// Disposición: [banda_0_ventana_0, banda_1_ventana_0, ..., banda_0_ventana_1, ...].
    pub bands: Vec<f32>,
    /// Número de bandas espectrales.
    pub num_bands: u32,
    /// Ventanas por segundo.
    pub windows_per_second: f64,
}

/// Envolvente de energía: RMS por ventana junto al sample rate del archivo.
pub struct Envelope {
    pub windows: Vec<f32>,
    pub sample_rate: usize,
}

/// Resultado del análisis de energía, listo para la UI.
#[flutter_rust_bridge::frb]
pub struct EnergyAnalysis {
    /// Energía RMS por ventana, normalizada 0–1.
    pub windows: Vec<f32>,
    /// Ventanas por segundo (depende del sample rate del archivo).
    pub windows_per_second: f64,
}

/// Decodifica el audio a mono y calcula el RMS por ventanas de [`HOP`].
///
/// Con `max_seconds = Some(s)` corta el análisis a los primeros `s` segundos;
/// con `None` analiza el archivo completo. El audio nunca se acumula entero
/// en memoria: solo la envolvente.
pub fn compute_envelope(path: &str, max_seconds: Option<f64>) -> Option<Envelope> {
    let file = File::open(path).ok()?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    let extension = Path::new(path).extension()?.to_str()?.to_lowercase();
    hint.with_extension(&extension);

    let probed = symphonia::default::get_probe()
        .format(
            &hint,
            mss,
            &FormatOptions::default(),
            &MetadataOptions::default(),
        )
        .ok()?;
    let mut format = probed.format;

    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)?;
    let track_id = track.id;
    let sample_rate = track.codec_params.sample_rate? as usize;
    if sample_rate == 0 {
        return None;
    }
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &DecoderOptions::default())
        .ok()?;
    let max_samples = max_seconds.map(|s| (s * sample_rate as f64) as usize);

    let mut windows: Vec<f32> = Vec::new();
    let mut acc = 0.0f64;
    let mut count = 0usize;
    let mut total = 0usize;
    loop {
        if max_samples.is_some_and(|max| total >= max) {
            break;
        }
        let packet = match format.next_packet() {
            Ok(packet) => packet,
            Err(SymphoniaError::IoError(ref e))
                if e.kind() == ErrorKind::UnexpectedEof =>
            {
                break
            }
            Err(_) => break,
        };
        if packet.track_id() != track_id {
            continue;
        }
        let Ok(decoded) = decoder.decode(&packet) else {
            continue;
        };
        let spec = *decoded.spec();
        let channels = spec.channels.count().max(1);
        let mut buffer = SampleBuffer::<f32>::new(decoded.capacity() as u64, spec);
        buffer.copy_interleaved_ref(decoded);
        for frame in buffer.samples().chunks(channels) {
            let mono = frame.iter().sum::<f32>() / channels as f32;
            acc += (mono as f64).powi(2);
            count += 1;
            total += 1;
            if count == HOP {
                windows.push((acc / HOP as f64).sqrt() as f32);
                acc = 0.0;
                count = 0;
            }
        }
    }
    if count > 0 {
        windows.push((acc / count as f64).sqrt() as f32);
    }
    if windows.len() < 32 {
        return None;
    }
    Some(Envelope { windows, sample_rate })
}

/// Analiza la energía de todo el archivo: RMS por ventana, normalizado 0–1.
///
/// De esta envolvente se derivan la forma de onda y el visualizador de
/// golpes reales de la app. El resultado se cachea del lado de Dart.
#[flutter_rust_bridge::frb]
pub fn analyze_energy(path: String) -> Option<EnergyAnalysis> {
    let env = compute_envelope(&path, None)?;
    let max = env.windows.iter().copied().fold(0.0f32, f32::max);
    if max <= 0.0 {
        return None;
    }
    Some(EnergyAnalysis {
        windows: env.windows.iter().map(|value| value / max).collect(),
        windows_per_second: env.sample_rate as f64 / HOP as f64,
    })
}

/// Realiza FFT por ventana y extrae energía de [SPECTRAL_BANDS] bandas,
/// limitado al rango [start_seconds, start_seconds + duration_seconds]
/// (`None` = hasta el final del archivo). Las bandas se espacian
/// logarítmicamente: graves en primeras bandas, agudos en últimas.
///
/// Los frames anteriores a `start_seconds` se decodifican (ineludible con
/// la mayoría de formatos comprimidos) pero se descartan sin FFT.
fn compute_spectral_bands_range(
    path: &str,
    start_seconds: f64,
    duration_seconds: Option<f64>,
) -> Option<SpectralAnalysis> {
    let file = File::open(path).ok()?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    let extension = Path::new(path).extension()?.to_str()?.to_lowercase();
    hint.with_extension(&extension);

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .ok()?;
    let mut format = probed.format;
    let track = format.tracks().iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)?;
    let track_id = track.id;
    let sample_rate = track.codec_params.sample_rate? as usize;
    if sample_rate == 0 {
        return None;
    }
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &DecoderOptions::default())
        .ok()?;

    let start_frame = (start_seconds * sample_rate as f64) as usize;
    let end_frame = duration_seconds
        .map(|d| start_frame + (d * sample_rate as f64) as usize);

    let mut window: Vec<f32> = vec![0.0; HOP];
    let mut bands_data: Vec<f32> = Vec::new();
    let mut pos = 0usize;
    let mut frames = 0usize;

    'outer: loop {
        let packet = match format.next_packet() {
            Ok(packet) => packet,
            Err(SymphoniaError::IoError(ref e)) if e.kind() == ErrorKind::UnexpectedEof => break,
            Err(_) => break,
        };
        if packet.track_id() != track_id { continue; }
        let Ok(decoded) = decoder.decode(&packet) else { continue; };
        let spec = *decoded.spec();
        let channels = spec.channels.count().max(1);
        let mut buffer = SampleBuffer::<f32>::new(decoded.capacity() as u64, spec);
        buffer.copy_interleaved_ref(decoded);

        for frame in buffer.samples().chunks(channels) {
            frames += 1;
            if let Some(end) = end_frame {
                if frames > end {
                    break 'outer;
                }
            }
            if frames <= start_frame {
                continue;
            }
            let mono = frame.iter().sum::<f32>() / channels as f32;
            window[pos] = mono;
            pos += 1;
            if pos == HOP {
                let bands = simple_fft_bands(&window, sample_rate);
                bands_data.extend_from_slice(&bands);
                pos = 0;
            }
        }
    }

    if bands_data.is_empty() || bands_data.len() % SPECTRAL_BANDS != 0 {
        return None;
    }

    Some(SpectralAnalysis {
        bands: bands_data,
        num_bands: SPECTRAL_BANDS as u32,
        windows_per_second: sample_rate as f64 / HOP as f64,
    })
}

/// FFT simple usando radix-2 Cooley-Tukey. Devuelve energía normalizada
/// en [SPECTRAL_BANDS] bandas logarítmicamente espaciadas.
fn simple_fft_bands(samples: &[f32], sample_rate: usize) -> Vec<f32> {
    let n = samples.len().next_power_of_two();
    let mut real: Vec<f32> = vec![0.0; n];
    let mut imag: Vec<f32> = vec![0.0; n];

    // Hann window para suavizar bordes.
    for (i, &sample) in samples.iter().enumerate() {
        let window = (2.0 * std::f32::consts::PI * i as f32 / (samples.len() as f32 - 1.0)).sin().powi(2);
        real[i] = sample * window;
    }

    fft_radix2(&mut real, &mut imag);

    // Bins a bandas: logarítmicamente espaciadas de ~50 Hz a Nyquist.
    let nyquist = sample_rate / 2;
    let bin_to_hz = sample_rate as f32 / n as f32;
    let mut bands = vec![0.0; SPECTRAL_BANDS];
    let min_hz = 50.0;

    for (b, band) in bands.iter_mut().enumerate() {
        let freq_start = min_hz * 2.0_f32.powf(b as f32 / (SPECTRAL_BANDS - 1) as f32 * (nyquist as f32 / min_hz).log2());
        let freq_end = min_hz * 2.0_f32.powf((b as f32 + 1.0) / (SPECTRAL_BANDS - 1) as f32 * (nyquist as f32 / min_hz).log2());

        let bin_start = (freq_start / bin_to_hz).max(0.0) as usize;
        let bin_end = (freq_end / bin_to_hz).min((n / 2) as f32) as usize;

        let mut energy = 0.0f32;
        for j in bin_start..=bin_end.min(n / 2 - 1) {
            energy += real[j].powi(2) + imag[j].powi(2);
        }
        *band = (energy / ((bin_end - bin_start).max(1) as f32)).sqrt();
    }

    // Escala fija (NO relativa a la ventana): dividir por el máximo de cada
    // ventana clavaba la banda más fuerte en 1.0 SIEMPRE (visual clavado en
    // el máximo) y destruía el nivel absoluto entre ventanas. Con escala
    // fija + AGC por banda del lado Dart, todas las bandas reaccionan de
    // forma comparable. 64.0 deja margen para que picos fuertes no se
    // recorten al cachear (1 byte por valor).
    bands.iter_mut().for_each(|b| *b = (*b / 64.0).min(1.0));
    bands
}

/// FFT radix-2 Cooley-Tukey (DIT). Modifica los vectores in-place.
fn fft_radix2(real: &mut [f32], imag: &mut [f32]) {
    let n = real.len();
    if n <= 1 {
        return;
    }

    let mut bit_reverse = vec![0usize; n];
    for i in 0..n {
        let mut rev = 0;
        let mut val = i;
        let mut temp = n;
        while temp > 1 {
            rev = (rev << 1) | (val & 1);
            val >>= 1;
            temp >>= 1;
        }
        bit_reverse[i] = rev;
    }

    for i in 0..n {
        if bit_reverse[i] > i {
            real.swap(i, bit_reverse[i]);
            imag.swap(i, bit_reverse[i]);
        }
    }

    let mut m = 2;
    while m <= n {
        let angle = 2.0 * std::f32::consts::PI / m as f32;
        for k in (0..n).step_by(m) {
            for j in 0..m / 2 {
                let twiddle_real = angle * j as f32;
                let wr = twiddle_real.cos();
                let wi = -twiddle_real.sin();

                let idx_e = k + j;
                let idx_o = k + j + m / 2;

                let tr = wr * real[idx_o] - wi * imag[idx_o];
                let ti = wr * imag[idx_o] + wi * real[idx_o];

                real[idx_o] = real[idx_e] - tr;
                imag[idx_o] = imag[idx_e] - ti;

                real[idx_e] += tr;
                imag[idx_e] += ti;
            }
        }
        m *= 2;
    }
}

/// Análisis espectral completo: extrae bandas de frecuencia.
#[flutter_rust_bridge::frb]
pub fn analyze_spectral(path: String) -> Option<SpectralAnalysis> {
    compute_spectral_bands_range(&path, 0.0, None)
}

/// Analiza solo el fragmento [start_seconds, start_seconds + duration_seconds]
/// del archivo y devuelve sus bandas de frecuencia.
///
/// Pensado para el análisis progresivo del lado Dart: se encadenan llamadas
/// avanzando `start_seconds`, se actualiza el visualizador en vivo con cada
/// fragmento y el resultado completo se cachea al terminar.
#[flutter_rust_bridge::frb]
pub fn analyze_spectral_chunk(
    path: String,
    start_seconds: f64,
    duration_seconds: f64,
) -> Option<SpectralAnalysis> {
    compute_spectral_bands_range(&path, start_seconds, Some(duration_seconds))
}


#[cfg(test)]
pub(crate) mod test_support {
    /// Genera un WAV mono con clicks periódicos al tempo indicado.
    pub fn write_click_wav(path: &std::path::Path, bpm: f64, seconds: usize) {
        let spec = hound::WavSpec {
            channels: 1,
            sample_rate: 44100,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };
        let mut writer = hound::WavWriter::create(path, spec).unwrap();
        let beat_len = (44100.0 * 60.0 / bpm).round() as usize;
        let click_len = 441; // ~10 ms
        for i in 0..44100 * seconds {
            let value = if i % beat_len < click_len {
                ((i % beat_len) as f32 / click_len as f32
                    * std::f32::consts::PI)
                    .sin()
                    * 0.9
                    * 32767.0
            } else {
                0.0
            };
            writer.write_sample(value as i16).unwrap();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spectral_chunk_limits_range() {
        let path = std::env::temp_dir().join("bass_chunk_test.wav");
        test_support::write_click_wav(&path, 120.0, 10);
        let full = analyze_spectral(path.to_str().unwrap().to_string()).unwrap();
        let chunk = analyze_spectral_chunk(
            path.to_str().unwrap().to_string(),
            2.0,
            3.0,
        )
        .unwrap();
        let wps = full.windows_per_second;
        let windows = chunk.bands.len() as f64 / chunk.num_bands as f64;
        assert!(
            (windows - 3.0 * wps).abs() < wps,
            "ventanas del fragmento: {windows} (esperadas ~{})",
            3.0 * wps
        );
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn energy_has_peaks_at_clicks() {
        let path = std::env::temp_dir().join("bass_energy_test.wav");
        test_support::write_click_wav(&path, 120.0, 5);
        let analysis = analyze_energy(path.to_str().unwrap().to_string())
            .expect("debería analizar");
        assert_eq!(analysis.windows_per_second, 44100.0 / HOP as f64);
        // Los clicks caen al inicio de cada beat (~43 ventanas a 120 BPM).
        assert!(
            analysis.windows[0] > 0.5,
            "primer click: {}",
            analysis.windows[0]
        );
        let beat_windows = (0.5 * analysis.windows_per_second).round() as usize;
        assert!(
            analysis.windows[beat_windows] > 0.5,
            "click del beat: {}",
            analysis.windows[beat_windows]
        );
        // Una ventana silenciosa entre clicks queda cerca de cero.
        assert!(
            analysis.windows[beat_windows / 2] < 0.1,
            "silencio: {}",
            analysis.windows[beat_windows / 2]
        );
        let _ = std::fs::remove_file(&path);
    }
}
