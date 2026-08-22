# syntax=docker/dockerfile:1
FROM userver-source AS userver-source
FROM ubuntu:24.04 AS build
ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
ARG USERVER_LTO=ON
COPY docker/userver-packages.txt /tmp/packages.txt
RUN rm -f /etc/apt/apt.conf.d/docker-clean
RUN --mount=type=cache,id=servicegen-apt-lists-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,id=servicegen-apt-cache-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    apt-get update \
    && xargs apt-get install --yes --no-install-recommends < /tmp/packages.txt \
    && apt-get install --yes --no-install-recommends clang-format \
    && rm -f /tmp/packages.txt
COPY --from=userver-source / /opt/userver
WORKDIR /workspace
COPY CMakeLists.txt ./
COPY proto ./proto
COPY scripts ./scripts
COPY src ./src
RUN --mount=type=cache,id=cppnative-ccache-${TARGETARCH},target=/root/.cache/ccache \
    --mount=type=cache,id=cppnative-userver3.1-grpc1.59.1-protobuf5.26.0-cpm-${TARGETARCH},target=/var/cache/cpm-source,sharing=locked \
    mkdir -p /var/cache/cpm-source/http_archives /workspace/build \
    && ln -sfn /var/cache/cpm-source/http_archives /workspace/build/http_archives \
    && CPM_SOURCE_CACHE=/var/cache/cpm-source \
    ./scripts/run_with_progress.sh "Release configure" \
      cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DUSERVER_LTO="${USERVER_LTO}" \
      -DUSERVER_FEATURE_TESTSUITE=OFF \
      -DUSERVER_FEATURE_UTEST=OFF \
    && ./scripts/run_with_progress.sh "Release build" \
      cmake --build build --target inventoryservice orderservice --parallel

FROM ubuntu:24.04 AS runtime
ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
RUN rm -f /etc/apt/apt.conf.d/docker-clean
RUN --mount=type=cache,id=servicegen-apt-lists-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,id=servicegen-apt-cache-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    apt-get update \
    && apt-get install --yes --no-install-recommends \
      ca-certificates \
      libcctz2 \
      libboost-filesystem1.83.0 \
      libboost-iostreams1.83.0 \
      libboost-locale1.83.0 \
      libboost-program-options1.83.0 \
      libboost-stacktrace1.83.0 \
      libcrypto++8t64 \
      libcurl4t64 \
      libev4t64 \
      libfmt9 \
      libjemalloc2 \
      libnghttp2-14 \
      libre2-10 \
      libyaml-cpp0.8 \
      libzstd1
WORKDIR /app
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint

FROM runtime AS inventoryservice
COPY config/inventory.static_config.yaml /app/config/inventory.static_config.yaml
COPY --from=build /workspace/build/inventoryservice /usr/local/bin/inventoryservice
ENTRYPOINT ["/usr/local/bin/entrypoint", "inventory"]

FROM runtime AS orderservice
COPY config/orders.static_config.yaml /app/config/orders.static_config.yaml
COPY --from=build /workspace/build/orderservice /usr/local/bin/orderservice
ENTRYPOINT ["/usr/local/bin/entrypoint", "orders"]
