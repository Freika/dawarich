FROM ruby:3.4.6-slim

ARG RAILS_ENV=production

ENV APP_PATH=/var/app
ENV BUNDLE_VERSION=2.5.21
ENV BUNDLE_PATH=/usr/local/bundle/gems
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_PORT=3000
ENV RAILS_ENV=${RAILS_ENV}

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

# Install Node.js with architecture-specific logic for development
# For production/staging, use LTS version
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "arm64" ] || [ "$ARCH" = "armhf" ]; then \
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
        apt-get install -y nodejs; \
    else \
        apt-get update && \
        apt-get install -y nodejs npm; \
    fi && \
    npm install -g yarn && \
    rm -rf /var/lib/apt/lists/*

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

# Install gems based on environment
RUN bundle config set --local path 'vendor/bundle' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3 && \
    rm -rf vendor/bundle/ruby/3.4.0/cache/*.gem

COPY ../. ./

# Precompile assets for production/staging
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rake assets:precompile && \
                            rm -rf node_modules tmp/cache

COPY ./docker/web-entrypoint.sh /usr/local/bin/web-entrypoint.sh
RUN chmod +x /usr/local/bin/web-entrypoint.sh

COPY ./docker/sidekiq-entrypoint.sh /usr/local/bin/sidekiq-entrypoint.sh
RUN chmod +x /usr/local/bin/sidekiq-entrypoint.sh

EXPOSE $RAILS_PORT

ENTRYPOINT ["bundle", "exec"]
