# One Dockerfile for every raymart image. The build stage compiles a NATIVE raylang binary
# either from this repository (APP_DIR = services/<name>, tools/<name>) or from one of the
# reused ray-apps, cloned at a pinned commit (APP_REPO + APP_REF); the runtime stage is a
# slim Debian with just that binary.
#
# Debian trixie and not bookworm: the raylang releases link against glibc 2.39.

FROM debian:trixie-slim AS toolchain
ARG RAY_VERSION=1.27.19
ARG TARGETARCH
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git build-essential pkg-config \
    && rm -rf /var/lib/apt/lists/*
RUN arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
        arm64) triple=aarch64-unknown-linux-gnu ;; \
        amd64) triple=x86_64-unknown-linux-gnu ;; \
        *) echo "raylang has no release for $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/ray-language/raylang/releases/download/v${RAY_VERSION}/raylang-${triple}.tar.gz" \
        | tar xz -C /usr/local/bin ray raylang \
    && ray version
# The private Rust toolchain + the ray-runtime vendor: native builds then need no network.
RUN ray toolchain install

FROM toolchain AS build
ARG APP_REPO=""
ARG APP_REF=main
ARG APP_DIR=.
COPY . /src/raymart
RUN set -e; \
    if [ -n "$APP_REPO" ]; then \
        git clone --quiet "$APP_REPO" /src/app; \
        git -C /src/app checkout --quiet "$APP_REF"; \
        cd /src/app; \
    else \
        cd "/src/raymart/$APP_DIR"; \
    fi; \
    ray fetch; \
    ray build --native --release -o /out/app

FROM debian:trixie-slim AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/app /usr/local/bin/app
ENTRYPOINT ["/usr/local/bin/app"]
