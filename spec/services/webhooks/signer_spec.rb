# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::Signer do
  it 'signs the body with HMAC-SHA256 of the secret' do
    signature = described_class.sign(body: '{"id":1}', secret: 'topsecret')

    expect(signature).to eq('sha256=da3557bb01e9adb585273452a18d40553fcd71fd1aeeae35eb30c81a7b082850')
  end
end
