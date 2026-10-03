# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixture: Rails accepts the bcrypt hash dawarich users password writes' do
  it 'verifies the recorded Phoenix hash with Devise' do
    hash = JSON.parse(Rails.root.join('app-phoenix/test/fixtures/a12e/password.json').read).fetch('hash')
    user = create(:user)
    user.update_column(:encrypted_password, hash)
    expect(user.reload.valid_password?('phoenix-a12e-login-not-for-production')).to be(true)
  end
end
