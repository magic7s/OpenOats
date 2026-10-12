#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <version> <sha256> [minimum-macos-version]" >&2
  exit 1
fi

VERSION="$1"
SHA256="$2"
MINIMUM_MACOS_VERSION="${3:-}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CASK_PATH="${CASK_PATH:-$ROOT_DIR/Casks/openoats.rb}"

if [[ ! -f "$CASK_PATH" ]]; then
  echo "Cask not found at $CASK_PATH" >&2
  exit 1
fi

/usr/bin/ruby - "$CASK_PATH" "$VERSION" "$SHA256" "$MINIMUM_MACOS_VERSION" <<'RUBY'
path, version, sha256, minimum_macos = ARGV
contents = File.read(path)
contents.sub!(/version\s+"[^"]+"/, %(version "#{version}"))
contents.sub!(/sha256\s+"[^"]+"/, %(sha256 "#{sha256}"))
unless minimum_macos.empty?
  abort "Invalid minimum macOS version" unless minimum_macos.match?(/\A\d+\.\d+(?:\.\d+)?\z/)
  # Homebrew's macOS dependency DSL accepts named major releases, not minor
  # versions. The app's Info.plist and Sparkle appcast retain the exact minimum.
  releases = {
    "11" => "big_sur", "12" => "monterey", "13" => "ventura",
    "14" => "sonoma", "15" => "sequoia", "26" => "tahoe",
    "27" => "golden_gate",
  }
  release = releases[minimum_macos.split(".").first]
  abort "Unsupported minimum macOS version: #{minimum_macos}" unless release
  replacement = %(depends_on macos: :#{release})
  abort "Missing macOS dependency in cask" unless contents.sub!(/depends_on macos: [^\n]+/, replacement)
end
File.write(path, contents)
RUBY
