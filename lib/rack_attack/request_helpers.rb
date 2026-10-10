# frozen_string_literal: true

def bearer_token(header)
  return nil if header.blank?

  match = header.match(/\ABearer\s+(\S+)\z/i)
  match && match[1]
end

# Rack::Attack runs ahead of the middleware that turns a malformed body into a
# 400, so an unparseable request would otherwise escape these throttles as a 500.
# Fall back to the query string, which parses independently of the body.
UNPARSEABLE_BODY_ERRORS = [
  Rack::Multipart::Error,
  Rack::Multipart::EmptyContentError,
  Rack::Multipart::MissingInputError,
  Rack::Multipart::BoundaryTooLongError,
  Rack::Multipart::MultipartPartLimitError,
  Rack::Multipart::MultipartTotalPartLimitError,
  Rack::QueryParser::ParamsTooDeepError,
  Rack::QueryParser::InvalidParameterError,
  Rack::QueryParser::ParameterTypeError,
  Rack::QueryParser::QueryLimitError,
  EOFError
].freeze

# Login and OTP bodies are a few hundred bytes; anything larger is never a
# legitimate client and is rejected before any throttle reads the body.
MAX_JSON_BODY_BYTES = 16.kilobytes
WEB_JSON_BODY_THROTTLED_PATHS = %w[/users/sign_in].freeze
API_JSON_BODY_THROTTLED_PATHS = %w[/api/v1/auth/login /api/v1/auth/otp_challenge].freeze

# Cheap params access: query string + form-encoded body only. rack-attack runs
# on Rack::Request, whose #params (GET.merge(POST)) parses only
# application/x-www-form-urlencoded and multipart/form-data bodies — it never
# parses application/json (ActionDispatch::ParamsParser does that later in the
# stack). Use safe_body_params for throttles that key on a field sent in a JSON
# request body, otherwise the discriminator returns nil for JSON clients and
# the throttle is silently bypassed. Deliberately not logged: a malformed-body
# flood would flood the log with it.
def safe_params(request)
  request.params
rescue *UNPARSEABLE_BODY_ERRORS
  safe_query(request)
end

# Like safe_params, but also parses an application/json body, which Rack::Request
# ignores. Required for throttles keyed on a JSON body field (API login email,
# OTP challenge token): rack-attack runs before ActionDispatch::ParamsParser, so
# the JSON body must be read and parsed here. The body is rewound and the parsed
# result memoised on env so multiple throttles in one request share a single
# read and the controller still sees the body. Query-string keys win over body
# keys, matching ActionDispatch::Request#parameters, so the throttle keys on the
# same value the controller authenticates.
def safe_body_params(request)
  body = json_request?(request) ? parsed_json_body(request) : safe_form_body(request)

  body.merge(safe_query(request))
rescue *UNPARSEABLE_BODY_ERRORS
  safe_query(request)
end

# Form-encoded body only (Rack::Request#POST); never the query string, so the
# caller can apply query-wins precedence itself.
def safe_form_body(request)
  request.POST
rescue *UNPARSEABLE_BODY_ERRORS
  {}
end

# The query string can be malformed on its own; a throttle must not raise here.
def safe_query(request)
  request.GET
rescue *UNPARSEABLE_BODY_ERRORS
  {}
end

# Rails parses every registered :json synonym (text/x-json, application/jsonrequest)
# with the JSON parser, so the throttle must accept the same set or a one-header
# swap bypasses it again. A malformed Content-Type raises out of Mime::Type, and
# Rails would reject that request anyway, so treat it as not-JSON rather than
# letting an unauthenticated header crash the throttle.
def json_request?(request)
  return false if request.media_type.blank?

  Mime::Type.lookup(request.media_type).symbol == :json
rescue Mime::Type::InvalidMimeType, ArgumentError
  false
end

# Reads at most MAX_JSON_BODY_BYTES + 1 so a flood of oversized bodies cannot
# buffer unbounded input; anything longer is handed to the size blocklist.
# Rewinds so downstream middleware and the controller still see the body, and
# memoises the parsed Hash on env because several throttles run per request
# and the body is a stream that can only be consumed once.
def parsed_json_body(request)
  request.env['rack.attack.json_body'] ||=
    begin
      body = request.body
      raw = body.read(MAX_JSON_BODY_BYTES + 1)
      body.rewind if body.respond_to?(:rewind)
      raw.to_s.bytesize > MAX_JSON_BODY_BYTES ? {} : parse_json_body(raw)
    end
end

# Always returns a Hash: a JSON array/scalar body has no string-key lookup, so
# it is treated the same as an unparseable body (fall back to the query string).
def parse_json_body(raw)
  return {} if raw.blank?

  JSON.parse(raw).then { |parsed| parsed.is_a?(Hash) ? parsed : {} }
rescue JSON::ParserError
  {}
end

# Oversized-body rejection is a payload-size safeguard, not a rate limit (see
# the blocklist below), so it does not need to mirror which throttles are
# self-hosted-exempt: the web sign-in path is always checked; the API paths
# were already self-hosted-exempt before the throttles behind them were.
def json_body_throttled_path?(request)
  return false unless request.post?

  path = throttle_path(request)
  return true if WEB_JSON_BODY_THROTTLED_PATHS.include?(path)

  API_JSON_BODY_THROTTLED_PATHS.include?(path) && !DawarichSettings.self_hosted?
end

# Rails routes accept an optional (.:format) suffix, while Rack sees the raw
# path before routing. Share counters across formats without matching child paths.
def throttle_path(request)
  request.path.sub(%r{\.[^/.]+\z}, '')
end

def request_api_key(request)
  safe_params(request)['api_key'] || bearer_token(request.get_header('HTTP_AUTHORIZATION'))
end
