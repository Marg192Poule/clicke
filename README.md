<p align="center">
  <img src="public/logo.png" width="128" height="128" alt="Clické">
</p>

# Clické

A macOS menu bar app to capture screenshots and make them look great: backgrounds, window mockups, shadows, social media sizes, and privacy tools to hide sensitive information before you share.

## Features

- **Capture** an area, a window, or the full screen with global keyboard shortcuts or from the menu bar.
- **Floating preview** after each capture (like macOS): edit, copy, save, or drag the screenshot straight into another app.
- **Editor**
  - Backgrounds: bundled wallpapers, your own image, solid colors, gradients, plus blur, grain, saturation and brightness.
  - Mockups: plain, glass frame, border, or a macOS window with traffic lights (light and dark).
  - Soft shadows, rounded corners, padding, rotation and 3D tilt.
  - Several screenshots on one canvas (layers).
  - Canvas sizes for X, Instagram, LinkedIn, YouTube, Pinterest, Dribbble and standard ratios, or **Auto** at full Retina resolution.
  - Undo and redo for every change, live preview, and the last style is remembered for your next screenshot.
  - Export as PNG or JPEG, copy to the clipboard, or drag the result out of the editor.
- **Redact** sensitive information: pixelate, blur or cover any area. **Find Sensitive Text** spots email addresses, phone numbers, card numbers, IBANs, API keys and tokens, using text recognition that runs entirely on your Mac.
- **Settings**: launch at login, Dock icon, capture sound, what happens after a capture, automatic saving to a folder, and custom shortcuts.

## Privacy

- Clické makes **no network connections**. Text recognition (Vision) runs on-device.
- Global shortcuts use the system hot key API: Clické **doesn't monitor your keyboard** and doesn't need the Accessibility permission.
- Captures are written to a private temporary folder, read, then deleted. Nothing is copied to your clipboard unless "Copy to clipboard" is on.

## Requirements

- macOS 26.1 or later
- The **Screen Recording** permission (System Settings > Privacy & Security > Screen & System Audio Recording). Clické asks for it the first time you capture.

## Installation

Download the latest `.dmg`:
- from the [clické.com](https://clické.com) website, or
- from the [Releases](https://github.com/nathbns/clicke/releases/) page,

then drag the app to your Applications folder.

If macOS blocks the app on first launch because it isn't notarized: open System Settings > Privacy & Security and click "Open Anyway" next to the Clické message.

## Usage

### Keyboard shortcuts

| Action | Default |
|--------|---------|
| Capture area | ⌥⇧4 |
| Capture window | ⌥⇧T |
| Capture full screen | ⌥⇧3 |
| Settings | ⌘, |

Shortcuts can be changed in Settings > Shortcuts. If another app already uses a shortcut, Settings tells you.

### In the editor

| Action | Shortcut |
|--------|----------|
| Copy the image | ⌘C |
| Save | ⌘S |
| Undo / Redo | ⌘Z / ⇧⌘Z |
| Zoom in / out | ⌘+ / ⌘− |
| Actual size / Zoom to fit | ⌘0 / ⌘9 |
| Show or hide the inspector | ⌥⌘I |
| Move the selected image | Arrow keys (⇧ for 10 pt) |
| Delete the selected image | ⌫ |

Drop images onto the canvas to add them as layers. Right-click an image for more actions.

![Editor](public/contentEditor.png)

## Building from Source

### Prerequisites

- Xcode 26 or later
- macOS 26.1 SDK

### Steps

```bash
git clone https://github.com/nathbns/clicke.git
cd clicke
open clické.xcodeproj
```

Select your development team in Signing & Capabilities, then build with Command + R.

### Releasing

The app uses the hardened runtime and isn't sandboxed (it runs `/usr/sbin/screencapture` and saves to a folder you choose). To ship a build that opens without warnings, archive it with a Developer ID certificate and notarize it, then check the result:

```bash
codesign -dv --verbose=4 Clické.app   # expect flags=0x10000(runtime)
spctl -a -vv Clické.app               # expect "accepted, source=Notarized Developer ID"
```

## Project Structure

```
clické/
├── Capture/          Screen capture, floating preview, export of captures
├── Coordinator/      App delegate, editor window
├── Extensions/       Swift extensions
├── Features/
│   ├── Editor/       Canvas, inspector, rendering
│   │   └── Redaction/  Redaction sheet and sensitive text detection
│   └── Settings/     Settings window
├── Managers/         Hotkeys, menus, toasts
├── Models/           Settings and style models
├── Services/         Image loading, encoding, clipboard
├── View/             Root views
├── ViewModel/        Editor view model
└── public/           Bundled wallpapers
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License. See [LICENSE](LICENSE) for details.
