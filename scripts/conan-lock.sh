#!/usr/bin/env bash
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
userver_dir="${USERVER_SOURCE_DIR:-/opt/userver}"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

version() {
  python3 "$root/conan/dependencies_generated.py" "$1"
}

"$root/scripts/conan-configure-remotes.sh"
conan export "$root/conan/recipes/googleapis"
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
googleapis/*: googleapis/$(version userver-googleapis)
gtest/*: gtest/$(version userver-googletest)
librdkafka/*: librdkafka/$(version librdkafka)
opentelemetry-proto/*: opentelemetry-proto/$(version userver-opentelemetry-proto)
protobuf/*: protobuf/$(version protobuf)
re2/*: re2/$(version re2)
yaml-cpp/*: yaml-cpp/$(version yaml-cpp)

[replace_tool_requires]
protobuf/*: protobuf/$(version protobuf)
EOF
  conan lock create "$userver_dir" \
    --profile:host "$effective_profile" \
    --profile:build "$effective_profile" \
    -o "&:with_mongodb=False" \
    -o "&:with_postgresql=False" \
    -o "&:with_redis=False" \
    -o "&:with_clickhouse=False" \
    -o "&:with_rabbitmq=False" \
    -o "&:with_sqlite=False" \
    -o "&:with_s3api=False" \
    -o "&:with_easy=False" \
    -o "&:with_grpc=True" \
    -o "&:with_kafka=False" \
    -o "&:with_otlp=False" \
    -o "&:with_utest=False" \
    -o "&:with_grpc_reflection=False" \
    -o "&:with_grpc_protovalidate=False" \
    --lockfile-out "$root/conan/locks/$(basename "$profile").lock"
done
