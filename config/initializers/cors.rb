# frozen_string_literal: true

# Cross-Origin Resource Sharing rules.
#
# Scoped narrowly to the public tools/signup-handoff endpoint
# (`/api/v1/imports/pending`). Browser-side uploads originate from
# https://dawarich.app and Cloudflare Pages preview deploys, so those origins
# need to clear preflight. The authenticated API (api_key + Bearer) is server-
# to-server and intentionally NOT covered here — adding it would broaden the
# CSRF/credential-disclosure surface without benefit.

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(
      'https://dawarich.app',
      %r{\Ahttps://[a-z0-9-]+\.dawarich\.pages\.dev\z},
      *(Rails.env.production? ? [] : [%r{\Ahttp://localhost(?::\d+)?\z}])
    )
    resource '/api/v1/imports/pending', headers: :any, methods: %i[post options]
  end
end
