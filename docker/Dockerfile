FROM ruby:3.4.6-slim

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
    libgeos-dev libgeos++-dev \
    imagemagick \
    tzdata \
    less \
    libjemalloc2 libjemalloc-dev \
    cmake \
    ca-certificates \
    && mkdir -p $APP_PATH \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js from Debian repositories (supports all architectures including armv7)
RUN apt-get update -qq \
    && apt-get install -y nodejs npm \
    && npm install -g yarn \
    && rm -rf /var/lib/apt/lists/*

# Use jemalloc with check for architecture
RUN if [ "$(uname -m)" = "x86_64" ]; then \
    echo "/usr/lib/x86_64-linux-gnu/libjemalloc.so.2" > /etc/ld.so.preload; \
    else \
    echo "/usr/lib/aarch64-linux-gnu/libjemalloc.so.2" > /etc/ld.so.preload; \
    fi

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
COPY ./docker/web-entrypoint.sh /usr/local/bin/web-entrypoint.sh
RUN chmod +x /usr/local/bin/web-entrypoint.sh

COPY ./docker/sidekiq-entrypoint.sh /usr/local/bin/sidekiq-entrypoint.sh
RUN chmod +x /usr/local/bin/sidekiq-entrypoint.sh

EXPOSE $RAILS_PORT

STOPSIGNAL SIGINT

ENTRYPOINT [ "bundle", "exec" ]
