#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install_app=false
universal=false
for argument in "$@"; do
  case "$argument" in
    --install) install_app=true ;;
    --universal) universal=true ;;
    -h|--help)
      printf 'Usage: %s [--universal] [--install]\nBuild Cleo.app for macOS 14+; --universal includes Apple silicon and Intel.\n--install also copies it to ~/Applications without launching it.\n' "$0"
      exit 0
      ;;
    *) printf 'Unknown argument: %s\n' "$argument" >&2; exit 2 ;;
  esac
done

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
    printf 'DEVELOPER_DIR does not provide a working Swift compiler: %s\n' "$DEVELOPER_DIR" >&2
    exit 1
  fi
else
  developer_dir=""
  command_line_tools="/Library/Developer/CommandLineTools"
  if DEVELOPER_DIR="$command_line_tools" /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
    developer_dir="$command_line_tools"
  elif selected_dir="$(/usr/bin/xcode-select -p 2>/dev/null)" && [[ -n "$selected_dir" && "$selected_dir" != "$command_line_tools" ]]; then
    if DEVELOPER_DIR="$selected_dir" /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
      developer_dir="$selected_dir"
    fi
  fi
  if [[ -z "$developer_dir" ]]; then
    printf 'A working Xcode or Command Line Tools installation is required. Set DEVELOPER_DIR explicitly.\n' >&2
    exit 1
  fi
  export DEVELOPER_DIR="$developer_dir"
fi

build_root="$project_root/build"
staged_app="$build_root/.Cleo-build-$$.app"
output_app="$build_root/Cleo.app"
trap 'rm -rf "$staged_app"' EXIT
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources" "$build_root/ModuleCache"
shopt -s nullglob
sources=("$project_root"/Sources/Cleo/*.swift)
if [[ ${#sources[@]} -eq 0 ]]; then
  printf 'No Swift sources found in %s/Sources/Cleo.\n' "$project_root" >&2
  exit 1
fi

sdk_path="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
architectures=(arm64)
if [[ "$universal" == true ]]; then architectures+=(x86_64); fi
for architecture in "${architectures[@]}"; do
  printf 'Building %s macOS 14+ app with %s\n' "$architecture" "$DEVELOPER_DIR"
  /usr/bin/xcrun --sdk macosx swiftc \
    -O -whole-module-optimization -parse-as-library \
    -target "$architecture-apple-macosx14.0" -sdk "$sdk_path" \
    -module-cache-path "$build_root/ModuleCache" \
    "${sources[@]}" -framework AppKit \
    -o "$staged_app/Contents/MacOS/Cleo-$architecture"
done
if [[ "$universal" == true ]]; then
  /usr/bin/xcrun lipo -create "$staged_app/Contents/MacOS/Cleo-arm64" \
    "$staged_app/Contents/MacOS/Cleo-x86_64" -output "$staged_app/Contents/MacOS/Cleo"
  rm "$staged_app/Contents/MacOS/Cleo-arm64" "$staged_app/Contents/MacOS/Cleo-x86_64"
else
  mv "$staged_app/Contents/MacOS/Cleo-arm64" "$staged_app/Contents/MacOS/Cleo"
fi
cp "$project_root/Info.plist" "$staged_app/Contents/Info.plist"
if [[ -d "$project_root/Resources" ]]; then
  /usr/bin/ditto "$project_root/Resources" "$staged_app/Contents/Resources"
fi
/usr/bin/plutil -lint "$staged_app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$staged_app"
/usr/bin/codesign --verify --strict "$staged_app"
rm -rf "$output_app"
mv "$staged_app" "$output_app"
printf 'Built: %s\n' "$output_app"

if [[ "$install_app" == true ]]; then
  applications_dir="$HOME/Applications"
  installed_app="$applications_dir/Cleo.app"
  install_staging="$applications_dir/.Cleo-install-$$.app"
  mkdir -p "$applications_dir"
  /usr/bin/ditto "$output_app" "$install_staging"
  /usr/bin/codesign --verify --strict "$install_staging"
  if [[ -e "$installed_app" ]]; then
    backup_dir="$applications_dir/Cleo Backups"
    mkdir -p "$backup_dir"
    backup_app="$backup_dir/Cleo-$(date +%Y%m%d-%H%M%S)-$$.app"
    mv "$installed_app" "$backup_app"
    printf 'Previous app preserved: %s\n' "$backup_app"
  fi
  mv "$install_staging" "$installed_app"
  printf 'Installed without launching: %s\n' "$installed_app"
fi

