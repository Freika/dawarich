# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixture: Rails accepts the bcrypt hash dawarich users password writes' do
  recorded = JSON.parse(Rails.root.join('app-phoenix/test/fixtures/a12e/password.json').read)

  it 'verifies the recorded Phoenix hash with Devise' do
    user = create(:user)
    user.update_column(:encrypted_password, recorded.fetch('hash'))
    expect(user.reload.valid_password?('phoenix-a12e-login-not-for-production')).to be(true)
  end

  it 'truncates a 128-character multibyte password at 72 bytes like Phoenix' do
    user = create(:user)
    user.update_column(:encrypted_password, recorded.fetch('long_hash'))
    expect(user.reload.valid_password?('ä' * 128)).to be(true)
    expect(user.valid_password?(('ä' * 36) + ('b' * 50))).to be(true)
  end
end
