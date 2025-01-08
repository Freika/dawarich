FROM ruby:3.3.4-alpine

ENV APP_PATH=/var/app
ENV BUNDLE_VERSION=2.5.21
ENV BUNDLE_PATH=/usr/local/bundle/gems
ENV TMP_PATH=/tmp/
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_PORT=3000

# Install dependencies for application
RUN apk -U add --no-cache \
    build-base \
    git \
    postgresql-dev \
    postgresql-client \
    libxml2-dev \
    libxslt-dev \
    nodejs \
    yarn \
    imagemagick \
    tzdata \
    less \
    yaml-dev \
    # gcompat for nokogiri on mac m1
    gcompat \
    && rm -rf /var/cache/apk/* \
    && mkdir -p $APP_PATH

RUN gem install bundler --version "$BUNDLE_VERSION" \
    && rm -rf $GEM_HOME/cache/*

# Navigate to app directory
WORKDIR $APP_PATH

COPY ../Gemfile ../Gemfile.lock ../vendor ../.ruby-version ./

# Install missing gems
RUN bundle config set --local path 'vendor/bundle' \
    && bundle install --jobs 20 --retry 5

COPY ../. ./

# Copy entrypoint scripts and grant execution permissions
COPY ./docker/prod-docker-entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE $RAILS_PORT

ENTRYPOINT [ "bundle", "exec" ]
