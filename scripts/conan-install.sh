#!/usr/bin/env bash
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
source "$root/scripts/conan-cache-guard.sh"
dependency_conan_cache_guard "$0" "$@"
userver_dir="${USERVER_SOURCE_DIR:-/opt/userver}"
build_type="${1:-Release}"
output_dir="${2:-$root/build/conan-${build_type,,}}"
profile="${CPPNATIVE_CONAN_PROFILE:-}"

if [[ ! -f "$userver_dir/conanfile.py" ]]; then
  echo "userver Conan recipe is missing: $userver_dir/conanfile.py" >&2
  exit 2
fi

if [[ -z "$profile" ]]; then
  case "$(uname -s):$(uname -m)" in
    Linux:aarch64|Linux:arm64)
      profile="$root/conan/profiles/linux-gcc-armv8"
      ;;
    Linux:x86_64)
      profile="$root/conan/profiles/linux-gcc-x86_64"
      ;;
    Darwin:arm64)
      profile="$root/conan/profiles/macos-apple-clang-armv8"
      ;;
    *)
      echo "unsupported Conan host: $(uname -s) $(uname -m)" >&2
      exit 1
      ;;
  esac
fi

version() {
  python3 "$root/conan/dependencies_generated.py" "$1"
}

mkdir -p "$output_dir"
output_dir="$(CDPATH= cd -- "$output_dir" && pwd)"
effective_profile="$output_dir/cppnative-userver.profile"
cp "$profile" "$effective_profile"
cat "$root/conan/userver-options.generated.profile" >>"$effective_profile"
cat >>"$effective_profile" <<EOF

[replace_requires]
boost/*: boost/$(version userver-boost)
grpc/*: grpc/$(version grpc)
googleapis/*: googleapis/$(version userver-googleapis)@gorundebug/userver
gtest/*: gtest/$(version userver-googletest)
librdkafka/*: librdkafka/$(version librdkafka)@gorundebug/userver
opentelemetry-proto/*: opentelemetry-proto/$(version userver-opentelemetry-proto)
openssl/*: openssl/$(version openssl)
protobuf/*: protobuf/$(version protobuf)
re2/*: re2/$(version re2)
yaml-cpp/*: yaml-cpp/$(version yaml-cpp)

[replace_tool_requires]
protobuf/*: protobuf/$(version protobuf)
EOF

"$root/scripts/conan-configure-remotes.sh"
conan export "$root/conan/recipes/googleapis" --user gorundebug --channel userver
conan export "$root/conan/recipes/librdkafka" \
  --version "$(version librdkafka)" --user gorundebug --channel userver
"$root/scripts/conan-export-userver.sh" "$userver_dir" "$(version userver)"
source "$root/scripts/conan-userver-package-args.sh"

source_download_cache="${CPPNATIVE_CONAN_SOURCE_CACHE:-$(conan config home)/source-download-cache}"
mkdir -p "$source_download_cache"
lockfile="${CPPNATIVE_CONAN_LOCKFILE:-$root/conan/locks/$(basename "$profile").lock}"
lock_args=()
if [[ "$lockfile" != "none" ]]; then
  if [[ ! -f "$lockfile" ]]; then
    echo "Conan lockfile is missing: $lockfile; run scripts/conan-lock.sh" >&2
    exit 2
  fi
  lock_args=(--lockfile "$lockfile")
fi

(
  # Keep every Conan-generated consumer file in the writable build tree.
  cd "$output_dir"
  conan install --requires="userver/$(version userver)@gorundebug/userver" \
    --profile:host "$effective_profile" \
    --profile:build "$effective_profile" \
    -s:h "build_type=$build_type" \
    -s:b "build_type=$build_type" \
    -o "userver/*:with_mongodb=False" \
    -o "userver/*:with_postgresql=False" \
    -o "userver/*:with_redis=False" \
    -o "userver/*:with_clickhouse=False" \
    -o "userver/*:with_rabbitmq=False" \
    -o "userver/*:with_sqlite=False" \
    -o "userver/*:with_s3api=False" \
    -o "userver/*:with_easy=False" \
    -o "userver/*:with_grpc=True" \
    -o "userver/*:with_kafka=True" \
    -o "userver/*:with_otlp=True" \
    -o "userver/*:with_utest=True" \
    -o "userver/*:with_grpc_reflection=False" \
    -o "userver/*:with_grpc_protovalidate=False" \
    "${userver_package_args[@]}" \
    -o:h "openssl/*:no_engine=False" \
    -o:b "openssl/*:no_engine=False" \
    --build=missing \
    -cc "core.sources:download_cache=$source_download_cache" \
    -c "tools.cmake.cmaketoolchain:user_presets=$output_dir/CMakeUserPresets.json" \
    -g CMakeDeps \
    -g CMakeToolchain \
    "${lock_args[@]}" \
    --output-folder="$output_dir" \
    "${@:3}"
)

toolchain="$output_dir/conan_toolchain.cmake"
if [[ ! -f "$toolchain" ]]; then
  echo "Conan toolchain is missing: $toolchain" >&2
  exit 2
fi
printf '%s\n' "$toolchain" >"$output_dir/toolchain.path"
