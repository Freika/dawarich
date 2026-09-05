# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeslaMate::ConnectionTester do
  it 'uses one short request for an interactive connection test' do
    client = instance_double(TeslaMate::Client, cars: [])

    expect(TeslaMate::Client).to receive(:new).with(
      'https://teslamate.example',
      username: nil,
      password: nil,
      api_token: nil,
      skip_ssl_verification: false,
      timeout: 5,
      max_attempts: 1
    ).and_return(client)

    result = described_class.new('https://teslamate.example').call

    expect(result).to include(success: true)
  end
end
