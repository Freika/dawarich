# Runtime libraries for the prebuilt maplibre-native Node binding
# (vendor/poster_renderer). The binary is built on Ubuntu 24.04 and links
# lib versions Debian doesn't ship (libicu74, libjpeg8) — vendor exactly
# those .so files and load them via LD_LIBRARY_PATH scoped to the renderer.
FROM ubuntu:24.04 AS mbgl_libs
# Only 64-bit targets ship the prebuilt maplibre-native binding (see the armv7
# skip below), so vendor these libs there only. On 32-bit armhf, Ubuntu 24.04's
# 64-bit time_t transition renamed libuv1/libpng16-16 to *t64, which would break
# the install for libraries armv7 never loads anyway — emit an empty /out.
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "amd64" ] || [ "$TARGETARCH" = "arm64" ]; then \
    apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    libicu74 libjpeg-turbo8 libuv1 libwebp7 libpng16-16 libxext6 \
    && mkdir /out \
    && cp -a /usr/lib/*/libicu*.so* /usr/lib/*/libjpeg.so.8* /usr/lib/*/libuv.so.1* \
       /usr/lib/*/libwebp.so.7* /usr/lib/*/libsharpyuv.so* /usr/lib/*/libpng16.so.16* \
       /usr/lib/*/libXext.so.6* /out/; \
    else mkdir /out; fi

FROM ruby:3.4.9-slim

ARG RAILS_ENV=production

ENV APP_PATH=/var/app
ENV BUNDLE_VERSION=2.5.21
ENV BUNDLE_PATH=/usr/local/bundle/gems
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_PORT=3000

RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl \
    wget \
    build-essential \
    git \
    postgresql-client \
    libpq-dev \
    libxml2-dev \
    libxslt-dev \
    libyaml-dev \
    zlib1g-dev \
    libgeos-dev libgeos++-dev \
    tzdata \
    less \
    libjemalloc2 libjemalloc-dev \
    cmake \
    ca-certificates \
    gosu \
    && mkdir -p $APP_PATH \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js from Debian repositories (supports all architectures including armv7)
RUN apt-get update -qq \
    && apt-get install -y nodejs npm \
    && npm install -g yarn \
    && rm -rf /var/lib/apt/lists/*

# Headless GL stack for the in-container poster renderer (maplibre-native):
# software rendering via Mesa + a virtual X display. No browser involved.
RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    libegl1 libgles2 libgbm1 libglx0 libopengl0 libx11-6 xvfb xauth \
    && (apt-get install -y --no-install-recommends mesa-libgallium 2>/dev/null || true) \
    && rm -rf /var/lib/apt/lists/*

COPY --from=mbgl_libs /out /opt/mbgl-libs

# Use jemalloc with check for architecture
RUN if [ "$(uname -m)" = "x86_64" ]; then \
    echo "/usr/lib/x86_64-linux-gnu/libjemalloc.so.2" > /etc/ld.so.preload; \
    else \
    echo "/usr/lib/aarch64-linux-gnu/libjemalloc.so.2" > /etc/ld.so.preload; \
    fi

# Return freed pages to the OS quickly instead of holding them in the
# allocator, and cap arena count — keeps idle RSS low on small hosts.
ENV MALLOC_CONF="narenas:2,dirty_decay_ms:1000,muzzy_decay_ms:1000"

# Enable YJIT
ENV RUBY_YJIT_ENABLE=1

# Update RubyGems and install Bundler
RUN gem update --system 3.6.9 \
    && gem install bundler --version "$BUNDLE_VERSION" \
    && rm -rf $GEM_HOME/cache/*

WORKDIR $APP_PATH

COPY ../Gemfile ../Gemfile.lock ../.ruby-version ../vendor ./

# Install production gems only
RUN bundle config set --local path 'vendor/bundle' \
    && bundle config set --local without 'development test' \
    && bundle install --jobs 4 --retry 3 \
    && rm -rf vendor/bundle/ruby/3.4.0/cache/*.gem

COPY ../. ./

# Node deps (tailwind plugins like daisyui) are needed by assets:precompile.
# Install them here so the build does not depend on a host-side `npm install`
# having populated node_modules in the build context.
RUN npm ci --no-audit --no-fund && rm -rf ~/.npm

# Poster renderer dependencies — prebuilt maplibre-native binaries exist for
# x64/arm64 only (Debian's Node 20 = ABI 115, which the release ships). On
# armv7 the renderer is skipped; server-side poster rendering is unavailable
# there.
RUN if [ "$(uname -m)" = "x86_64" ] || [ "$(uname -m)" = "aarch64" ]; then \
    cd vendor/poster_renderer \
    && npm ci --no-audit --no-fund \
    && rm -rf ~/.npm; \
    fi

# Precompile assets
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rake assets:precompile \
    && rm -rf node_modules tmp/cache

# Ensure tmp directory exists and is writable by any user (for custom uid:gid support)
RUN mkdir -p tmp/pids tmp/cache tmp/sockets \
    && chmod -R 777 tmp

# Copy public directory to temp location for syncing with volume at runtime
# This allows new static files to be added to the persistent volume
RUN cp -r public /tmp/public_assets

# Copy entrypoint scripts and grant execution permissions
COPY ./docker/entrypoint-env-guard.sh /usr/local/bin/entrypoint-env-guard.sh

COPY ./docker/web-entrypoint.sh /usr/local/bin/web-entrypoint.sh
RUN chmod +x /usr/local/bin/web-entrypoint.sh

COPY ./docker/sidekiq-entrypoint.sh /usr/local/bin/sidekiq-entrypoint.sh
RUN chmod +x /usr/local/bin/sidekiq-entrypoint.sh

EXPOSE $RAILS_PORT

STOPSIGNAL SIGINT

ENTRYPOINT [ "bundle", "exec" ]
