# Base-Image for Ruby and Node.js
FROM ruby:3.4.9-slim

ENV APP_PATH=/var/app
ENV BUNDLE_VERSION=2.5.21
ENV BUNDLE_PATH=/usr/local/bundle/gems
ENV TMP_PATH=/tmp/
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_PORT=3000

# Install dependencies for application (mirrors docker/Dockerfile)
RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    curl \
    ca-certificates \
    postgresql-client \
    libpq-dev \
    libxml2-dev \
    libxslt-dev \
    libyaml-dev \
    zlib1g-dev \
    libgeos-dev \
    nodejs \
    npm \
    imagemagick \
    tzdata \
    less \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p $APP_PATH

RUN gem update --system 3.6.2 && gem install bundler --version "$BUNDLE_VERSION" \
    && rm -rf $GEM_HOME/cache/*

# FIXME It would be a good idea to use a other user than root, but this lead to permission error on export and maybe more yet.
# RUN adduser -D -h ${APP_PATH} vscode
USER root

# Navigate to app directory
WORKDIR $APP_PATH

EXPOSE $RAILS_PORT

