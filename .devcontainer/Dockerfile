# Basis-Image für Ruby und Node.js
FROM ruby:3.3.4-alpine

ENV APP_PATH=/var/app
ENV BUNDLE_VERSION=2.5.9
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

RUN gem update --system 3.5.7 && gem install bundler --version "$BUNDLE_VERSION" \
    && rm -rf $GEM_HOME/cache/*


# FIXME It would be a good idea to use a other user than root, but this lead to permission error on export and maybe more yet.
# RUN adduser -D -h ${APP_PATH} vscode
USER root

# Navigate to app directory
WORKDIR $APP_PATH


EXPOSE $RAILS_PORT


