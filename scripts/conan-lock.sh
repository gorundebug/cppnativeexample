#!/usr/bin/env bash
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
source "$root/scripts/conan-cache-guard.sh"
dependency_conan_cache_guard "$0" "$@"
userver_dir="${USERVER_SOURCE_DIR:-/opt/userver}"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

if [[ ! -f "$userver_dir/conanfile.py" ]]; then
  echo "userver Conan recipe is missing: $userver_dir/conanfile.py" >&2
  exit 2
fi

version() {
  python3 "$root/conan/dependencies_generated.py" "$1"
}

"$root/scripts/conan-configure-remotes.sh"
conan export "$root/conan/recipes/googleapis" --user gorundebug --channel userver
conan export "$root/conan/recipes/librdkafka" \
  --version "$(version librdkafka)" --user gorundebug --channel userver
"$root/scripts/conan-export-userver.sh" "$userver_dir" "$(version userver)"
source "$root/scripts/conan-userver-package-args.sh"
mkdir -p "$root/conan/locks"

for profile in "$root"/conan/profiles/*; do
  [[ -f "$profile" ]] || continue
  effective_profile="$temporary_dir/$(basename "$profile")"
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
  conan lock create --requires="userver/$(version userver)@gorundebug/userver" \
    --profile:host "$effective_profile" \
    --profile:build "$effective_profile" \
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
    --lockfile-out "$root/conan/locks/$(basename "$profile").lock"
done
