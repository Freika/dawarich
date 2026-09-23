# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MapMatching::Atlas::ConnectionTest do
  let(:client) { instance_double(MapMatching::Atlas::Client) }

  before do
    allow(DawarichSettings).to receive(:atlas_url).and_return('http://atlas:4567')
  end

  it 'reports a ready routing capability and Atlas version' do
    allow(client).to receive_messages(
      health: { status: 'degraded', routing: 'up' },
      version: { version: '0.6.0', revision: 'abcdef1234567890' }
    )

    type, message = described_class.call(client:)

    expect(type).to eq(:notice)
    expect(message).to include('0.6.0', 'abcdef123456')
  end

  it 'warns when Atlas answers but routing is unavailable' do
    allow(client).to receive_messages(
      health: { status: 'degraded', routing: 'down' },
      version: { version: '0.6.0', revision: nil }
    )

    expect(described_class.call(client:).first).to eq(:alert)
  end

  it 'returns a sanitized Atlas error code' do
    error = MapMatching::Atlas::Client::Unavailable.new(
      'secret upstream detail', status: 503, code: 'unavailable'
    )
    allow(client).to receive(:health).and_raise(error)

    type, message = described_class.call(client:)

    expect(type).to eq(:alert)
    expect(message).to include('unavailable')
    expect(message).not_to include('secret upstream detail')
  end
end
