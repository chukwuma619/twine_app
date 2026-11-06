#!/bin/sh
set -e
cd "$(dirname "$0")/.."
flutter_rust_bridge_codegen generate
