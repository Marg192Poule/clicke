<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Clické Icon">
</p>

<h1 align="center">Clické</h1>

<p align="center">
  <strong>Beautiful screenshots in seconds</strong>
</p>

<p align="center">
  A lightweight macOS menu bar app to capture, style, and share stunning screenshots.
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#building">Building</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#license">License</a>
</p>

---

## Features

✨ **Beautiful Mockups** — Apply stunning frames and styles to your screenshots  
🎨 **Custom Backgrounds** — Solid colors, gradients, mesh gradients, or your wallpapers  
🖼️ **Wallpaper Integration** — Automatically loads your macOS wallpapers as backgrounds  
⌨️ **Global Hotkeys** — Capture with customizable keyboard shortcuts  
🪟 **Window Capture** — Capture specific windows or the entire screen  
📐 **Social Media Presets** — Export sizes optimized for Twitter, Instagram, LinkedIn, etc.  
🔒 **Privacy First** — Blur or redact sensitive information  
🚀 **Lightweight** — Lives in your menu bar, ready when you need it  
💾 **Export Options** — Copy to clipboard or save as PNG  

## Screenshots

<p align="center">
  <img src="assets/screenshot-editor.png" width="800" alt="Clické Editor">
</p>

## Requirements

- **macOS 14.0 Sonoma** or later (macOS 15+ recommended for Liquid Glass effects)
- **Accessibility permissions** (required for global hotkeys)

## Installation

### Download

1. Download the latest `.dmg` from the [Releases](https://github.com/YOUR_USERNAME/clicke/releases) page
2. Open the `.dmg` and drag **Clické** to your Applications folder
3. Launch Clické from your Applications or Spotlight
4. Grant Accessibility permissions when prompted

### Build from Source

See [Building](#building) section below.

## Usage

### Capture a Screenshot

1. **Menu Bar**: Click the **C** icon in your menu bar → **Screenshot**
2. **Keyboard Shortcut**: Press `⌥⇧4` (Option + Shift + 4) by default
3. Select the area you want to capture
4. The editor opens automatically

### Edit Your Screenshot

- **Style Tab**: Choose mockup styles (Glass, Liquid Glass, Inset, etc.)
- **Canvas Tab**: Set background colors, gradients, or images
- **Export Tab**: Copy to clipboard or save to file

### Keyboard Shortcuts

| Action | Default Shortcut |
|--------|-----------------|
| Screenshot (area) | `⌥⇧4` |
| Window Capture | `⌥⇧T` |
| Open Preferences | `⌘,` |

Shortcuts can be customized in **Preferences → Hotkeys**.

## Building

### Prerequisites

- Xcode 16.0 or later
- macOS 14.0 SDK or later
- Apple Developer account (for code signing)

### Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/clicke.git
   cd clicke
   ```

2. Open in Xcode:
   ```bash
   open clické.xcodeproj
   ```

3. Select your development team in **Signing & Capabilities**

4. Build and run:
   - Press `⌘R` to build and run
   - Or use **Product → Archive** for release builds

### Creating a DMG

See [RELEASE.md](RELEASE.md) for detailed instructions on creating a distributable `.dmg` file.

## App Icon

To add your custom app icon:

1. Prepare your icon in the following sizes (all PNG format):
   - `icon_16x16.png` (16×16)
   - `icon_16x16@2x.png` (32×32)
   - `icon_32x32.png` (32×32)
   - `icon_32x32@2x.png` (64×64)
   - `icon_128x128.png` (128×128)
   - `icon_128x128@2x.png` (256×256)
   - `icon_256x256.png` (256×256)
   - `icon_256x256@2x.png` (512×512)
   - `icon_512x512.png` (512×512)
   - `icon_512x512@2x.png` (1024×1024)

2. Copy all files to: `clické/Assets.xcassets/AppIcon.appiconset/`

3. Update `Contents.json` to reference the filenames (see template below)

**Or use the easy method:**
1. Create a 1024×1024 PNG icon
2. Use a tool like [Icon Generator](https://appicon.co/) to generate all sizes
3. Download and replace the contents of `AppIcon.appiconset`

## Project Structure

```
clické/
├── clicke_App.swift          # App entry point
├── ContentView.swift         # Main content view
├── Assets.xcassets/          # Images and app icon
├── Coordinator/
│   ├── AppDelegate.swift     # Menu bar and hotkey setup
│   └── ScreenshotEditorWindow.swift
├── Extensions/               # Swift extensions
├── Features/
│   ├── Editor/              # Screenshot canvas and renderer
│   └── Settings/            # Preferences views
├── Managers/
│   ├── HotkeyManager.swift  # Global hotkey handling
│   └── ToastManager.swift   # Toast notifications
├── Models/
│   ├── ScreenshotStyle.swift # Styling configuration
│   └── Settings.swift       # App preferences
├── View/
│   ├── ScreenshotEditorView.swift
│   └── ToastView.swift
└── ViewModel/
    └── ScreenshotEditorViewModel.swift
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Code Style

- Follow Swift API Design Guidelines
- Use SwiftUI for all new views
- Add comments for complex logic
- Keep functions small and focused

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by [shots.so](https://shots.so)
- Uses native macOS APIs for screenshot capture
- Built with SwiftUI and AppKit

---

<p align="center">
  Made with ❤️ by <a href="https://github.com/YOUR_USERNAME">Nathan Ben Soussan</a>
</p>
