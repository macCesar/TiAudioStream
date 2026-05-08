# ti.audiostream - iOS

Platform-specific details for the iOS implementation of `ti.audiostream`.

For the full API reference, see the [main README](../README.md).

## iOS-specific behavior

### Background audio

Audio playback uses `AVAudioSession` with the **Playback** category, so audio continues when the screen locks or the app moves to the background.

Background audio requires the `UIBackgroundModes` key in your `tiapp.xml` (inside `<ios><plist><dict>`):

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

Without this, iOS suspends audio when the app goes to the background.

### Lock screen and system controls

The module registers commands with `MPRemoteCommandCenter.sharedCommandCenter`:

- Play
- Pause
- Toggle play/pause
- Stop
- Next track
- Previous track

These controls appear on the lock screen, in Control Center, and on Apple Watch automatically.

### Audio interruption handling

| Scenario                               | Behavior                                                          |
| :------------------------------------- | :---------------------------------------------------------------- |
| Interruption begins (phone call, Siri) | Playback pauses                                                   |
| Interruption ends                      | Playback resumes (only if it was playing before the interruption) |

If the user manually paused before the interruption, playback stays paused after the interruption ends.

### Mac Catalyst

The iOS module includes Mac Catalyst support (`mac: true` in manifest). See the [main README](../README.md#mac-catalyst-note) for SDK version requirements.

## CarPlay

CarPlay support is built into the module, but Titanium apps still need the CarPlay entitlement and scene manifest entries in `tiapp.xml`.

At runtime, the module provides:

- CarPlay and window scene delegates for Titanium apps
- A station browsing list backed by `setAutomotiveStations(...)`
- Now-playing info published directly to `MPNowPlayingInfoCenter.defaultCenter` so CarPlay and the system always see the app as the active audio source
- `remotecontrol` events from CarPlay with the same `PLAY`, `PAUSE`, `STOP`, `NEXT`, and `PREV` actions used on the lock screen

### Setup step-by-step

#### 1. Request the entitlement

1. Go to [Apple's CarPlay entitlement request form](https://developer.apple.com/contact/carplay/)
2. Fill in your app details and select **Audio** as the app type
3. Submit. Apple reviews and approves it, usually within a few business days.

#### 2. Update your provisioning profile

After Apple approves the entitlement:

1. Go to [Apple Developer account](https://developer.apple.com/account) > Certificates, Identifiers & Profiles > Identifiers
2. Select your app identifier
3. Enable the **CarPlay Audio** capability
4. Regenerate your provisioning profile and download it

#### 3. Add entitlements to `tiapp.xml`

Add the CarPlay Audio entitlement inside your `<ios>` section:

```xml
<ios>
    <entitlements>
        <dict>
            <key>com.apple.developer.carplay-audio</key>
            <true/>
        </dict>
    </entitlements>
</ios>
```

If your approved App ID or existing provisioning profile also includes `com.apple.developer.playable-content`, keep it enabled consistently in the same block. The example apps in this repo use both keys during development.

#### 4. Add the scene manifest (required for Titanium)

CarPlay uses the iOS scene lifecycle. Add this inside `<ios><plist><dict>`:

```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <true/>
    <key>UISceneConfigurations</key>
    <dict>
        <key>CPTemplateApplicationSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneClassName</key>
                <string>CPTemplateApplicationScene</string>
                <key>UISceneConfigurationName</key>
                <string>Default Configuration</string>
                <key>UISceneDelegateClassName</key>
                <string>TiAudiostreamCarPlaySceneDelegate</string>
            </dict>
        </array>
        <key>UIWindowSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneConfigurationName</key>
                <string>Default Configuration</string>
                <key>UISceneDelegateClassName</key>
                <string>TiAudiostreamWindowSceneDelegate</string>
            </dict>
        </array>
    </dict>
</dict>
```

These delegate classes ship inside the module. Your app only references them by name in `tiapp.xml`.

#### 5. Background audio (required)

Background audio must already be enabled in your `tiapp.xml` (inside `<ios><plist><dict>`). This is the same configuration required for background playback:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

#### 6. That's it

Once configured, CarPlay reads the same active stream metadata and playback state that power the lock screen and Control Center.

### What appears on CarPlay

- **Station list** with station/program rows published from the app
- **Now Playing screen** with title, artist, and artwork
- **Transport controls**: play/pause, next, previous, stop
- The `remotecontrol` event fires normally from CarPlay interactions, with the same `action` values (`PLAY`, `PAUSE`, `STOP`, `NEXT`, `PREV`) as from the lock screen or Control Center

### Limitations

- Apple must approve the entitlement before CarPlay works
- The entitlement is **per-app**, not per-module

## Testing with CarPlay Simulator

1. Run your app on the iOS Simulator
2. In the Simulator menu: **I/O → External Displays → CarPlay**
3. Start a stream in your app
4. Open your app from the CarPlay home screen or tap **Now Playing**

The CarPlay entitlement is required even in the Simulator. Without it, your app will not appear as a selectable audio source on the CarPlay home screen.

If the CarPlay simulator shows a stale or blank Now Playing surface during development, test the already-built `.app` directly with `simctl install` + `simctl launch` or from Xcode against the generated simulator build.

### Using a physical device

Connect an iPhone to a CarPlay-compatible head unit (USB or wireless). The CarPlay entitlement must be approved and included in the provisioning profile.

## Troubleshooting

### App does not appear on CarPlay

- Verify the CarPlay Audio entitlement is **approved** in your Apple Developer account
- Confirm the provisioning profile has been regenerated and installed after approval
- Make sure `UIBackgroundModes: audio` is set in `tiapp.xml`

### No metadata on CarPlay

- Ensure `setStream()` or `setMetadata()` is called before or during playback
- Check that the stream is actually playing (CarPlay needs an active Now Playing session)
- Verify the scene manifest is present in the built `Info.plist`, not only in source `tiapp.xml`

### Controls do not respond

- Make sure you have a `remotecontrol` event listener set up for `NEXT` and `PREV`
- Play, pause, and stop are handled automatically by the module
- If no controls appear at all, verify the `UIBackgroundModes: audio` configuration
