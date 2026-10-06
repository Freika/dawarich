FROM ubuntu:24.04 AS mbgl_libs
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

FROM debian:trixie-slim AS phoenix_builder

RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    erlang-nox erlang-dev elixir git ca-certificates build-essential nodejs npm \
    && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod LANG=C.UTF-8
WORKDIR /build

RUN mix local.hex --force && mix local.rebar --force

COPY app-phoenix/mix.exs app-phoenix/mix.lock ./
RUN mix deps.get --only prod
COPY app-phoenix/config/config.exs app-phoenix/config/prod.exs config/
RUN mix deps.compile

COPY app-phoenix/lib lib
COPY app-phoenix/priv priv
COPY config/shared_link_wordlist.txt priv/shared_link_wordlist.txt
COPY lib/assets/admin1_world.geojson priv/admin1_world.geojson
COPY lib/assets/countries.geojson.gz priv/countries.geojson.gz
COPY app-phoenix/rel rel
COPY app-phoenix/config/runtime.exs config/
RUN mix release

WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund && rm -rf ~/.npm
RUN mkdir -p /out/public/api-docs \
    && cp node_modules/swagger-ui-dist/swagger-ui-bundle.js \
          node_modules/swagger-ui-dist/swagger-ui.css \
          node_modules/swagger-ui-dist/LICENSE /out/public/api-docs/
COPY app/assets app/assets
COPY app/javascript app/javascript
COPY app/helpers app/helpers
COPY app/views app/views
COPY vendor/assets vendor/assets
COPY vendor/javascript vendor/javascript
COPY config/locales config/locales
COPY config/achievements config/achievements
COPY config/achievements.yml config/importmap.rb config/tailwind.config.js config/
COPY app-phoenix/lib app-phoenix/lib
RUN BROWSERSLIST_IGNORE_OLD_DATA=1 node_modules/.bin/tailwindcss \
      -i app/assets/stylesheets/application.tailwind.css -o app/assets/builds/tailwind.css \
      -c config/tailwind.config.js --minify \
    && cd /build && mix dawarich.build_inputs --root /src --out /out

FROM debian:trixie-slim AS native_runtime

ENV APP_PATH=/var/app LANG=C.UTF-8 RAILS_ENV=production RAILS_PORT=3000

RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    erlang-base erlang-inets erlang-ssl erlang-xmerl \
    libstdc++6 libgcc-s1 libssl3t64 libncurses6 zlib1g \
    postgresql-client curl procps gosu ca-certificates tzdata nodejs \
    libegl1 libgles2 libgbm1 libglx0 libopengl0 libx11-6 xvfb xauth mesa-libgallium \
    libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libjpeg62-turbo libgif7 librsvg2-2 \
    && rm -rf /var/lib/apt/lists/* \
    && test "$(node -p 'process.versions.modules')" = 115

COPY --from=mbgl_libs /out /opt/mbgl-libs
WORKDIR $APP_PATH
EXPOSE $RAILS_PORT
STOPSIGNAL SIGTERM
ENTRYPOINT ["web-entrypoint.sh"]

FROM ruby:3.4.9-slim AS coexistence_runtime

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

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends nodejs npm \
    && npm install -g yarn \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    libegl1 libgles2 libgbm1 libglx0 libopengl0 libx11-6 xvfb xauth \
    && (apt-get install -y --no-install-recommends mesa-libgallium 2>/dev/null || true) \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends erlang-base erlang-inets erlang-ssl erlang-xmerl procps \
    && rm -rf /var/lib/apt/lists/*

COPY --from=mbgl_libs /out /opt/mbgl-libs

RUN if [ "$(uname -m)" = "x86_64" ]; then \
    echo "/usr/lib/x86_64-linux-gnu/libjemalloc.so.2" > /etc/ld.so.preload; \
    else \
    echo "/usr/lib/aarch64-linux-gnu/libjemalloc.so.2" > /etc/ld.so.preload; \
    fi

ENV MALLOC_CONF="narenas:2,dirty_decay_ms:1000,muzzy_decay_ms:1000"

ENV RUBY_YJIT_ENABLE=1

RUN gem update --system 3.6.9 \
    && gem install bundler --version "$BUNDLE_VERSION" \
    && rm -rf $GEM_HOME/cache/*

WORKDIR $APP_PATH

COPY ../Gemfile ../Gemfile.lock ../.ruby-version ../vendor ./

RUN bundle config set --local path 'vendor/bundle' \
    && bundle config set --local without 'development test' \
    && bundle install --jobs 4 --retry 3 \
    && rm -rf vendor/bundle/ruby/3.4.0/cache/*.gem

COPY ../. ./

RUN if [ "$(uname -m)" = "x86_64" ] || [ "$(uname -m)" = "aarch64" ]; then \
    cd vendor/poster_renderer \
    && npm ci --no-audit --no-fund \
    && rm -rf ~/.npm; \
    fi

COPY --from=phoenix_builder /out/public/assets public/assets
COPY --from=phoenix_builder /out/public/api-docs public/api-docs
COPY --from=phoenix_builder /out/config/sprockets-manifest.json config/sprockets-manifest.json
COPY --from=phoenix_builder /src/app/assets/builds/tailwind.css app/assets/builds/tailwind.css
COPY --from=phoenix_builder /out/tmp/phoenix tmp/phoenix

RUN mkdir -p tmp/pids tmp/cache tmp/sockets \
    && chmod -R 777 tmp

RUN cp -r public $APP_PATH/public_dist

COPY --from=phoenix_builder /build/_build/prod/rel/dawarich /opt/dawarich
RUN DAWARICH_COOKIE_FILE=/tmp/build-cookie /opt/dawarich/bin/dawarich eval 'Dawarich.Release.check_runtime_apps!()' \
    && rm -f /tmp/build-cookie
RUN ln -s /opt/dawarich/bin/dawarich /usr/local/bin/dawarich \
    && rm -f /opt/dawarich/releases/COOKIE \
    && DAWARICH_COOKIE_FILE=/tmp/build-cookie dawarich eval '{:ok, _} = Application.ensure_all_started(:postgrex); IO.puts(:ok)' | grep -qx ok \
    && rm -f /tmp/build-cookie

COPY ./docker/entrypoint-env-guard.sh /usr/local/bin/entrypoint-env-guard.sh
COPY ./docker/entrypoint-common.sh /usr/local/bin/entrypoint-common.sh

COPY ./docker/web-entrypoint.sh /usr/local/bin/web-entrypoint.sh
RUN chmod +x /usr/local/bin/web-entrypoint.sh

COPY ./docker/sidekiq-entrypoint.sh /usr/local/bin/sidekiq-entrypoint.sh
RUN chmod +x /usr/local/bin/sidekiq-entrypoint.sh

COPY ./docker/cloud-entrypoint.sh ./docker/cloud-sidekiq-entrypoint.sh ./docker/release.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/cloud-entrypoint.sh /usr/local/bin/cloud-sidekiq-entrypoint.sh /usr/local/bin/release.sh

EXPOSE $RAILS_PORT

STOPSIGNAL SIGTERM

ENTRYPOINT [ "bundle", "exec" ]
