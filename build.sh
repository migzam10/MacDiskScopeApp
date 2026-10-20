#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MacDiskScope"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 Compilando ${APP_NAME}.app nativa para macOS..."

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.migzam.macdiskscope</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>MacDiskScope</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>MacDiskScope necesita acceso para analizar el tamaño de los archivos y detectar duplicados en tu Escritorio.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>MacDiskScope necesita acceso para analizar el tamaño de los archivos y detectar duplicados en tus Documentos.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>MacDiskScope necesita acceso para analizar el tamaño de los archivos y detectar duplicados en tus Descargas.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>MacDiskScope necesita acceso para analizar discos externos o volúmenes seleccionados.</string>
</dict>
</plist>
EOF

swiftc -O \
    -parse-as-library \
    Sources/Models.swift \
    Sources/DiskScanner.swift \
    Sources/TreemapView.swift \
    Sources/CategoryAndFilesView.swift \
    Sources/DuplicatesView.swift \
    Sources/ContentView.swift \
    Sources/MacDiskScopeApp.swift \
    -o "${MACOS_DIR}/${APP_NAME}"

chmod +x "${MACOS_DIR}/${APP_NAME}"

echo "✅ Compilación exitosa: $(pwd)/${APP_BUNDLE}"
echo "🚀 Para abrir la aplicación ejecuta: open ${APP_BUNDLE}"
