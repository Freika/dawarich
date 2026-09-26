# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'B12 outbound HTTP guard' do
  it 'allows only loopback HTTP when opted in' do
    expect(B12E2EEgress.enabled?).to be(true)
    expect(WebMock.net_connect_allowed?(URI('http://127.0.0.1:3103/health'))).to be(true)
    expect(WebMock.net_connect_allowed?(URI('https://example.invalid/'))).to be(false)
  end
end
