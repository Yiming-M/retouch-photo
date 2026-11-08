#!/bin/sh
set -eu
skill_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec /usr/bin/swift -module-cache-path "${TMPDIR:-/tmp}/retouch-photo-swift-cache" \
  "$skill_script_dir/photo.swift" "$@"
