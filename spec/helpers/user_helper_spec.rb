# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserHelper, type: :helper do
  let(:user) { create(:user) }

  before { UserHelper::QR_CACHE.clear }

  it 'renders the QR code once per payload and size' do
    allow(ResponsiveQrSvg).to receive(:call).and_call_original

    first = helper.api_key_qr_code(user)
    second = helper.api_key_qr_code(user)

    expect(second).to eq(first)
    expect(first).to include('<svg')
    expect(ResponsiveQrSvg).to have_received(:call).once
  end

  it 'renders a new QR code when the API key or size changes' do
    original = helper.api_key_qr_code(user)
    small = helper.api_key_qr_code(user, size: 3)
    user.update!(api_key: SecureRandom.hex(16))

    expect(small).not_to eq(original)
    expect(helper.api_key_qr_code(user)).not_to eq(original)
  end
end
