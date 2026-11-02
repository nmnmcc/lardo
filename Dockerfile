# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM alpine:3.23 AS download
RUN apk add --no-cache ca-certificates curl

ARG CLI_VERSION
ARG TARGETOS
ARG TARGETARCH
WORKDIR /download
RUN set -eu; \
    printf '%s\n' "$CLI_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$'; \
    test "$TARGETOS" = linux; \
    case "$TARGETARCH" in amd64|arm64) ;; *) exit 1 ;; esac; \
    archive="lark-cli-${CLI_VERSION}-linux-${TARGETARCH}.tar.gz"; \
    release="https://github.com/larksuite/cli/releases/download/v${CLI_VERSION}"; \
    curl --fail --location --silent --show-error --retry 3 \
        --connect-timeout 15 --max-time 180 "$release/$archive" -o "$archive"; \
    curl --fail --location --silent --show-error --retry 3 \
        --connect-timeout 15 --max-time 180 "$release/checksums.txt" -o checksums.txt; \
    awk -v name="$archive" '$2 == name { print; found++ } END { if (found != 1) exit 1 }' \
        checksums.txt > checksum; \
    sha256sum -c checksum; \
    tar -xzf "$archive" lark-cli LICENSE; \
    chmod 0755 lark-cli

FROM alpine:3.23
RUN apk add --no-cache ca-certificates \
    && addgroup -g 10001 lark \
    && adduser -D -u 10001 -G lark -h /data lark \
    && mkdir -p /work \
    && chown lark:lark /data /work \
    && chmod 0700 /data

ARG CLI_VERSION
LABEL org.opencontainers.image.title="lark-cli" \
      org.opencontainers.image.description="Isolated Lark/Feishu CLI with persistent state under /data" \
      org.opencontainers.image.version="${CLI_VERSION}" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.url="https://github.com/larksuite/cli"

COPY --from=download /download/lark-cli /usr/local/bin/lark-cli
COPY --from=download /download/LICENSE /usr/share/licenses/lark-cli/LICENSE

ENV HOME=/data \
    LARKSUITE_CLI_CONFIG_DIR=/data/.lark-cli \
    LARKSUITE_CLI_DATA_DIR=/data/.local/share \
    XDG_CONFIG_HOME=/data/.config \
    XDG_DATA_HOME=/data/.local/share \
    XDG_STATE_HOME=/data/.local/state \
    XDG_CACHE_HOME=/data/.cache \
    LARKSUITE_CLI_NO_UPDATE_NOTIFIER=1 \
    LARKSUITE_CLI_NO_SKILLS_NOTIFIER=1

USER 10001:10001
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/lark-cli"]
CMD ["--help"]
