#!/bin/sh
set -eu

CREW_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$CREW_ROOT"
CREW_SWIFTC=$(xcrun --find swiftc)
CREW_TOOLCHAIN=${CREW_SWIFTC%/usr/bin/swiftc}
CREW_TEST_MACROS="$CREW_TOOLCHAIN/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -f "$CREW_TEST_MACROS" ]; then
    swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$CREW_TEST_MACROS" "$@"
else
    swift test --disable-xctest "$@"
fi
