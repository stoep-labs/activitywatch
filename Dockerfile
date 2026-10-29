FROM debian:bookworm-slim

WORKDIR /app

# Pre-built Linux zip from the GitHub Actions Build workflow artifact
# (builds-ubuntu-22.04-py3.9 → activitywatch-*.zip).
COPY activitywatch-*.zip /tmp/aw.zip

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates unzip \
 && unzip -q /tmp/aw.zip -d /app \
 && rm /tmp/aw.zip \
 && chmod +x /app/activitywatch/aw-server-rust/aw-server-rust \
 && apt-get purge -y --auto-remove unzip \
 && rm -rf /var/lib/apt/lists/*

EXPOSE 5600
CMD ["/app/activitywatch/aw-server-rust/aw-server-rust", "--host", "0.0.0.0", "--profile", "default"]
