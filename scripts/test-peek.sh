#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
TEST_BINARY="$PROJECT_DIR/.build/renotch-peek-tests"

cd "$PROJECT_DIR"
swiftc \
    -swift-version 5 \
    Sources/Renotch/Models/NotchModels.swift \
    Sources/Renotch/Models/NotchGeometry.swift \
    Sources/Renotch/Models/BrowserActivityModels.swift \
    Sources/Renotch/Models/DeveloperActivityGlance.swift \
    Sources/Renotch/Models/TransientEventModels.swift \
    Sources/Renotch/Models/MediaRemoteNowPlayingModels.swift \
    Sources/Renotch/Services/SettingsStore.swift \
    Sources/Renotch/Services/TimerService.swift \
    Sources/Renotch/Services/ShelfStore.swift \
    Sources/Renotch/Services/TodoStore.swift \
    Sources/Renotch/Services/MusicService.swift \
    Sources/Renotch/Services/BrowserActivityService.swift \
    Sources/Renotch/Services/DeveloperActivityService.swift \
    Sources/Renotch/Services/AppleCalendarService.swift \
    Sources/Renotch/Services/LaunchAtLoginService.swift \
    Sources/Renotch/Services/NotificationService.swift \
    Sources/Renotch/Services/FocusBlockerService.swift \
    Sources/Renotch/Services/MediaRemoteCommandService.swift \
    Sources/Renotch/Services/MediaRemoteNowPlayingService.swift \
    Sources/Renotch/Window/FocusBlockerOverlayController.swift \
    Sources/Renotch/State/AppModel.swift \
    Tests/AppModelPeekTests.swift \
    -framework AppKit \
    -framework EventKit \
    -framework ServiceManagement \
    -framework UserNotifications \
    -framework WebKit \
    -o "$TEST_BINARY"
"$TEST_BINARY"
