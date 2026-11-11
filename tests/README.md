# Native stabilization regressions

Run from the repository root:

```sh
python3 tests/android_regressions.py
python3 tests/android_buffering.py
python3 tests/android_transitions.py
python3 tests/android_receiver.py
python3 tests/android_focus.py
python3 tests/ios_regressions.py
python3 tests/ios_content.py
python3 tests/carplay_regressions.py
node --check tests/device/app.js
```

Android tests require a JDK with `javac` and `java`. The iOS and CarPlay tests require macOS and Xcode Command Line Tools. The tests compile selected production methods in temporary directories and substitute the OS APIs they need. The content-loader test compiles the complete Foundation loader and serves local HTTP responses. The checks cover publication, field retention, async cancellation, typed HLS sources, request limits, status classification and row reuse. AVPlayer, MediaSession/Binder and physical automotive integration require separate tests.

## Device smoke test

`device/app.js` is a disposable Titanium app entry point. Copy the existing test app into a temporary directory, exclude its build/modules, change its app ID to `mx.codigomovil.audiostreamaudit`, install the newly built module ZIPs there and replace only the copy's `Resources/app.js`. Keep the normal background-audio and scene configuration; a vehicle entitlement is unnecessary for the phone/tablet checks.

Start the deterministic fixture server:

```sh
python3 tests/device/serve.py
```

The server requires FFmpeg and listens on port 18765. Set the copied app's string property `auditBaseURL` to `http://<Mac-LAN-address>:18765` and enable local HTTP in the copy's ATS or Android network configuration. Accept the Local Network prompt in the iPadOS test app before starting the timed run. The prompt comes from connecting to the test server on the LAN. The server generates quiet MP3 audio and sends known ICY metadata (`Fixture Artist - Fixture Song`).

The run verifies direct playback, repeated start, received metadata with automatic publication disabled, pause, soft/hard stop, relative playlists and retry cancellation. It then opens three actual public streams (Radio Paradise, Heart London HLS and The VIP Lounge 2), records received metadata and checks play/pause. Public endpoints can change or fail independently of this module. Inspect `audit-results.json` in the app data directory and the platform's native logs; a green JavaScript result alone does not prove correct lock-screen metadata or URI permissions.

Use Device Hub for the physical iPad and Visor Android for the connected Android. Bluetooth, headset removal, extended suspension, car cold start/search and Patrick's exact URI-reader problem need separate hardware acceptance.

See [VALIDACION.md](VALIDACION.md) for the first audit results and
[SEGUNDA_PASADA.md](SEGUNDA_PASADA.md) for the second audit, final-package
measurements and remaining limits. Both reports retain incomplete runs and
measurements that exceeded their budget.

`device/second-pass.js` checks silent cold starts, delayed playlists, pause during resolution, rapid switches, finite EOF and restart in the disposable audit app. Use the silent fixture documented in the second-audit evidence; do not run it against the original apps.

## Silent second-pass acceptance

Run `python3 tests/device/second_pass_serve.py --output /tmp/tiaudiostream-silent`. The default bind is loopback, port 18767. Android can use `adb reverse tcp:18767 tcp:18767` and app property `auditBaseURL=http://127.0.0.1:18767`. For an authorized iPad LAN test, pass `--host 0.0.0.0` and use the Mac LAN address instead. Generated audio has zero volume. The server writes fixture assets, request logs and posted results only to the selected evidence directory.

Install the module ZIP in the disposable app before building. Run `second-pass.js` first, then run `stability.js` for 30 minutes. Wait until the run ends before rebuilding or installing another APK. Unlock the Android before launch and check that the app is visible. Each script keeps its window awake during the run, restores the flag afterward and hard-stops playback on completion or error. Remove the ADB reverse mapping afterward.

`controller-target.js` and `controller/MainActivity.java` are an independent MediaBrowser/MediaController reader and target. The external controller supports inspect, prepareB/play, playB, pause/play/stop, next/search and transient-focus/manual-pause cases. These check transport, actual published bitmap/URI dimensions, hashes and reader permissions; they do not certify a car's visual rendering. Build/install them only under their disposable audit package IDs.

Implementation, recorded results and remaining hardware acceptance: [SEGUNDA_PASADA.md](SEGUNDA_PASADA.md).

Build the reader with `python3 tests/device/controller/build.py --output /tmp/tiaudio-controller.apk` and install it. Build the disposable target app with `controller-target.js` and the final module. With the phone unlocked, run `python3 tests/device/controller/run.py --fixture-evidence /tmp/tiaudiostream-silent --output /tmp/tiaudio-controller-results`. The runner needs one authorized ADB device and force-stops only the two disposable packages between cases. Check its results for playback and artwork as well as the MediaBrowser connection.
