# frozen_string_literal: true

Mime::Type.register 'application/geo+json', :geojson
Mime::Type.register 'application/manifest+json', :webmanifest

# Mime::Type.register only covers controller content negotiation; the static
# file server resolves extensions through Rack::Mime, which has no entry for
# .webmanifest and falls back to text/plain.
Rack::Mime::MIME_TYPES['.webmanifest'] = 'application/manifest+json'
