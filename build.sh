#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# Vercel build script — fetches Flutter SDK and builds the web app.
#
# Required Vercel environment variable:
#   WS_URL  e.g. wss://rivian-vehicle-intelligence-backend.onrender.com
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.24.5}"
FLUTTER_HOME="$HOME/flutter"

if [ ! -d "$FLUTTER_HOME" ]; then
  echo "==> Downloading Flutter $FLUTTER_VERSION"
  git clone --depth 1 -b "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi

export PATH="$FLUTTER_HOME/bin:$PATH"
flutter --disable-analytics
flutter config --no-analytics

cd flutter_app
flutter pub get

WS_URL="${WS_URL:-ws://localhost:8765}"
echo "==> Building Flutter Web with WS_URL=$WS_URL"
flutter build web --release \
  --dart-define=WS_URL="$WS_URL" \
  --base-href /

echo "==> Done. Output: flutter_app/build/web"
