#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p apple/.build
cabal run hastellcolor-metal -- --check
cabal run hastellcolor-metal -- --fixtures apple/.build/reference.json
xcrun swiftc -O -module-cache-path apple/.build/ModuleCache \
    apple/HastellColor/Drawing.swift apple/HastellColor/Paper.swift apple/HastellColor/MetalPainter.swift \
    apple/Tests/RendererChecks.swift -o apple/.build/renderer-checks
apple/.build/renderer-checks apple/HastellColor/Generated/Paint.metal apple/.build/reference.json
