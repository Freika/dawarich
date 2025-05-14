#!/bin/bash

set -euo pipefail

dirname=${0%/*}
if [ "$dirname" != "systemd" ]; then
    echo "This installed must be called in the repository root!" >&2
    exit 1
fi

# make shellcheck happy (vars are defined in while loop below)
BUNDLE_VERSION=''
GEM_HOME=''
# "source" "$dirname"/environment and EXPORT all vars
# export all vars from env
envfile="$dirname"/environment
while IFS='#' read -r line; do
    if [[ "$line" =~ ^([A-Z0-9_]+)=\"?(.*)\"?$ ]]; then
        k=${BASH_REMATCH[1]}
        v=${BASH_REMATCH[2]}
        export "$k"="$v"
    fi
done < "$envfile"

if [ "$APP_PATH" != "$PWD" ]; then
    echo "Error: APP_PATH (defined in $envfile) != $PWD!" >&2
    exit 1
fi

set -x

# from docker/Dockerfile.dev

# Update gem system and install bundler
gem update --system 3.6.2
gem install bundler --version "$BUNDLE_VERSION"
rm -rf "$GEM_HOME"/cache/*

# Install all gems into the image
bundle config set --local path 'vendor/bundle'
bundle install --jobs 4 --retry 3
rm -rf vendor/bundle/ruby/3.4.1/cache/*.gem

exit 0
