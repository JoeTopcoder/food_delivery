#!/usr/bin/env bash
# Build both web apps to their separate output directories.
# Usage: ./build_web.sh [restaurant|admin|both]
# Default: builds both.
set -euo pipefail

TARGET="${1:-both}"

build_restaurant() {
  echo ""
  echo "===> Building RESTAURANT web app..."
  flutter build web \
    --dart-define=WEB_MODE=restaurant \
    --output build/web_restaurant \
    --release
  echo "===> Restaurant build complete -> build/web_restaurant/"
}

build_admin() {
  echo ""
  echo "===> Building ADMIN web app..."
  flutter build web \
    --dart-define=WEB_MODE=admin \
    --output build/web_admin \
    --release
  echo "===> Admin build complete -> build/web_admin/"
}

case "$TARGET" in
  restaurant) build_restaurant ;;
  admin)      build_admin ;;
  *)          build_restaurant; build_admin ;;
esac

echo ""
echo "Done!"
