#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
test_dir="${IMOVE_TEST_DIR:-$project_dir/work/tests}"
mkdir -p "$test_dir/modules"
export CLANG_MODULE_CACHE_PATH="$test_dir/modules"
swiftc -swift-version 5 -parse-as-library -emit-module -emit-library \
  -module-name IMoveCore "$project_dir"/Sources/IMoveCore/*.swift \
  -emit-module-path "$test_dir/IMoveCore.swiftmodule" -o "$test_dir/libIMoveCore.dylib"
swiftc -swift-version 5 -parse-as-library -I "$test_dir" -L "$test_dir" -lIMoveCore \
  -Xlinker -rpath -Xlinker "$test_dir" \
  "$project_dir/Sources/IMoveApp/HostPreferences.swift" "$project_dir/Sources/IMoveApp/LocationVerification.swift" "$project_dir/Sources/IMoveApp/AppModel.swift" "$project_dir/Sources/IMoveApp/SavedPlaces.swift" "$project_dir/Sources/IMoveApp/SavedRoutes.swift" "$project_dir/Sources/IMoveApp/RailCatalogue.swift" "$project_dir/Sources/IMoveApp/WalkingRouter.swift" "$project_dir/Sources/IMoveApp/RemoteServer.swift" "$project_dir/Tests/StandaloneTests.swift" \
  -o "$test_dir/IMoveTests"
IMOVE_RAIL_FILE="$project_dir/Web/istanbul-rail.json" "$test_dir/IMoveTests"
