# Releasing Clické

This guide covers how to build, sign, and distribute Clické as a `.dmg` file for your website.

## Prerequisites

- **Xcode 16+** installed
- **Apple Developer Account** (for code signing)
- **create-dmg** tool (optional, for fancy DMGs)

## 1. Prepare for Release

### Update Version Number

1. Open `clické.xcodeproj` in Xcode
2. Select the project in the navigator
3. Select the **clické** target
4. Go to **General** tab
5. Update:
   - **Version**: Semantic version (e.g., `1.0.0`, `1.1.0`)
   - **Build**: Increment for each build (e.g., `1`, `2`, `3`)

### Verify Settings

Ensure these settings are correct in **Signing & Capabilities**:

- ✅ **Automatically manage signing**: Enabled
- ✅ **Team**: Your Apple Developer Team
- ✅ **Hardened Runtime**: Enabled
- ✅ **App Sandbox**: Enabled

## 2. Archive the App

### Using Xcode

1. Set the scheme to **Any Mac (Apple Silicon, Intel)**
2. Go to **Product → Archive**
3. Wait for the build to complete
4. The Organizer window will open with your archive

### Validate (Optional but Recommended)

1. Select your archive in Organizer
2. Click **Validate App**
3. Choose **Developer ID** distribution
4. Fix any issues that appear

## 3. Export the App

### For Direct Distribution (Website)

1. In Organizer, select your archive
2. Click **Distribute App**
3. Choose **Developer ID** (for distribution outside the App Store)
4. Select **Export** (not Upload)
5. Choose your signing certificate
6. Wait for notarization (this can take a few minutes)
7. Click **Export** and choose a destination folder

The exported `.app` will be code-signed and notarized, ready for distribution.

### For Development/Testing

If you don't have a paid Developer account:

1. Click **Distribute App**
2. Choose **Copy App** 
3. The `.app` will be unsigned (users will need to right-click → Open to launch)

## 4. Create the DMG

### Option A: Quick DMG (Built-in macOS)

```bash
# Create a temporary folder
mkdir -p ~/Desktop/dmg-contents

# Copy your app
cp -R "/path/to/exported/clické.app" ~/Desktop/dmg-contents/

# Create Applications symlink
ln -s /Applications ~/Desktop/dmg-contents/Applications

# Create DMG
hdiutil create -volname "Clické" \
    -srcfolder ~/Desktop/dmg-contents \
    -ov -format UDZO \
    ~/Desktop/Clicke-1.0.0.dmg

# Clean up
rm -rf ~/Desktop/dmg-contents
```

### Option B: Fancy DMG with create-dmg (Recommended)

Install create-dmg:
```bash
brew install create-dmg
```

Create a styled DMG:
```bash
create-dmg \
    --volname "Clické" \
    --volicon "/path/to/icon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "clické.app" 150 190 \
    --hide-extension "clické.app" \
    --app-drop-link 450 190 \
    --background "/path/to/dmg-background.png" \
    "Clicke-1.0.0.dmg" \
    "/path/to/exported/clické.app"
```

### Option C: Disk Utility (GUI Method)

1. Open **Disk Utility**
2. Go to **File → New Image → Image from Folder...**
3. Select your folder containing `clické.app` and the Applications alias
4. Name: `Clické`
5. Format: **compressed**
6. Click **Save**

## 5. Notarize the DMG (Important!)

If your `.app` wasn't notarized during export, or if you created the DMG manually:

```bash
# Submit for notarization
xcrun notarytool submit Clicke-1.0.0.dmg \
    --apple-id "your@email.com" \
    --password "app-specific-password" \
    --team-id "YOUR_TEAM_ID" \
    --wait

# Staple the notarization ticket
xcrun stapler staple Clicke-1.0.0.dmg
```

To get an app-specific password:
1. Go to https://appleid.apple.com
2. Sign in
3. App-Specific Passwords → Generate

## 6. Test the DMG

Before distributing:

1. **Clean test**: Delete any existing Clické installations
2. **Open the DMG** on a different Mac or user account
3. **Drag to Applications** and verify it copies correctly
4. **Launch the app** and verify it works
5. **Check permissions**: Ensure Accessibility permission prompt appears

## 7. Distribute

### GitHub Releases (Recommended)

1. Create a new release on GitHub
2. Tag: `v1.0.0`
3. Title: `Clické 1.0.0`
4. Upload `Clicke-1.0.0.dmg` as an asset
5. Add release notes

### Your Website

1. Upload `Clicke-1.0.0.dmg` to your web server
2. Create a download page with:
   - Download button
   - System requirements
   - Installation instructions
   - Screenshot/preview

Example download page HTML:
```html
<section class="download">
    <h2>Download Clické</h2>
    <p>Version 1.0.0 · macOS 14.0+</p>
    
    <a href="/downloads/Clicke-1.0.0.dmg" class="download-button">
        Download for Mac
    </a>
    
    <h3>Installation</h3>
    <ol>
        <li>Open the downloaded .dmg file</li>
        <li>Drag Clické to Applications</li>
        <li>Launch from Spotlight or Applications</li>
        <li>Grant Accessibility permissions when prompted</li>
    </ol>
</section>
```

## 8. Update Process

When releasing updates:

1. Increment version number
2. Archive and export new build
3. Create new DMG: `Clicke-1.1.0.dmg`
4. Notarize and staple
5. Create GitHub release with changelog
6. Update website download link

## Troubleshooting

### "App is damaged" error

The app wasn't properly notarized. Solutions:
- Re-export with notarization from Xcode
- Or run: `xattr -cr /Applications/clické.app`

### Gatekeeper blocks the app

User needs to:
1. Right-click the app
2. Select **Open**
3. Click **Open** in the dialog

### App won't launch (code signature invalid)

Re-sign the app:
```bash
codesign --force --deep --sign "Developer ID Application: Your Name" /path/to/clické.app
```

## Checklist

Before each release:

- [ ] Version number updated
- [ ] Build number incremented
- [ ] All features tested
- [ ] Archive created
- [ ] App notarized
- [ ] DMG created
- [ ] DMG notarized and stapled
- [ ] Tested on clean install
- [ ] Release notes written
- [ ] Uploaded to GitHub/website

---

Happy releasing! 🚀
