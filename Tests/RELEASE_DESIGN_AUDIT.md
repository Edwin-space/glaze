# Release design capture suite

These are capture tests, not a claim of visual or accessibility compliance. Inspect
every attachment before accepting it. Reject transition frames, unexpected screens,
and screenshots containing private server details. Never use the whole Mac desktop
as evidence; the Mac suite captures the target application's window.

## Targets

- `GlazeiOSUITests/ReleaseDesignAudit`: welcome, settings, largest text, Korean,
  source forms, local playback, subtitle sheet, rotation, first-playback guide.
  The guide also runs at accessibility XXXL: its heading joins the scroll content,
  while completion remains fixed. At standard sizes both heading and completion
  stay outside the scroll content. Tests assert the completion control is hittable
  and inside the visible window, before and after scrolling.
- `GlazeMacUITests/MacReleaseDesignAudit`: start, settings, playback and inspectors.
- `GlazeTVUITests/TVReleaseDesignAudit`: simulator onboarding, home and settings.

Mac playback uses XCTest's public `openURL` delivery after launch; current macOS
hosts `NSOpenPanel` in a separate service that this test session cannot address.
This does not verify the file picker's accessibility. The TV suite skips on hardware.

The Mac and TV schemes are separate from application release schemes. Run UI test
sessions serially: simultaneous desktop accessibility sessions can interfere with
launching and interaction. A passing test only proves its explicit assertions and
that an attachment was produced; a human must still verify the image.

## Fixtures and privacy

For local playback, put two disposable, non-personal movies named `AuditSample1.mkv`
and `AuditSample2.mkv` in the test app's `Documents/GlazeAudit` directory. The Mac
playback capture uses `/tmp/glaze-design-audit/GlazeAudit/AuditSample1.mkv`.
The November audit used a 120-second stream-copy excerpt of the repository's
`test file/Sintel.2010.1080p.mkv` (© copyright Blender Foundation,
[durian.blender.org](https://durian.blender.org/sharing/),
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)). Clips and test
result bundles are not committed. This layout-only fixture does not replace
functional regression tests with `test file/testmedia.mkv`.

Source-form tests run only on a simulator and type the non-resolving example
`https://example.invalid:5006/video/`; they do not connect, save credentials, or
modify a real NAS. Settings captures do not toggle diagnostics or delete data.
Saved Mac settings may still be visible: inspect before publication even when
launch arguments attempt to override connection defaults.

Physical iPhone tests must explicitly target iPhone 13 mini
(`00008110-00060D820E44401E`). Do not substitute iPhone 17 Pro or deploy to an
Apple TV. Never unlock a device with credentials; wait for the viewer to unlock it.

## Running

Regenerate after adding test files:

```sh
xcodegen generate
xcodebuild -project Glaze.xcodeproj -scheme GlazeiOSUITests \
  -destination 'platform=iOS Simulator,id=YOUR_AUDIT_SIMULATOR_ID' \
  -only-testing:GlazeiOSUITests/ReleaseDesignAudit -collect-test-diagnostics never \
  -parallel-testing-enabled NO test
xcodebuild -project Glaze.xcodeproj -scheme GlazeMacUITests \
  -destination 'platform=macOS' -collect-test-diagnostics never -parallel-testing-enabled NO test
xcodebuild -project Glaze.xcodeproj -scheme GlazeTVUITests \
  -destination 'platform=tvOS Simulator,id=YOUR_AUDIT_SIMULATOR_ID' \
  -collect-test-diagnostics never -parallel-testing-enabled NO test
```

Export attachments from a **completed** `.xcresult`, inspect the saved PNGs, and
copy only accepted images to the dated audit folder. Keep raw results local. Do
not use audit screenshots as App Store marketing assets without a separate review.
