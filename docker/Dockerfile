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

ARG ELIXIR_VERSION=1.20.4
ARG ELIXIR_SHA256=4389f216eec086b34a08d70a3eb0a649d00e6631987d1cbb649a2f81092f034c

RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    erlang-nox erlang-dev curl unzip git ca-certificates build-essential nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# Release artifacts include Elixir, while Debian supplies OTP 27 in both runtimes.
# Verify the official precompiled Elixir archive instead of relying on apt's older version.
RUN curl -fsSL --retry 3 "https://github.com/elixir-lang/elixir/releases/download/v${ELIXIR_VERSION}/elixir-otp-27.zip" -o /tmp/elixir.zip \
    && echo "${ELIXIR_SHA256}  /tmp/elixir.zip" | sha256sum -c - \
    && unzip -q /tmp/elixir.zip -d /opt/elixir \
    && rm /tmp/elixir.zip \
    && erl -noshell -eval '"27" = erlang:system_info(otp_release), halt().'

ENV PATH=/opt/elixir/bin:$PATH
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
COPY app/assets/svg/icons/lucide/outline priv/svg_icons/lucide/outline
COPY app/assets/svg/icons/brands priv/svg_icons/brands
COPY app-phoenix/rel rel
COPY app-phoenix/config/runtime.exs config/
COPY app-phoenix/assets/package.json app-phoenix/assets/package-lock.json assets/
RUN npm ci --prefix assets --no-audit --no-fund && rm -rf ~/.npm
COPY app-phoenix/assets assets
COPY app-phoenix/assets /src/app-phoenix/assets
COPY app-phoenix/lib /src/app-phoenix/lib
COPY app-phoenix/priv/tailwind /src/app-phoenix/priv/tailwind
COPY app/assets/stylesheets /src/app/assets/stylesheets
COPY app/assets/fonts /src/app/assets/fonts
COPY app/assets/images /src/app/assets/images
COPY vendor/assets/stylesheets /src/vendor/assets/stylesheets
COPY vendor/assets/fonts /src/vendor/assets/fonts
COPY vendor/javascript/mapbox-gl-rtl-text.js vendor/javascript/mapbox-gl-rtl-text.LICENSE.txt /src/vendor/javascript/
COPY public/maplibre /src/public/maplibre
COPY lib/assets /src/lib/assets
COPY config/locales /src/config/locales
COPY config/achievements /src/config/achievements
COPY config/achievements.yml config/shared_link_wordlist.txt /src/config/
RUN ln -s /build/assets/node_modules /src/app-phoenix/assets/node_modules \
    && mix esbuild.install --if-missing && APP_PATH=/src mix assets.deploy \
    && mix dawarich.build_inputs --root /src --out /out && mix release
RUN mkdir -p /out/public/api-docs \
    && cp assets/node_modules/swagger-ui-dist/swagger-ui-bundle.js \
          assets/node_modules/swagger-ui-dist/swagger-ui.css \
          assets/node_modules/swagger-ui-dist/LICENSE /out/public/api-docs/

FROM phoenix_builder AS rails_frontend_builder
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund && rm -rf ~/.npm
COPY app/assets app/assets
COPY lib/assets lib/assets
COPY app/javascript app/javascript
COPY vendor/assets vendor/assets
COPY vendor/javascript vendor/javascript
COPY config/locales config/locales
COPY config/achievements config/achievements
COPY config/achievements.yml config/importmap.rb config/tailwind.config.js config/
COPY app-phoenix/lib app-phoenix/lib
COPY app-phoenix/assets/js app-phoenix/assets/js
COPY app-phoenix/priv/tailwind/retained_classes.html app-phoenix/priv/tailwind/retained_classes.html
RUN BROWSERSLIST_IGNORE_OLD_DATA=1 node_modules/.bin/tailwindcss \
      -i app/assets/stylesheets/application.tailwind.css -o app/assets/builds/tailwind.css \
      -c config/tailwind.config.js --minify
COPY app-phoenix/tools/rails_frontend /build/tools/rails_frontend
RUN cd /build && mix run --no-start tools/rails_frontend/build.exs --root /src --out /legacy-out

FROM debian:trixie-slim AS poster_builder

