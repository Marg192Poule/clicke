#!/bin/bash

# Script pour créer un DMG avec retrait de la quarantaine

APP_PATH="build/Release/clické.app"
DMG_PATH="/Users/nath/Desktop/Clické.dmg"
TEMP_DIR="/tmp/dmg_temp"

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
