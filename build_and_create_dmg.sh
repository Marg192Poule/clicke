#!/bin/bash

# Script pour build et créer un DMG avec retrait de la quarantaine

PROJECT="clické.xcodeproj"
APP_PATH="build/Release/clické.app"
DMG_PATH="/Users/nath/Desktop/Clické.dmg"
TEMP_DIR="/tmp/dmg_temp"

echo "🔨 Building app..."
rm -rf build
xcodebuild -project "$PROJECT" \
    -alltargets \
    -configuration Release \
    CONFIGURATION_BUILD_DIR="$PWD/build/Release" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    INFOPLIST_FILE="clické/Info.plist" \
    INFOPLIST_KEY_LSUIElement="YES" \
    INFOPLIST_KEY_NSHighResolutionCapable="YES" \
    2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo "📦 Creating DMG..."
# Nettoyer
rm -rf "$TEMP_DIR"
rm -f "$DMG_PATH"

# Créer le dossier temporaire
mkdir -p "$TEMP_DIR"

# Copier l'app
cp -R "$APP_PATH" "$TEMP_DIR/"

# Créer le lien vers Applications
ln -s /Applications "$TEMP_DIR/Applications"

# Retirer la quarantaine de l'app
xattr -cr "$TEMP_DIR/clické.app"

# S'assurer que les permissions d'exécution sont correctes
chmod +x "$TEMP_DIR/clické.app/Contents/MacOS/clické"

# Créer le DMG
hdiutil create -volname "Clické" -srcfolder "$TEMP_DIR" -ov -format UDZO "$DMG_PATH"

# Retirer la quarantaine du DMG
xattr -cr "$DMG_PATH"

echo "✅ DMG créé : $DMG_PATH"
echo "💡 Pour installer :"
echo "   1. Ouvrez le DMG"
echo "   2. Glissez l'app dans Applications"
echo "   3. Si macOS bloque, faites Clic droit → Ouvrir"
