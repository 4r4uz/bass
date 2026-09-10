# (B)ASS

Reproductor de música **local** para Android, centrado en visuales: cada canción se analiza (energía, espectro de 32 bandas, BPM) y la portada reacciona al audio real con visualizadores dibujados por `CustomPainter`.

> Sin streaming, sin cuentas, sin red. Tu música, a tu manera.

## Características

- **Biblioteca local**: importa archivos sueltos (`+`) o elige una **carpeta observada** que se escanea al arrancar y se vigila en vivo (lo nuevo entra solo).
- **Visualizadores reactivos** alrededor de la portada:
  - *Tentáculos* — 1 o 3 capas concéntricas, cada capa atada a un rango (graves/medios/agudos).
  - *Sectores* — mapeo espacial fijo banda → sector (graves abajo, agudos arriba), cada zona con su propio envelope follower.
- **Análisis espectral progresivo**: la primera vez se analiza por fragmentos de 12 s y el visualizador funciona mientras tanto; luego queda cacheado (no se re-analiza).
- **Detección de BPM** por autocorrelación + **modo calmado** en silencios sostenidos.
- **Personalización**: 5 formas de portada, 5 paletas × claro/oscuro, sensibilidad del visualizador ajustable.
- **Notificación MediaStyle** con portada, controles y cierre limpio al deslizar la app de recientes.


## Cómo compilar

Requisitos: Flutter SDK (^3.12), Rust toolchain (`cargo` + `flutter_rust_bridge_codegen`), JDK 17.

```bash
flutter pub get
flutter run
flutter build apk
```

Si tocas `rust/src/api/`:

```bash
flutter_rust_bridge_codegen generate
cd rust && cargo test
```

## Uso

1. Abre **Ajustes → Carpeta observada** y elige tu carpeta de música (o usa `+` para archivos sueltos).
2. Reproduce: en **Ajustes** cambia tipo (Tentáculos/Sectores), capas (1/Múltiples), sensibilidad, forma de portada y tema.
3. La primera reproducción analiza en segundo plano; las siguientes son instantáneas (caché en Hive).


## Roadmap

- [ ] Arreglar que esta porquería no queda como quiero T·T