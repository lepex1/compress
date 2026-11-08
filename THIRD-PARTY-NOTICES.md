# Third-party notices

`compress` is distributed under the MIT license (see [LICENSE](LICENSE)).
The components below are bundled with the release archive, downloaded at runtime
or linked against. They are not part of the MIT-licensed source code and keep
their own licenses.

## Bundled with the release archive

| Component | Version | License |
|---|---|---|
| [Flutter](https://flutter.dev/) | 3.x | BSD-3-Clause |
| [Dart](https://dart.dev/) | 3.x | BSD-3-Clause |
| [file_picker](https://pub.dev/packages/file_picker) | 8.x | MIT |
| [desktop_drop](https://pub.dev/packages/desktop_drop) | 0.5.x | Apache-2.0 |
| [archive](https://pub.dev/packages/archive) | 4.x | MIT |
| [path](https://pub.dev/packages/path) | 1.9.x | BSD-3-Clause |
| [ffi](https://pub.dev/packages/ffi) | 2.x | BSD-3-Clause |
| [window_manager](https://pub.dev/packages/window_manager) | 0.4.x | MIT |

## Downloaded at runtime (not shipped)

| Component | Source | License |
|---|---|---|
| FFmpeg (`ffmpeg-master-latest-win64-gpl`) | [BtbN FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) | LGPL-2.1-or-later core; this is the `gpl` build, so GPL-2.0-or-later applies to the bundled binaries |
| FFmpeg build scripts | [BtbN FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) | MIT |

FFmpeg is downloaded on first use and stored next to the executable. It is not
part of the repository and not part of the release archive, so redistributing
the downloaded binaries is the user's responsibility under the licenses above.

## Affiliation

The project is not affiliated with, endorsed by or sponsored by FFmpeg, BtbN,
Google or the authors of the packages listed above. Their names are used only
to describe which components are used.
