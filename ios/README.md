# ti.audiostream - iOS

Platform-specific details for the iOS implementation of `ti.audiostream`.

For the full API reference, see the [main README](../README.md).

The iOS package requires Titanium SDK **13.1.1.GA+** and **iOS 15.0+**. See the [source build requirements](../README.md#mac-catalyst-note) if you rebuild the module with Mac Catalyst support.

## iOS-specific behavior

### Source completion and metadata

The module accepts timed metadata only from the selected item's output and URL, including when you change stations while paused. At the end of the item it reports `stopped`. The next `start()` prepares a fresh item. AVPlayer opens direct audio and HLS URLs with recognized suffixes without a preliminary playlist request. The module still resolves extensionless URLs and station playlists.

CarPlay keeps the station list open and shares pending artwork downloads across rows with the same URL. If a row changes URL before its download finishes, it discards that image. Verify the result on a CarPlay display.

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
| Interruption ends                      | Playback resumes when the system allows it and playback is still requested |

If the user manually pauses before or during the interruption, playback stays paused after the interruption ends. Pending retries also honor manual pause and stop.

The module resolves relative M3U and PLS entries against the response URL. AVPlayer handles HLS, including HLS served with a `.m3u` suffix. Changing URLs invalidates the previous resolution. Artwork downloads have an 8 MiB limit, a 15-second resource timeout and a 1024-pixel decode limit. The module publishes text metadata while the image loads. Detailed native diagnostics are off by default. Compile with `TI_AUDIOSTREAM_DIAGNOSTICS=1` to enable diagnostics with URLs redacted.

### Mac Catalyst

The iOS module includes Mac Catalyst support (`mac: true` in manifest). See the [main README](../README.md#mac-catalyst-note) for SDK version requirements.

## CarPlay

CarPlay support is built into the module, but Titanium apps still need the CarPlay entitlement and scene manifest entries in `tiapp.xml`.

At runtime, the module provides:

- CarPlay and window scene delegates for Titanium apps
- A station browsing list backed by `setAutomotiveStations(...)`
- Now-playing metadata published through MediaPlayer for the system's Now Playing surface
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

If your approved App ID and provisioning profile also include `com.apple.developer.playable-content`, keep it enabled consistently in the same block.

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

Use the manifest above on every supported Titanium SDK version. On `13.3.0.GA+`, TiApp uses the UIScene lifecycle natively and the module forwards the window scene to it. On `≤ 13.2.x.GA`, the module attaches Titanium's window to the connecting scene.

#### 5. Background audio (required)

Background audio must already be enabled in your `tiapp.xml` (inside `<ios><plist><dict>`). This is the same configuration required for background playback:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

#### 6. Check the active stream

Once configured, CarPlay reads the same active stream metadata and playback state that power the lock screen and Control Center.

### What appears on CarPlay

- **Station list** with artwork thumbnails, a Play/Pause row, and a single active station indicator
- **System Now Playing** with title, artist, and artwork. Selecting a station keeps the app on its list.
- **Transport controls** exposed through MediaPlayer
- The `remotecontrol` event fires normally from CarPlay interactions, with the same `action` values (`PLAY`, `PAUSE`, `STOP`, `NEXT`, `PREV`) as from the lock screen or Control Center

### Limitations

- Apple must approve the entitlement before CarPlay works
- The entitlement is **per-app**, not per-module

## Testing CarPlay

With Device Hub on Xcode 27.2, connect a physical iPhone to the Mac by USB and open CarPlay Simulator for that device. A simulated iPhone or a device paired only over the network cannot host this CarPlay session. Install a build signed with your approved entitlement, then select a station from the CarPlay list. Verify the active indicator, artwork, and transport controls. [Xcode 27.2 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes)

On older Xcode versions that provide the CarPlay external display in Simulator, run the app on an existing iOS simulator, then choose **I/O → External Displays → CarPlay**. Open the app on the CarPlay home screen and select a station. The app still needs its CarPlay entitlement. [Apple's Simulator guide](https://developer.apple.com/documentation/carplay/using-the-carplay-simulator)

You can also retest an existing simulator build by installing and launching its `.app` with `xcrun simctl install` and `xcrun simctl launch`, then opening the CarPlay display.

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

- If your app listens for `remotecontrol`, handle `NEXT` and `PREV` there. Without a listener, the registered station list provides native next/previous behavior.
- Play, pause, and stop are handled automatically by the module
- If no controls appear at all, verify the `UIBackgroundModes: audio` configuration