ARG TARGETARCH
RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs npm ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /renderer
COPY vendor/poster_renderer/package.json vendor/poster_renderer/package-lock.json ./
COPY vendor/poster_renderer/render.sh vendor/poster_renderer/render.mjs vendor/poster_renderer/register.mjs ./
COPY vendor/poster_renderer/fonts fonts
COPY app-phoenix/assets/server/poster_loader.mjs loader.mjs
COPY app-phoenix/assets/js/poster/data/theme_loader.js app-phoenix/assets/js/poster/data/protomaps_schema.js browser/data/
COPY app-phoenix/assets/js/poster/export/pdf_encoder.js app-phoenix/assets/js/poster/export/png_encoder.js browser/export/
COPY app-phoenix/assets/js/poster/render/overlay.js app-phoenix/assets/js/poster/render/style_builder.js app-phoenix/assets/js/poster/render/text_layout.js browser/render/
RUN if [ "$TARGETARCH" = "amd64" ] || [ "$TARGETARCH" = "arm64" ]; then \
    test "$(node -p 'process.versions.modules')" = 115 \
    && npm ci --no-audit --no-fund \
    && rm -rf /root/.npm; fi

FROM debian:trixie-slim AS native_runtime

ENV APP_PATH=/var/app LANG=C.UTF-8 RAILS_ENV=production RAILS_PORT=3000

RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    erlang-base erlang-inets erlang-ssl erlang-xmerl \
    libstdc++6 libgcc-s1 libssl3t64 libncurses6 zlib1g \
    postgresql-client curl wget procps gosu ca-certificates tzdata nodejs \
    libegl1 libgles2 libgbm1 libglx0 libopengl0 libx11-6 xvfb xauth mesa-libgallium \
    libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libjpeg62-turbo libgif7 librsvg2-2 \
    && rm -rf /var/lib/apt/lists/* \
    && test "$(node -p 'process.versions.modules')" = 115

COPY --from=mbgl_libs /out /opt/mbgl-libs
WORKDIR $APP_PATH
ENV DAWARICH_RAILS=off DAWARICH_PHOENIX_LIFECYCLE=true
COPY --from=phoenix_builder /build/_build/prod/rel/dawarich /opt/dawarich
COPY --from=phoenix_builder /out/public/api-docs public/api-docs
COPY --from=phoenix_builder /out/tmp/phoenix tmp/phoenix
COPY swagger/v1/swagger.yaml swagger/v1/swagger.yaml
COPY public/*.html public/*.png public/*.ico public/*.svg public/*.txt public/*.webmanifest public/
COPY public/maplibre public/maplibre
COPY public/maps public/maps
COPY public/maps_maplibre public/maps_maplibre
COPY public/poster_themes public/poster_themes
COPY app/assets/svg/icons/flags/landscape app/assets/svg/icons/flags/landscape
COPY config/storage.yml config/storage.yml
COPY .app_version .app_version
COPY --from=poster_builder /renderer vendor/poster_renderer
COPY docker/entrypoint-env-guard.sh docker/entrypoint-common.sh docker/web-entrypoint.sh docker/sidekiq-entrypoint.sh docker/cloud-entrypoint.sh docker/cloud-sidekiq-entrypoint.sh docker/release.sh /usr/local/bin/
RUN mkdir -p storage log tmp/pids tmp/cache tmp/sockets public/imports public/exports \
    && chmod -R 777 storage log tmp public \
    && cp -r public $APP_PATH/public_dist \
    && chmod +x /usr/local/bin/*entrypoint*.sh /usr/local/bin/release.sh \
    && ln -s /opt/dawarich/bin/dawarich /usr/local/bin/dawarich \
    && rm -f /opt/dawarich/releases/COOKIE
RUN if [ "$(uname -m)" = "x86_64" ] || [ "$(uname -m)" = "aarch64" ]; then \
    cd vendor/poster_renderer \
    && LD_LIBRARY_PATH=/opt/mbgl-libs node -e "require('@maplibre/maplibre-gl-native'); require('canvas')"; fi
RUN for tool in ruby bundle gem rake rails puma sidekiq; do \
    ! command -v "$tool" >/dev/null 2>&1 || exit 1; done \
    && for path in Gemfile Gemfile.lock .ruby-version bin/rails bin/rake \
    config/application.rb config/boot.rb config/environment.rb spec \
    app/controllers app/models app/jobs app/helpers app/views app/mailers app/services app/policies \
    db/schema.rb vendor/bundle lib/tasks; do \
    [ ! -e "$APP_PATH/$path" ] || exit 1; done
RUN for path in /usr/local/lib/ruby /usr/lib/ruby /usr/local/bundle /var/lib/gems; do \
    [ ! -e "$path" ] || exit 1; done
RUN DAWARICH_COOKIE_FILE=/tmp/build-cookie dawarich eval 'Dawarich.Release.check_runtime_apps!()' \
    && rm -f /tmp/build-cookie
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

COPY --from=rails_frontend_builder /legacy-out/public/assets public/assets
COPY --from=phoenix_builder /out/public/api-docs public/api-docs
COPY --from=rails_frontend_builder /legacy-out/config/sprockets-manifest.json config/sprockets-manifest.json
COPY --from=rails_frontend_builder /src/app/assets/builds/tailwind.css app/assets/builds/tailwind.css
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
