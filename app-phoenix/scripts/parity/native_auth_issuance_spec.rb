# frozen_string_literal: true

require 'rails_helper'
require 'open3'

RSpec.describe 'Native F authentication issuance read back by Rails', type: :request do
  def native_vectors
    environment = {
      'MIX_ENV' => 'test', 'NATIVE_ISSUANCE_SECRET' => Rails.application.secret_key_base,
      'PHOENIX_TEST_DATABASE' => ENV.fetch('PHOENIX_TEST_DATABASE'),
      'PHOENIX_TEST_REDIS_URL' => ENV.fetch('PHOENIX_TEST_REDIS_URL'),
      'DATABASE_HOST' => ENV.fetch('DATABASE_HOST'),
      'PATH' => "#{Dir.home}/.asdf/shims:#{ENV.fetch('PATH')}",
      'ASDF_ERLANG_VERSION' => '27.3.4.1', 'ASDF_ELIXIR_VERSION' => '1.20.4-otp-27'
    }
    output, status = Open3.capture2e(environment, 'mix', 'run', 'scripts/parity/native_auth_issuance.exs',
                                     chdir: Rails.root.join('app-phoenix').to_s)
    expect(status.success?).to be(true), 'native issuance failed; synthetic cookies withheld'
    line = output.lines.find { |value| value.start_with?('NATIVE_AUTH_ISSUANCE=') }
    expect(line).to be_present
    JSON.parse(line.delete_prefix('NATIVE_AUTH_ISSUANCE='))
  end

  it 'authenticates credentials registration recovery account OTP and remember issuance in Rails' do
    vectors = native_vectors
    expect(vectors.pluck('name')).to eq(%w[credentials remember_restore registration recovery account otp])
    vectors.each do |vector|
      user = User.find_by(id: vector.fetch('id')) || create(:user, id: vector.fetch('id'))
      user.update_columns(email: vector.fetch('email'), encrypted_password: vector.fetch('hash'),
                          remember_created_at: vector['remembered_at'], status: 1,
                          active_until: 10.years.from_now, locked_at: nil)
      browser = ActionDispatch::Integration::Session.new(Rails.application)
      browser.get('/notifications', headers: { 'Cookie' => "_dawarich_session=#{vector.fetch('session')}" })
      expect(browser.response.status).to eq(200), "Rails refused #{vector.fetch('name')} session"
      expect(browser.request.env['warden'].user&.id).to eq(user.id), "Rails identity mismatch: #{vector.fetch('name')}"
      next unless vector['remember']

      remembered = ActionDispatch::Integration::Session.new(Rails.application)
      remembered.get('/notifications', headers: { 'Cookie' => "remember_user_token=#{vector.fetch('remember')}" })
      expect(remembered.response.status).to eq(200), "Rails refused #{vector.fetch('name')} remember cookie"
      expect(remembered.request.env['warden'].user&.id).to eq(user.id)
    end
  end
end
