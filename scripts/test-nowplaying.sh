#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
TEST_BINARY="$PROJECT_DIR/.build/renotch-nowplaying-tests"

cd "$PROJECT_DIR"
swiftc \
    -swift-version 5 \
    Sources/Renotch/Models/NotchModels.swift \
    Sources/Renotch/Models/TransientEventModels.swift \
    Sources/Renotch/Models/MediaRemoteNowPlayingModels.swift \
    Tests/MediaRemoteNowPlayingTests.swift \
    -framework AppKit \
    -o "$TEST_BINARY"
"$TEST_BINARY"
