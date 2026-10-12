# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AirTrail::ConnectionTester do
  it 'returns failure when url is blank' do
    expect(described_class.new('', 'k').call).to include(success: false)
  end

  it 'returns failure when api key is blank' do
    expect(described_class.new('https://a.example', '').call).to include(success: false)
  end

  it 'returns success on a 200 list response' do
    stub_request(:get, 'https://a.example/api/flight/list?scope=mine')
      .to_return(status: 200, body: { success: true, flights: [] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    expect(described_class.new('https://a.example', 'k').call).to include(success: true)
  end

  it 'returns failure on a 401' do
    stub_request(:get, 'https://a.example/api/flight/list?scope=mine').to_return(status: 401)

    expect(described_class.new('https://a.example', 'k').call).to include(success: false)
  end
end
