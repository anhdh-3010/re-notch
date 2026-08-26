#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
TEST_BINARY="$PROJECT_DIR/.build/renotch-mediaremote-tests"

cd "$PROJECT_DIR"
swiftc \
    -swift-version 5 \
    Sources/Renotch/Services/MediaRemoteCommandService.swift \
    Tests/MediaRemoteCommandServiceTests.swift \
    -o "$TEST_BINARY"
"$TEST_BINARY"
