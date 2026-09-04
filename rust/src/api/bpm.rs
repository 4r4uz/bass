use super::energy::compute_envelope;

/// Rango de tempos razonables para la búsqueda por autocorrelación.
const MIN_BPM: f64 = 60.0;
const MAX_BPM: f64 = 200.0;
/// Cuántos segundos de audio se analizan como máximo.
const MAX_SECONDS: f64 = 60.0;

/// Detecta el tempo (BPM) de un archivo de audio analizando su contenido.
///
/// Usa la envolvente de energía (RMS por ventanas cortas), obtiene la señal
/// de onset (incrementos de energía) y busca el período dominante por
/// autocorrelación dentro del rango 60-200 BPM. El resultado se pliega al
/// rango 70-180 BPM.
/// Devuelve `None` si el archivo no se pudo decodificar o es demasiado corto.
#[flutter_rust_bridge::frb]
pub fn detect_bpm(path: String) -> Option<u32> {
    let env = compute_envelope(&path, Some(MAX_SECONDS))?;
    let hop_time = super::energy::HOP as f64 / env.sample_rate as f64;
    let envelope = env.windows;

    // Señal de onset: solo incrementos de energía, centrada en cero.
    let mut onset: Vec<f32> = Vec::with_capacity(envelope.len());
    onset.push(0.0);
    for i in 1..envelope.len() {
        let diff = envelope[i] - envelope[i - 1];
        onset.push(if diff > 0.0 { diff } else { 0.0 });
    }
    let mean = onset.iter().sum::<f32>() / onset.len() as f32;
    for value in onset.iter_mut() {
        *value -= mean;
    }

    // Autocorrelación sobre los lags del rango de tempos buscado.
    let n = onset.len();
    let min_lag = ((60.0 / MAX_BPM) / hop_time).floor() as usize;
    let max_lag = (((60.0 / MIN_BPM) / hop_time).ceil() as usize).min(n - 1);
    if min_lag == 0 || min_lag > max_lag {
        return None;
    }
    let mut best_score = f64::NEG_INFINITY;
    let mut best_lag = 0usize;
    for lag in min_lag..=max_lag {
        let mut corr = 0.0f64;
        for i in 0..n - lag {
            corr += onset[i] as f64 * onset[i + lag] as f64;
        }
        let corr = corr / (n - lag) as f64;
        // Leve preferencia por tempos en el rango musical medio.
        let bpm_candidate = 60.0 / (lag as f64 * hop_time);
        let weight = if (90.0..=180.0).contains(&bpm_candidate) {
            1.1
        } else {
            1.0
        };
        let score = corr * weight;
        if score > best_score {
            best_score = score;
            best_lag = lag;
        }
    }
    if best_lag == 0 || best_score <= 0.0 {
        return None;
    }

    let mut bpm = 60.0 / (best_lag as f64 * hop_time);
    while bpm < 70.0 {
        bpm *= 2.0;
    }
    while bpm > 180.0 {
        bpm /= 2.0;
    }
    Some(bpm.round() as u32)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::energy::test_support::write_click_wav;

    #[test]
    fn detects_120bpm_click_track() {
        let path = std::env::temp_dir().join("bass_bpm_test_120.wav");
        write_click_wav(&path, 120.0, 30);
        let bpm =
            detect_bpm(path.to_str().unwrap().to_string()).expect("debería detectar");
        assert!((115..=125).contains(&bpm), "BPM detectado: {bpm}");
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn detects_90bpm_click_track() {
        let path = std::env::temp_dir().join("bass_bpm_test_90.wav");
        write_click_wav(&path, 90.0, 30);
        let bpm =
            detect_bpm(path.to_str().unwrap().to_string()).expect("debería detectar");
        assert!((86..=94).contains(&bpm), "BPM detectado: {bpm}");
        let _ = std::fs::remove_file(&path);
    }
}
