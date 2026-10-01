# YouTube helper (vendored)

Used only by `YouTubeSource.swift` to turn a YouTube URL into local M4A audio.
Nothing here is part of the transcription engine.

| File | What | Source | SHA-256 |
| --- | --- | --- | --- |
| `yt-dlp` | yt-dlp 2026.08.19, zipimport build (pure Python, plain data) | `https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp` | `1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6` (matches upstream `SHA2-256SUMS`) |
| `python3.13` | CPython 3.13.15, arm64 only, from python-build-standalone `20260929` `aarch64-apple-darwin-install_only_stripped` | `https://github.com/astral-sh/python-build-standalone/releases/tag/20260929` | `b321b81dcd3f55809357bdf672f2dfffe01293e272dec798c13a435cc33f687e` (extracted executable); archive `d66c67f16148c7454b1509c32747175f7669c8b8e105b97b92a0000d66af6e6e` matches upstream `SHA256SUMS` |
| `python-home/lib/python3.13/` | Standard library from the same archive, pruned (no tkinter, idlelib, tests, ensurepip, pip, setuptools, turtle, lib2to3, pydoc data, `__pycache__`, the `_dbm` extension) | same archive | n/a |
| `ytdlp_launcher.py` | Runs `yt-dlp` and exits when the parent process disappears | this repository | n/a |
| `helper-inherit.entitlements` | `app-sandbox` + `inherit` only | this repository | n/a |

The Xcode "Embed YouTube helper" build phase installs them as:

```
Contents/Helpers/python3.13                 (only Mach-O; signed with helper-inherit.entitlements)
Contents/Resources/python-home/             (stdlib, PYTHONHOME)
Contents/Resources/yt-dlp
Contents/Resources/ytdlp_launcher.py
```

## Constraints

- `python3.13` is **arm64 only**. On an Intel Mac the helper fails to launch and the job
  reports a clear error. Intel has not been tested.
- The helper runs as a sandbox-inheriting child of the app. It has no `network.client`
  of its own; it uses the app's. Do not add other entitlements to it.
- ffmpeg and a JavaScript runtime (deno) are intentionally not bundled. Audio is fetched as
  `bestaudio[ext=m4a]`, which needs neither. yt-dlp warns that YouTube extraction without a JS
  runtime is deprecated; formats may degrade as YouTube changes.
- yt-dlp is pinned. There is no runtime self-update.

## Licences (from yt-dlp's own README, "Licensing")

- yt-dlp is under the Unlicense. The zipimport executable also contains ISC-licensed code from
  `meriyah` and MIT-licensed code from `astring` (see yt-dlp's `THIRD_PARTY_LICENSES.txt`).
- The PyInstaller-bundled executables (`yt-dlp_macos`, `yt-dlp_macos.zip`) include GPLv3+ code
  and are licensed as a combined work under GPLv3+. They are **not** used here.
- CPython is under the Python Software Foundation licence and the interpreter statically links
  OpenSSL. Python's `LICENSE.txt` is already included in the bundled standard library
  (`python-home/lib/python3.13/LICENSE.txt`). The OpenSSL licence text and a user-facing notice
  are still missing and need to be added before a public release.

## Updating

Replace `yt-dlp` with a newer zipimport release, verify it against that release's `SHA2-256SUMS`,
update the table above, and rebuild. Re-verify with a real YouTube URL.
