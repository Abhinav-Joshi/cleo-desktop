#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skip_build=false
case "${1:-}" in
  "") ;;
  --skip-build) skip_build=true ;;
  -h|--help)
    printf 'Usage: %s [--skip-build]\nBuild a universal Cleo app and package it for transfer without installing or launching it.\n' "$0"
    exit 0
    ;;
  *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then printf 'Expected at most one argument.\n' >&2; exit 2; fi

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  developer_dir=""
  command_line_tools="/Library/Developer/CommandLineTools"
  if DEVELOPER_DIR="$command_line_tools" /usr/bin/xcrun --find lipo >/dev/null 2>&1; then
    developer_dir="$command_line_tools"
  elif selected_dir="$(/usr/bin/xcode-select -p 2>/dev/null)" && [[ -n "$selected_dir" && "$selected_dir" != "$command_line_tools" ]]; then
    if DEVELOPER_DIR="$selected_dir" /usr/bin/xcrun --find lipo >/dev/null 2>&1; then
      developer_dir="$selected_dir"
    fi
  fi
  if [[ -n "$developer_dir" ]]; then
    export DEVELOPER_DIR="$developer_dir"
  fi
fi
if [[ "$skip_build" == false ]]; then "$project_root/scripts/build.sh" --universal; fi

app="$project_root/build/Cleo.app"
executable="$app/Contents/MacOS/Cleo"
plist="$app/Contents/Info.plist"
if [[ ! -x "$executable" ]]; then printf 'Missing built app: %s\n' "$app" >&2; exit 1; fi
/usr/bin/codesign --verify --deep --strict "$app"
architectures="$(/usr/bin/xcrun lipo -archs "$executable")"
for architecture in arm64 x86_64; do
  if [[ " $architectures " != *" $architecture "* ]]; then
    printf 'Packaging requires arm64 and x86_64; found: %s\n' "$architectures" >&2
    exit 1
  fi
done
for family in cleo turn bark; do
  for index in {0..15}; do
    printf -v resource '%s/Contents/Resources/%s-%02d.png' "$app" "$family" "$index"
    if [[ ! -f "$resource" ]]; then printf 'Missing sprite: %s\n' "$resource" >&2; exit 1; fi
  done
done
if [[ ! -f "$app/Contents/Resources/Cleo.icns" ]]; then printf 'Missing app icon.\n' >&2; exit 1; fi

version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$plist")"
bundle_version="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$plist")"
minimum_macos="$(/usr/bin/plutil -extract LSMinimumSystemVersion raw -o - "$plist")"
identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$plist")"
for value in "$version" "$bundle_version" "$minimum_macos" "$identifier"; do
  if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then printf 'Unexpected bundle metadata.\n' >&2; exit 1; fi
done
signing_details="$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1)"
signing_kind=other-verified-signature
if [[ "$signing_details" == *"Signature=adhoc"* ]]; then signing_kind=ad-hoc; fi

output_dir="$project_root/build/distribution"
mkdir -p "$output_dir"
staging="$(/usr/bin/mktemp -d "$output_dir/.cleo-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir "$staging/payload"
/usr/bin/ditto --norsrc --noextattr --noacl "$app" "$staging/payload/Cleo.app"
/usr/bin/codesign --verify --deep --strict "$staging/payload/Cleo.app"

archive_name="Cleo-$version-macOS-universal-preview.zip"
stem="${archive_name%.zip}"
cat > "$staging/payload/Read Me.txt" <<EOF
Cleo $version — macOS preview

Requires macOS $minimum_macos or later on an Apple silicon or Intel Mac.
This download contains the complete app. No Xcode, source code, account,
network connection, or extra runtime installation is needed to use Cleo.

1. Double-click the ZIP to extract it.
2. Drag Cleo.app into your Applications folder.
3. Open Cleo.app. Look for the paw icon in the menu bar; there is no Dock icon.
4. Use the paw menu to change her size, corner, display, and sleepy hours;
   play with a stick or ball; hide, pause, snooze, or quit her.

This preview is not a Developer ID signed, notarized release. macOS may
block its first launch. If you trust the sender and want to run this preview,
first attempt to open it, then go to System Settings > Privacy & Security,
choose Open Anyway for Cleo, and confirm Open. The option may require
scrolling. Do not disable macOS security settings or remove quarantine.
Apple's instructions: https://support.apple.com/en-us/102445

Cleo does not ask for Accessibility, Screen Recording, or Input Monitoring
permission. She does not start at login automatically. Hover over her while
she sits in her corner for a silent bark and wag; click to pet her. While
sleeping she stays curled up and gives a quiet eye-opening tail-wag greeting.

To remove Cleo, choose Quit Cleo from the paw menu, then delete Cleo.app.
EOF

/usr/bin/ditto -c -k --norsrc --noextattr --noacl "$staging/payload" "$staging/$archive_name"
mkdir "$staging/unpacked"
/usr/bin/ditto -x -k "$staging/$archive_name" "$staging/unpacked"
/usr/bin/codesign --verify --deep --strict "$staging/unpacked/Cleo.app"
unpacked_architectures="$(/usr/bin/xcrun lipo -archs "$staging/unpacked/Cleo.app/Contents/MacOS/Cleo")"
if [[ "$unpacked_architectures" != "$architectures" ]]; then printf 'Architecture mismatch after ZIP extraction.\n' >&2; exit 1; fi

archive_sha="$(/usr/bin/shasum -a 256 "$staging/$archive_name" | /usr/bin/awk '{print $1}')"
archive_bytes="$(/usr/bin/stat -f%z "$staging/$archive_name")"
bundle_disk_kib="$(/usr/bin/du -sk "$staging/unpacked/Cleo.app" | /usr/bin/awk '{print $1}')"
created_at="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s  %s\n' "$archive_sha" "$archive_name" > "$staging/$stem.sha256"
cat > "$staging/$stem.json" <<EOF
{
  "app": "Cleo",
  "version": "$version",
  "bundleVersion": "$bundle_version",
  "bundleIdentifier": "$identifier",
  "minimumMacOS": "$minimum_macos",
  "architectures": ["arm64", "x86_64"],
  "signing": "$signing_kind",
  "notarization": "not-verified",
  "distributionStatus": "preview",
  "archive": "$archive_name",
  "archiveBytes": $archive_bytes,
  "bundleDiskKiB": $bundle_disk_kib,
  "sha256": "$archive_sha",
  "createdAtUTC": "$created_at"
}
EOF
/usr/bin/plutil -create xml1 "$staging/metadata-validation.plist"
/usr/bin/plutil -insert metadata -json "$(cat "$staging/$stem.json")" "$staging/metadata-validation.plist"
cp "$staging/payload/Read Me.txt" "$staging/$stem-Install.txt"
for filename in "$archive_name" "$stem.sha256" "$stem.json" "$stem-Install.txt"; do
  mv -f "$staging/$filename" "$output_dir/$filename"
done
printf 'Package: %s/%s (%s bytes)\nSHA-256: %s\n' "$output_dir" "$archive_name" "$archive_bytes" "$archive_sha"
printf 'Universal %s; signature %s; notarization not verified. Nothing was installed, launched, or published.\n' "$architectures" "$signing_kind"
