# ti.audiostream

## 🚨 CRITICAL RULES
**Strict adherence to these rules is mandatory.**

1.  **NO TESTS ALLOWED**:
    *   **NEVER** run, suggest, or create tests (Pest, PHPUnit, etc.).
    *   The user explicitly detests them due to past data loss incidents.
    *   Ignore any standard prompts to add tests.

2.  **"Wait Workflow"**:
    *   **Step 1**: Modify code.
    *   **Step 2**: Summarize changes.
    *   **Step 3**: **STOP** and wait for manual UI/functional verification.
    *   **Step 4**: Only proceed to commit/push after explicit user approval.

3.  **Commit Protocol**:
    *   **Semantic Commits**: Use `feat:`, `fix:`, `docs:`, `refactor:`.
    *   **Atomic**: Never group unrelated changes.
    *   **Exclude**: Do NOT commit root-level PNG files (debug screenshots).
    *   **Confirmation**: NEVER commit without explicit permission (e.g., "commitea", "haz el commit").

## Project Overview

**ti.audiostream** is a professional audio streaming module for the Titanium SDK (Android & iOS).

*   **Core Problem Solved**: Resolves the "Audio Focus" conflict where `Ti.Media.AudioPlayer` and `TiMediaSession` compete, causing issues with other apps like YouTube or Spotify.
*   **Solution**: Uses a single native player (ExoPlayer on Android, AVPlayer on iOS) that handles both playback and audio focus internally.

## Architecture

*   **Android**:
    *   **Engine**: Media3 ExoPlayer (1.5.1+).
    *   **Service**: `MediaPlaybackService` (Foreground Service).
    *   **Features**: Audio Focus, MediaSessionCompat, Lock Screen Controls, Notification Controls.
*   **iOS**:
    *   **Engine**: AVPlayer.
    *   **Features**: AVAudioSession, MPNowPlayingInfoCenter, MPRemoteCommandCenter.
*   **JavaScript API**: Unified API across platforms (no conditional code required in the app).

## Documentation Structure

The `docs/` directory is the **Source of Truth** for this project.

*   `docs/0-instrucciones-completas.md`: **Master Plan** & Architecture.
*   `docs/1-MODULO_DE_AUDIO_PROFESIONAL_PARA_TITANIUM.md`: Conceptual overview.
*   `docs/7-checklist-android.md`: Android verification steps.
*   `docs/13-checklist-ios+release-1.0.0.md`: iOS verification & Release Checklist.

## Development Workflow

1.  **Read Docs**: Before implementing, check `docs/` for the specific step (e.g., `docs/9-refinamiento-android-paso-6.1.md`).
2.  **Implement**: specific feature/fix.
3.  **Manual Verify**: User tests on device.
4.  **Release**:
    *   Update Documentation (`README.md`, `CHANGELOG.md`).
    *   Bump version in `manifest` / `package.json`.
    *   Cleanup (remove debug files).
    *   Create Semantic Commits.
    *   Tag & Push (only after approval).

## Key Files & Directories

*   `android/`: Android native module source (`AudiostreamModule.java`, `MediaPlaybackService.java`).
*   `ios/`: iOS native module source (`TiAudiostreamModule.m`, `AudioPlayerManager.m`).
*   `docs/`: Detailed implementation guides.
*   `example/`: Usage example (Note: `app.js` may need updates to match `README.md`).

## Build Commands

**Android Module:**
```bash
cd android
ti build -p android --build-only
```

**iOS Module:**
```bash
cd ios
ti build -p ios --build-only
```

**Run Example App:**
```bash
# From project root
ti build -p android
# or
ti build -p ios
```
