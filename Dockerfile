FROM alpine:3.21

# Install Tor, obfs4proxy, and Snowflake proxy (~20MB total)
RUN apk add --no-cache \
    tor \
    obfs4proxy \
    bash \
    curl \
    && rm -rf /var/cache/apk/*

# Install Snowflake proxy from official release
ARG SNOWFLAKE_VERSION=2.9.2
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64) SNOWFLAKE_ARCH="amd64" ;; \
      aarch64) SNOWFLAKE_ARCH="arm64" ;; \
      armv7l) SNOWFLAKE_ARCH="arm" ;; \
      *) echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL "https://gitlab.torproject.org/api/v4/projects/tpo%2Fanti-censorship%2Fplugitable-transports%2Fsnowflake/packages/generic/snowflake/${SNOWFLAKE_VERSION}/proxy-${SNOWFLAKE_VERSION}-linux-${SNOWFLAKE_ARCH}" \
      -o /usr/local/bin/snowflake-proxy && \
    chmod +x /usr/local/bin/snowflake-proxy

# Create directories
RUN mkdir -p /var/lib/tor /var/log/tor /data \
    && chown -R tor:tor /var/lib/tor /var/log/tor /data

# Copy scripts
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Persistent data
VOLUME ["/data"]

# Ports: ORPort, obfs4, Snowflake metrics
EXPOSE 9001 9002 9999

ENTRYPOINT ["/entrypoint.sh"]
