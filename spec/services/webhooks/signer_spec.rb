# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::Signer do
  it 'signs the body with HMAC-SHA256 of the secret' do
    signature = described_class.sign(body: '{"id":1}', secret: 'topsecret')

    expect(signature).to eq("sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 'topsecret', '{"id":1}')}")
  end
end
