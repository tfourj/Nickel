#!/bin/zsh  # Use zsh for better error handling

# Configuration
PROJECT_NAME="Nickel"
SCHEME_NAME="Nickel"
BUILD_DIR="build"

VERSION=$(grep 'SHARED_VERSION_NUMBER' Nickel.xcodeproj/project.pbxproj | head -n 1 | sed -E 's/.*SHARED_VERSION_NUMBER = ([0-9\.]+);.*/\1/')
IPA_NAME="Nickel-${VERSION}-uBeta.ipa"
echo "Extracted version: ${VERSION}"
echo "IPA will be named: ${IPA_NAME}"

# Clean build directory
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

echo "--- Archiving project ---"
xcodebuild clean archive \
  -project "$PROJECT_NAME.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -archivePath "$BUILD_DIR/archive.xcarchive" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO || { echo "Archive failed"; exit 1; }

# Verify archive contents
APP_PATH="$BUILD_DIR/archive.xcarchive/Products/Applications/$PROJECT_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "❌ Missing .app file in archive!"
  exit 1
fi

echo "--- Packaging IPA ---"
IPA_PATH="$BUILD_DIR/${IPA_NAME}"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
cd "$BUILD_DIR"
zip -qr "${IPA_NAME}" Payload || { echo "IPA creation failed"; exit 1; }
cd ..
rm -rf "$BUILD_DIR/Payload"

echo "✅ Unsigned IPA created at: $IPA_PATH"
