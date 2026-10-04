# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings::TwoFactor', type: :request do
  let(:password) { 'test_password_123' }
  let(:user) { create(:user, password: password) }

  before do |example|
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
    sign_in user unless example.metadata[:a11c_management]
  end

  context 'A11c management', :a11c_management do
    include ActiveSupport::Testing::TimeHelpers

    let(:synthetic_secret) { 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ' }
    let(:instant) { Time.utc(2026, 10, 4, 12, 0, 0) }

    around do |example|
      previous = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      travel_to(instant) { example.run }
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end

    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

    def management_client(actor, remember: false)
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.get('/users/sign_in')
      client.post('/users/sign_in', params: {
                    authenticity_token: management_token(client),
                    user: { email: actor.email, password: password, remember_me: remember ? '1' : '0' }
                  })
      expect(client.response.status).to eq(303)
      client.get('/settings/two_factor')
      expect(client.response.status).to eq(200)
      client
    end

    def management_token(client)
      Nokogiri::HTML5(client.response.body).at_css('meta[name="csrf-token"]')['content']
    end

    def management_request(client, method, path = '/settings/two_factor', **params)
      client.public_send(method, path, params: params.merge(authenticity_token: management_token(client)))
    end

    def management_session(client)
      request = ActionDispatch::Request.new(Rails.application.env_config.dup)
      jar = ActionDispatch::Cookies::CookieJar.build(request,
                                                     '_dawarich_session' => client.cookies['_dawarich_session'])
      jar.encrypted['_dawarich_session']
    end

    def seed_management_session(client, data)
      jar = ActionDispatch::Request.new(Rails.application.env_config.dup).cookie_jar
      jar.encrypted['_dawarich_session'] = { value: data }
      client.cookies['_dawarich_session'] = jar['_dawarich_session']
    end

    def expect_management_redirect(client, kind, message)
      expect(client.response.status).to eq(302)
      expect(client.response.location).to eq('http://www.example.com/settings/two_factor')
      expect(management_session(client).dig('flash', 'flashes', kind)).to eq(message)
      client.get('/settings/two_factor')
      expect(client.response.status).to eq(200)
      expect(client.response.body).to include(message)
    end

    it 'A11c management matches source actions and effect ordering' do
      actor = create(:user, email: 'a11c-actions@dawarich.test', password: password)
      client = management_client(actor)
      expect(client.response.body).to include('2FA is not enabled')
      allow(DawarichSettings).to receive(:two_factor_available?).and_return(false)
      client.get('/settings/two_factor')
      expect(client.response.status).to eq(302)
      expect(client.response.location).to eq('http://www.example.com/settings/general')
      expect(management_session(client).dig('flash', 'flashes', 'alert'))
        .to eq('Two-factor authentication is not configured on this instance.')
      allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
      client.get('/settings/two_factor')

      2.times do
        before = actor.reload.attributes
        management_request(client, :post)
        expect(client.response.status).to eq(200)
        expect(actor.reload.otp_secret).to match(/\A[A-Z2-7]{32}\z/)
        expect(actor.otp_secret == before['otp_secret']).to be(false)
        expect(actor.attributes.except('otp_secret',
                                       'updated_at') == before.except('otp_secret', 'updated_at')).to be(true)
        expect(client.response.body).to include(ResponsiveQrSvg.call(actor.otp_provisioning_uri(actor.email,
                                                                                                issuer: 'Dawarich')))
      end
      actor.update!(otp_required_for_login: true, consumed_timestep: 123, otp_backup_codes: ['retained-digest'])
      before = actor.reload.attributes
      management_request(client, :post)
      expect(client.response.status).to eq(200)
      expect(actor.reload.otp_secret == before['otp_secret']).to be(false)
      expect(actor.attributes.except('otp_secret',
                                     'updated_at') == before.except('otp_secret', 'updated_at')).to be(true)

      actor.update!(otp_secret: synthetic_secret, otp_required_for_login: false, consumed_timestep: nil,
                    otp_backup_codes: nil)
      client.get('/settings/two_factor')
      management_request(client, :post, '/settings/two_factor/verify', otp_attempt: 'not-a-code')
      expect(client.response.status).to eq(422)
      doc = Nokogiri::HTML5(client.response.body)
      expect(doc.at_css('input[name="otp_attempt"]')['value'].to_s).to eq('')
      qr = ResponsiveQrSvg.call(actor.otp_provisioning_uri(actor.email, issuer: 'Dawarich'))
      expect(client.response.body).to include('Invalid verification code', qr)
      expect(management_session(client).dig('flash', 'flashes')).to be_blank
      expect(actor.reload.consumed_timestep).to be_nil

      management_request(client, :post, '/settings/two_factor/verify', otp_attempt: actor.current_otp)
      expect(client.response.status).to eq(200)
      codes = Nokogiri::HTML5(client.response.body).css('code.font-mono').map(&:text)
      expect(codes.size).to eq(10)
      expect(codes.all? { |code| code.match?(/\A[0-9a-f]{24}\z/) }).to be(true)
      expect(actor.reload.otp_required_for_login).to be(true)
      expect(actor.consumed_timestep).to eq(instant.to_i / 30)
      expect(actor.otp_backup_codes.zip(codes).all? do |hash, code|
        Devise::Encryptor.compare(User, hash, code)
      end).to be(true)
      before = actor.attributes
      management_request(client, :post, '/settings/two_factor/verify', otp_attempt: actor.current_otp)
      expect(client.response.status).to eq(422)
      expect(actor.reload.attributes == before).to be(true)

      [-60, -30, 0, 30, 60].each do |offset|
        actor.update_columns(consumed_timestep: nil)
        code = actor.otp.at(instant + offset)
        expect(actor.validate_and_consume_otp!(code)).to be(offset.abs <= 30)
        expect(actor.reload.consumed_timestep).to eq(offset.abs <= 30 ? (instant.to_i + offset) / 30 : nil)
      end
      [0, 29, 30, 59].each do |offset|
        travel_to(instant + offset)
        actor.update_columns(consumed_timestep: nil)
        code = actor.otp.at(instant + offset + 30)
        expect(actor.validate_and_consume_otp!(" \t#{code[0..2]}\n#{code[3..]}\r\f\v")).to be(true)
        expect(actor.validate_and_consume_otp!(code)).to be(false)
        expect(actor.validate_and_consume_otp!(actor.current_otp)).to be(false)
      end
      zero_time = (0..200).map { |offset| instant + offset * 30 }.find { |time| actor.otp.at(time).start_with?('0') }
      travel_to(zero_time)
      actor.update_columns(consumed_timestep: nil)
      code = actor.current_otp
      expect(actor.validate_and_consume_otp!(code.delete_prefix('0'))).to be(false)
      expect(actor.validate_and_consume_otp!("#{code}\u00a0")).to be(false)
      expect(actor.validate_and_consume_otp!(code)).to be(true)
      travel_to(instant)

      actor.update!(otp_secret: nil, consumed_timestep: nil, otp_backup_codes: nil, otp_required_for_login: false)
      client.get('/settings/two_factor')
      management_request(client, :post, '/settings/two_factor/verify', otp_attempt: 'not-a-code')
      expect(client.response.status).to eq(422)
      expect(client.response.body).to include('Invalid verification code')
      [nil, []].each do |backups|
        actor.update_column(:otp_backup_codes, backups)
        expect(actor.invalidate_otp_backup_code!('not-a-code')).to be(false)
      end
      malformed = actor.dup
      allow(malformed).to receive(:otp_backup_codes).and_return('legacy-string')
      expect do
        malformed.invalidate_otp_backup_code!('not-a-code')
      end.to raise_error(TypeError, /expected to be an Array/)

      actor.update!(otp_secret: synthetic_secret, otp_required_for_login: true)
      [nil, '', 'incorrect'].each do |candidate|
        params = { otp_attempt: actor.current_otp }
        params[:password] = candidate unless candidate.nil?
        management_request(client, :delete, **params)
        expect_management_redirect(client, 'alert', 'Incorrect password.')
        expect(actor.reload.consumed_timestep).to be_nil
      end
      [nil, '', 'not-a-code'].each do |candidate|
        params = { password: password }
        params[:otp_attempt] = candidate unless candidate.nil?
        management_request(client, :delete, **params)
        expect_management_redirect(client, 'alert', 'Provide a valid two-factor code (or backup code) to disable 2FA.')
      end
      %i[delete post].each do |method|
        actor.update!(otp_secret: synthetic_secret, otp_required_for_login: true, consumed_timestep: nil)
        client.get('/settings/two_factor')
        params = { password: password, otp_attempt: actor.current_otp }
        params[:_method] = 'delete' if method == :post
        management_request(client, method, **params)
        expect_management_redirect(client, 'notice', 'Two-factor authentication disabled.')
        expect(actor.reload.attributes.values_at('otp_required_for_login', 'otp_secret',
                                                 'otp_backup_codes')).to eq([false, nil, nil])
        expect(actor.consumed_timestep).to eq(instant.to_i / 30)
      end
      actor.update!(otp_secret: synthetic_secret, otp_required_for_login: true)
      backup = actor.generate_otp_backup_codes!.first
      actor.save!
      management_request(client, :delete, password: 'incorrect', otp_attempt: backup)
      expect_management_redirect(client, 'alert', 'Incorrect password.')
      expect(actor.reload.otp_backup_codes.size).to eq(10)
      management_request(client, :delete, password: password, otp_attempt: backup)
      expect_management_redirect(client, 'notice', 'Two-factor authentication disabled.')
      expect(actor.reload.attributes.values_at('otp_required_for_login', 'otp_secret',
                                               'otp_backup_codes')).to eq([false, nil, nil])
      management_request(client, :delete, password: password, otp_attempt: backup)
      expect_management_redirect(client, 'alert', 'Provide a valid two-factor code (or backup code) to disable 2FA.')
    end

    it 'A11c management preserves session and unrelated account state' do
      other = create(:user, email: 'a11c-other@dawarich.test', password: password)
      other_before = other.attributes
      [instant - 60, instant - 2.hours].each_with_index do |lock, index|
        actor = create(:user, email: "a11c-effects-#{index}@dawarich.test", password: password)
        client = management_client(actor, remember: true)
        actor.update_columns(failed_attempts: 2, failed_otp_attempts: 3, otp_locked_at: lock,
                             reset_password_token: "a11c-reset-#{index}", reset_password_sent_at: instant - 1.hour)
        data = management_session(client).merge('user_return_to' => '/stats', 'locale' => 'en', 'a11c' => 'retain')
        seed_management_session(client, data)
        before = actor.reload.attributes
        remember = client.cookies['remember_user_token']
        jobs = enqueued_jobs.size
        mails = ActionMailer::Base.deliveries.size
        management_request(client, :post)
        management_request(client, :post, '/settings/two_factor/verify', otp_attempt: 'not-a-code')
        expect(client.response.status).to eq(422)
        management_request(client, :post, '/settings/two_factor/verify', otp_attempt: actor.reload.current_otp)
        expect(client.response.status).to eq(200)
        codes = Nokogiri::HTML5(client.response.body).css('code.font-mono').map(&:text)
        management_request(client, :delete, password: password, otp_attempt: codes.first)
        expect(client.response.status).to eq(302)
        received = management_session(client)
        retained = %w[session_id _csrf_token user_return_to locale a11c warden.user.user.key]
        expect(received.values_at(*retained) == data.values_at(*retained)).to be(true)
        expect(client.cookies['remember_user_token'] == remember).to be(true)
        ignored = %w[otp_secret otp_required_for_login otp_backup_codes consumed_timestep updated_at]
        expect(actor.reload.attributes.except(*ignored) == before.except(*ignored)).to be(true)
        expect(enqueued_jobs.size).to eq(jobs)
        expect(ActionMailer::Base.deliveries.size).to eq(mails)
        client.get('/settings/two_factor')
        expect(client.response.body).to include('Two-factor authentication disabled.')
        client.get('/settings/two_factor')
        expect(client.response.body).not_to include('Two-factor authentication disabled.')
        expect(other.reload.attributes == other_before).to be(true)
      end

      actor = create(:user, email: 'a11c-save-order@dawarich.test', password: password)
      client = management_client(actor)
      actor.update!(otp_secret: synthetic_secret)
      actor.update_columns(email: '', updated_at: instant - 1.day)
      before = actor.reload.attributes
      management_request(client, :post, '/settings/two_factor/verify', otp_attempt: actor.current_otp)
      expect(client.response.status).to eq(422)
      expect(actor.reload.consumed_timestep).to eq(instant.to_i / 30)
      expect(actor.otp_required_for_login).to be(false)
      expect(actor.otp_backup_codes).to be_nil
      expect(actor.updated_at).to eq(instant)
      expect(actor.attributes.except('consumed_timestep', 'updated_at') ==
             before.except('consumed_timestep', 'updated_at')).to be(true)
    end
  end

  describe 'GET /settings/two_factor' do
    it 'shows 2FA status page' do
      get settings_two_factor_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /settings/two_factor (enable)' do
    it 'generates OTP secret and shows QR code' do
      expect { post settings_two_factor_path }.to change { user.reload.otp_secret }.from(nil)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Scan QR code')
    end
  end

  describe 'POST /settings/two_factor/verify' do
    before do
      user.update!(otp_secret: User.generate_otp_secret)
    end

    context 'with valid OTP code' do
      it 'enables 2FA and shows backup codes' do
        valid_code = user.current_otp

        post verify_settings_two_factor_path, params: { otp_attempt: valid_code }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Save your backup codes')
        expect(user.reload.otp_required_for_login).to be true
        expect(user.otp_backup_codes).to be_present
      end
    end

    context 'with invalid OTP code' do
      it 'shows error and re-renders QR code' do
        post verify_settings_two_factor_path, params: { otp_attempt: '000000' }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Invalid verification code')
        expect(user.reload.otp_required_for_login).to be false
      end
    end
  end

  describe 'DELETE /settings/two_factor (disable)' do
    before do
      user.update!(
        otp_secret: User.generate_otp_secret,
        otp_required_for_login: true
      )
    end

    context 'with correct password and valid OTP' do
      it 'disables 2FA' do
        delete settings_two_factor_path, params: { password: password, otp_attempt: user.current_otp }

        expect(response).to redirect_to(settings_two_factor_path)
        user.reload
        expect(user.otp_required_for_login).to be false
        expect(user.otp_secret).to be_nil
        expect(user.otp_backup_codes).to be_nil
      end
    end

    context 'with correct password and a valid backup code' do
      it 'disables 2FA' do
        backup = user.generate_otp_backup_codes!.first
        user.save!

        delete settings_two_factor_path, params: { password: password, otp_attempt: backup }

        expect(response).to redirect_to(settings_two_factor_path)
        expect(user.reload.otp_required_for_login).to be false
      end
    end

    context 'with incorrect password' do
      it 'does not disable 2FA' do
        delete settings_two_factor_path, params: { password: 'wrong_password', otp_attempt: user.current_otp }

        expect(response).to redirect_to(settings_two_factor_path)
        expect(flash[:alert]).to eq('Incorrect password.')
        expect(user.reload.otp_required_for_login).to be true
      end
    end

    context 'with correct password but missing OTP' do
      it 'does not disable 2FA' do
        delete settings_two_factor_path, params: { password: password }

        expect(response).to redirect_to(settings_two_factor_path)
        expect(flash[:alert]).to include('valid two-factor code')
        expect(user.reload.otp_required_for_login).to be true
      end
    end

    context 'with correct password but invalid OTP' do
      it 'does not disable 2FA' do
        delete settings_two_factor_path, params: { password: password, otp_attempt: '000000' }

        expect(response).to redirect_to(settings_two_factor_path)
        expect(flash[:alert]).to include('valid two-factor code')
        expect(user.reload.otp_required_for_login).to be true
      end
    end
  end
end
