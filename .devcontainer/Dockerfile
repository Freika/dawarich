FROM ruby:3.4.6-slim

ARG RAILS_ENV=development
ENV RAILS_ENV=development
ENV APP_PATH=/var/app
ENV BUNDLE_VERSION=2.5.21
# In dev, we usually let gems stay in the system path for easier LSP access
#ENV BUNDLE_PATH=/usr/local/bundle/gems
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_PORT=3000
# Add the gem bin directory to the system PATH
#ENV PATH="${BUNDLE_PATH}/bin:${PATH}"

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

# DEV OPTIMIZATION: Don't exclude development/test gems
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install --jobs 4 --retry 3

# We don't COPY the whole app here because devcontainer.json 
# mounts the local folder over $APP_PATH anyway.

# Copy entrypoints from the specific context
COPY ./docker/web-entrypoint.sh /usr/local/bin/web-entrypoint.sh
COPY ./docker/sidekiq-entrypoint.sh /usr/local/bin/sidekiq-entrypoint.sh
RUN chmod +x /usr/local/bin/*.sh

EXPOSE $RAILS_PORT

ENTRYPOINT [ "bundle", "exec" ]