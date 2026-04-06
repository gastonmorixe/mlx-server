#!/usr/bin/env bash
set -euo pipefail

# Build mlx-server and compile the Metal shaders into a metallib.
#
# Usage:
#   ./build.sh              # debug build
#   ./build.sh release      # release build

CONFIG="${1:-debug}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Building MLXServer ($CONFIG)..."
if [ "$CONFIG" = "release" ]; then
    swift build -c release
else
    swift build
fi

# Locate the mlx-swift checkout where the .metal source files live
MLX_CHECKOUT="$SCRIPT_DIR/.build/checkouts/mlx-swift"
METAL_DIR="$MLX_CHECKOUT/Source/Cmlx/mlx-generated/metal"

if [ ! -d "$METAL_DIR" ]; then
    echo "ERROR: Metal shader directory not found at $METAL_DIR"
    echo "Run 'swift package resolve' first."
    exit 1
fi

BUILD_DIR="$SCRIPT_DIR/.build/$CONFIG"
METALLIB_PATH="$BUILD_DIR/mlx.metallib"

if [ -f "$METALLIB_PATH" ]; then
    echo "==> mlx.metallib already exists, skipping Metal compilation."
    echo "    (Delete $METALLIB_PATH to force recompilation.)"
else
    echo "==> Compiling Metal shaders..."
    TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT

    find "$METAL_DIR" -name "*.metal" -type f | while read -r f; do
        NAME=$(basename "$f" .metal)
        xcrun metal -c "$f" -o "$TMPDIR/$NAME.air" \
            -I "$METAL_DIR" \
            -I "$MLX_CHECKOUT/Source/Cmlx/mlx/mlx/backend/metal/kernels" \
            -std=metal3.1 -w 2>&1
    done

    echo "==> Linking metallib..."
    xcrun metallib "$TMPDIR"/*.air -o "$METALLIB_PATH"
    echo "    Created $METALLIB_PATH ($(du -h "$METALLIB_PATH" | cut -f1))"
fi

echo ""
echo "==> Build complete."
echo "    Binary: $BUILD_DIR/MLXServerCLI"
echo ""
echo "    Run:"
echo "    $BUILD_DIR/MLXServerCLI --model-path <path-to-model>"
