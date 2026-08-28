ARG DEPENDENCY_DOCKER_REGISTRY=docker.io
FROM userver-source AS userver-source
FROM ${DEPENDENCY_DOCKER_REGISTRY}/library/ubuntu:24.04 AS build
ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
ARG USERVER_LTO=ON
ARG SERVICEGEN_APT_UBUNTU_ARCHIVE_URL=
ARG SERVICEGEN_APT_UBUNTU_SECURITY_URL=
ARG SERVICEGEN_APT_UBUNTU_PORTS_URL=
ARG SERVICEGEN_CONAN_REMOTE_URL=
ARG PIP_INDEX_URL=https://pypi.org/simple
ARG PIP_TRUSTED_HOST=
ENV SERVICEGEN_CONAN_REMOTE_URL=${SERVICEGEN_CONAN_REMOTE_URL}
COPY docker/userver-packages.txt /tmp/packages.txt
RUN if [ -n "$SERVICEGEN_APT_UBUNTU_ARCHIVE_URL$SERVICEGEN_APT_UBUNTU_SECURITY_URL$SERVICEGEN_APT_UBUNTU_PORTS_URL" ]; then \
      find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) -exec sed -i \
        -e "s|http://archive.ubuntu.com/ubuntu|$SERVICEGEN_APT_UBUNTU_ARCHIVE_URL|g" \
        -e "s|http://security.ubuntu.com/ubuntu|$SERVICEGEN_APT_UBUNTU_SECURITY_URL|g" \
        -e "s|http://ports.ubuntu.com/ubuntu-ports|$SERVICEGEN_APT_UBUNTU_PORTS_URL|g" {} +; \
    fi
RUN rm -f /etc/apt/apt.conf.d/docker-clean
RUN --mount=type=cache,id=servicegen-apt-lists-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,id=servicegen-apt-cache-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    apt-get update \
    && xargs apt-get install --yes --no-install-recommends < /tmp/packages.txt \
    && apt-get install --yes --no-install-recommends clang-format \
    && rm -f /tmp/packages.txt
COPY conan/dependencies_generated.py /tmp/dependencies_generated.py
RUN CONAN_VERSION="$(python3 /tmp/dependencies_generated.py conan)" \
    && python3 -m venv /opt/conan \
    && PIP_TRUSTED_HOST="$PIP_TRUSTED_HOST" \
       /opt/conan/bin/pip install --no-cache-dir --index-url "$PIP_INDEX_URL" \
       "conan==$CONAN_VERSION" \
    && rm -f /tmp/dependencies_generated.py
ENV PATH=/opt/conan/bin:$PATH
ENV CONAN_HOME=/conan
COPY --from=userver-source / /tmp/userver-source
RUN set -eu; \
    source_dir=/tmp/userver-source; \
    archive=$(find "$source_dir" -mindepth 1 -maxdepth 1 -type f \( -name context -o -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.tar.xz' \) -print -quit); \
    if [ -n "$archive" ]; then \
      mkdir -p /tmp/userver-archive; \
      tar -xf "$archive" -C /tmp/userver-archive; \
      source_dir=/tmp/userver-archive; \
    fi; \
    manifest="$source_dir/CMakeLists.txt"; \
    if [ ! -f "$manifest" ]; then manifest=$(find "$source_dir" -mindepth 2 -maxdepth 2 -type f -name CMakeLists.txt -print -quit); fi; \
    if [ -z "$manifest" ]; then echo "userver source context has no CMakeLists.txt" >&2; exit 1; fi; \
    source_dir=${manifest%/CMakeLists.txt}; \
    mkdir -p /opt/userver; \
    cp -a "$source_dir/." /opt/userver/; \
    rm -rf /tmp/userver-source /tmp/userver-archive
WORKDIR /workspace
COPY conan ./conan
COPY scripts/conan-configure-remotes.sh scripts/conan-install.sh scripts/run_with_progress.sh ./scripts/

FROM build AS build-dependencies
RUN --mount=type=cache,id=cppnative-ccache-${TARGETARCH},target=/root/.cache/ccache \
    --mount=type=cache,id=servicegen-conan2-${TARGETARCH},target=/conan,sharing=locked \
    ./scripts/run_with_progress.sh "Conan Release install" \
      ./scripts/conan-install.sh Release /workspace/build/conan-release

FROM build-dependencies AS build-application
COPY CMakeLists.txt ./
COPY proto ./proto
COPY scripts ./scripts
COPY src ./src
RUN --mount=type=cache,id=cppnative-ccache-${TARGETARCH},target=/root/.cache/ccache \
    --mount=type=cache,id=servicegen-conan2-${TARGETARCH},target=/conan,sharing=locked \
    conan_toolchain="$(cat /workspace/build/conan-release/toolchain.path)" \
    && ./scripts/run_with_progress.sh "Release configure" \
      cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_TOOLCHAIN_FILE="${conan_toolchain}" \
      -DUSERVER_LTO="${USERVER_LTO}" \
      -DUSERVER_FEATURE_TESTSUITE=OFF \
      -DUSERVER_FEATURE_UTEST=OFF \
    && ./scripts/run_with_progress.sh "Release build" \
      cmake --build build --target inventoryservice orderservice --parallel

FROM ${DEPENDENCY_DOCKER_REGISTRY}/library/ubuntu:24.04 AS runtime
ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
ARG SERVICEGEN_APT_UBUNTU_ARCHIVE_URL=
ARG SERVICEGEN_APT_UBUNTU_SECURITY_URL=
ARG SERVICEGEN_APT_UBUNTU_PORTS_URL=
RUN if [ -n "$SERVICEGEN_APT_UBUNTU_ARCHIVE_URL$SERVICEGEN_APT_UBUNTU_SECURITY_URL$SERVICEGEN_APT_UBUNTU_PORTS_URL" ]; then \
      find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) -exec sed -i \
        -e "s|http://archive.ubuntu.com/ubuntu|$SERVICEGEN_APT_UBUNTU_ARCHIVE_URL|g" \
        -e "s|http://security.ubuntu.com/ubuntu|$SERVICEGEN_APT_UBUNTU_SECURITY_URL|g" \
        -e "s|http://ports.ubuntu.com/ubuntu-ports|$SERVICEGEN_APT_UBUNTU_PORTS_URL|g" {} +; \
    fi
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
COPY --from=build-application /workspace/build/inventoryservice /usr/local/bin/inventoryservice
ENTRYPOINT ["/usr/local/bin/entrypoint", "inventory"]

FROM runtime AS orderservice
COPY config/orders.static_config.yaml /app/config/orders.static_config.yaml
COPY --from=build-application /workspace/build/orderservice /usr/local/bin/orderservice
ENTRYPOINT ["/usr/local/bin/entrypoint", "orders"]
