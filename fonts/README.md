# Myanmar Unicode Fonts

These fonts are bundled locally (declared in `pubspec.yaml` → `flutter.fonts`)
so the Teashop POS renders Myanmar text correctly **offline** – no runtime font
download is needed. This avoids the Asat/Virama stacking glitches that occur when
the platform falls back to a font without proper Myanmar OpenType shaping.

| File | Family | Role | Source |
|------|--------|------|--------|
| `Pyidaungsu-Regular.ttf` | `Pyidaungsu` | Primary Myanmar font (applied globally via `ThemeData.fontFamily`) | [AungMyoKyaw/Myanmar-Unicode-Fonts](https://github.com/AungMyoKyaw/Myanmar-Unicode-Fonts/tree/master/Pyidaungsu) |
| `NotoSansMyanmar-Regular.ttf` | `NotoSansMyanmar` | Fallback for any glyph Pyidaungsu lacks (variable font, default instance) | [google/fonts](https://github.com/google/fonts/tree/main/ofl/notosansmyanmar) |

## Refreshing / re-downloading

```sh
dart run tool/setup_fonts.dart
```

## Licensing

- **Pyidaungsu** – SIL Open Font License (OFL). See the source repository.
- **Noto Sans Myanmar** – SIL Open Font License (OFL), © Google.
