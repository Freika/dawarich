# frozen_string_literal: true

require 'rails_helper'

# Regression: a per-key throttle must see an api_key supplied in the JSON body,
# not only in the query string / Authorization header, otherwise the 2FA-sensitive
# throttle is bypassed by moving the key into the body.
RSpec.describe 'request_api_key reads a JSON-body api_key' do
  def json_request(path, body)
    env = Rack::MockRequest.env_for(path, method: 'POST', input: body,
                                          'CONTENT_LENGTH' => body.bytesize.to_s,
                                          'CONTENT_TYPE' => 'application/json')
    Rack::Attack::Request.new(env)
  end

  it 'finds the api_key when it is only in the JSON body' do
    req = json_request('/api/v1/users/me/two_factor/backup_codes', '{"api_key":"body-key","password":"x"}')
    expect(request_api_key(req)).to eq('body-key')
  end

  it 'still prefers a query-string key and leaves the body unparsed (hot path)' do
    req = json_request('/api/v1/points?api_key=query-key', '{"api_key":"body-key"}')
    expect(request_api_key(req)).to eq('query-key')
    expect(req.env.key?('rack.attack.json_body')).to be(false)
  end
end
