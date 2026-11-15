#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
python_bin="${IMOVE_BUILD_PYTHON:-python3.13}"
venv_dir="$project_dir/.build-usb-venv"
dist_dir="$project_dir/.usb-dist"
build_dir="$project_dir/.usb-build"

"$python_bin" -m venv "$venv_dir"
"$venv_dir/bin/python" -m pip install 'pymobiledevice3==11.19.1' 'pyinstaller==6.22.3'
mkdir -p "$build_dir/config"
PYINSTALLER_CONFIG_DIR="$build_dir/config" "$venv_dir/bin/pyinstaller" \
  --noconfirm --clean --onedir --console --target-arch arm64 \
  --name pymobiledevice3 --collect-all pymobiledevice3 \
  --recursive-copy-metadata pymobiledevice3 \
  --distpath "$dist_dir" --workpath "$build_dir/work" --specpath "$build_dir" \
  "$project_dir/scripts/usb_entry.py"
"$dist_dir/pymobiledevice3/pymobiledevice3" version
