# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /auth/account_link', type: :request do
  let(:user) { create(:user, email: 'user@example.com') }

  def issue(provider: 'apple', uid: 'apple-sub-42', subject: user)
    Auth::IssueAccountLinkToken.new(subject, provider: provider, uid: uid).call
  end

  before { Rails.cache.clear }

  it 'links the identity and signs the user in when 2FA is NOT required' do
    token = issue
    get "/auth/account_link?token=#{token}"

    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to match(/Sign in with Apple is now linked/)
    user.reload
    expect(user.provider).to eq('apple')
    expect(user.uid).to eq('apple-sub-42')
  end

  context 'with a stashed pending-import ticket' do
    let!(:pending) { create(:pending_import, :with_file) }

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      allow(DawarichSettings).to receive(:registration_enabled?).and_return(true)
      allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
      stub_const('MANAGER_URL', 'https://manager.example.com')
    end

    it 'claims the ticket when the token link signs the user in' do
      get "/users/sign_up?import_ticket=#{pending.claim_ticket}"
      expect(session[:pending_import_ticket]).to eq(pending.claim_ticket)

      token = issue
      expect { get "/auth/account_link?token=#{token}" }
        .to change(user.imports, :count).by(1)

      expect(pending.reload.claimed_by_user_id).to eq(user.id)
    end
  end

  context 'when the user has 2FA enabled' do
    before do
      user.otp_secret = User.generate_otp_secret
      user.otp_required_for_login = true
      user.save!
    end

    it 'links the identity but does NOT sign the user in (no 2FA bypass)' do
      token = issue
      get "/auth/account_link?token=#{token}"

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:notice]).to match(/linked.*Sign in.*2FA/mi)
      user.reload
      expect(user.provider).to eq('apple')
      expect(user.uid).to eq('apple-sub-42')
    end
  end

  it 'rejects a token whose jti has already been atomically consumed' do
    token = issue
    decoded = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY'), false).first
    Auth::VerifyAccountLinkToken.consume!(decoded['jti'])

    get "/auth/account_link?token=#{token}"

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to match(/already been used/i)
    expect(user.reload.provider).to be_nil
  end

  it 'sends Cache-Control: no-store' do
    token = issue
    get "/auth/account_link?token=#{token}"

    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'rejects a replayed link with an "already used" alert' do
    token = issue
    get "/auth/account_link?token=#{token}" # first use, succeeds

    # Replay — sign out to simulate an attacker on a different session
    delete destroy_user_session_path
    get "/auth/account_link?token=#{token}"

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to match(/already been used/i)
  end

  it 'rejects an invalid token' do
    get '/auth/account_link?token=not.a.real.jwt'

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to match(/invalid or expired/i)
  end

  context 'when the user is already linked to a different oauth identity' do
    before { user.update!(provider: 'google', uid: 'google-existing') }

    it 'refuses to overwrite and redirects to sign-in with an explanatory alert' do
      token = issue(provider: 'apple', uid: 'apple-sub-42')
      get "/auth/account_link?token=#{token}"

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to match(/already linked to a different google/i)
      user.reload
      expect(user.provider).to eq('google')
      expect(user.uid).to eq('google-existing')
    end

    it 'does NOT consume the token when refusing the overwrite' do
      token = issue(provider: 'apple', uid: 'apple-sub-42')
      get "/auth/account_link?token=#{token}" # rejected, token NOT consumed

      user.update!(provider: nil, uid: nil)
      get "/auth/account_link?token=#{token}"
      expect(user.reload.provider).to eq('apple')
    end
  end
end

RSpec.describe 'OAuth account-link password challenge', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { 'secret-password-123' }
  let(:email) { 'oauth_user@example.com' }
  let!(:user) { create(:user, email: email, password: password, provider: nil, uid: nil) }

  before(:all) do
    Rails.application.routes.append do
      devise_scope :user do
        get 'users/auth/openid_connect/callback', to: 'users/omniauth_callbacks#openid_connect'
      end
    end
    Rails.application.reload_routes!
  end

  before do
    Rails.application.env_config['devise.mapping'] = Devise.mappings[:user]
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:openid_connect] = OmniAuth::AuthHash.new(
      provider: 'openid_connect',
      uid: '123545',
      info: { email: email, name: 'Test' },
      extra: { raw_info: { email_verified: true } }
    )
    Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:openid_connect]
    Rails.cache.clear
  end

  after do
    OmniAuth.config.mock_auth[:openid_connect] = nil
    Rails.application.env_config.delete('omniauth.auth')
  end

  def trigger_collision
    get '/users/auth/openid_connect/callback'
    expect(response).to redirect_to(auth_account_link_challenge_path)
  end

  describe 'GET /auth/account_link/challenge' do
    it 'renders the password form after an OAuth email collision' do
      trigger_collision
      get auth_account_link_challenge_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(email)
    end

    it 'renders complete French account-link instructions' do
      trigger_collision
      get auth_account_link_challenge_path(locale: 'fr')

      expect(response.body).to include('Associer OpenID Connect à votre compte Dawarich')
      expect(response.body).to include('Saisissez votre mot de passe pour y associer votre identité OpenID Connect')
    end

    it 'redirects to sign-in when no pending link in session' do
      get auth_account_link_challenge_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirects to sign-in once the pending link has expired' do
      trigger_collision
      travel 16.minutes do
        get auth_account_link_challenge_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'POST /auth/account_link/challenge' do
    it 'links the identity and signs in when password is correct' do
      trigger_collision
      post confirm_auth_account_link_path, params: { password: password }

      expect(response).to redirect_to(root_path)
      user.reload
      expect(user.provider).to eq('openid_connect')
      expect(user.uid).to eq('123545')
    end

    it 'rejects an incorrect password without linking' do
      trigger_collision
      post confirm_auth_account_link_path, params: { password: 'wrong-password' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('Incorrect password')
      user.reload
      expect(user.provider).to be_nil
      expect(user.uid).to be_nil
    end

    it 'redirects to sign-in (without linking) when no pending link' do
      post confirm_auth_account_link_path, params: { password: password }

      expect(response).to redirect_to(new_user_session_path)
      expect(user.reload.provider).to be_nil
    end

    context 'when the user has 2FA enabled' do
      before do
        user.otp_secret = User.generate_otp_secret
        user.otp_required_for_login = true
        user.save!
      end

      it 'links but does NOT sign the user in (no 2FA bypass)' do
        trigger_collision
        post confirm_auth_account_link_path, params: { password: password }

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:notice]).to match(/2FA/)
        expect(user.reload.provider).to eq('openid_connect')
      end
    end

    it 'clears pending state and bounces to sign-in after 5 invalid attempts' do
      trigger_collision

      4.times do
        post confirm_auth_account_link_path, params: { password: 'wrong-password' }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      post confirm_auth_account_link_path, params: { password: 'wrong-password' }
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to match(/Too many invalid/)

      get auth_account_link_challenge_path
      expect(response).to redirect_to(new_user_session_path)

      expect(user.reload.provider).to be_nil
    end
  end

  describe 'pending-import ticket on password confirm' do
    let!(:pending) { create(:pending_import, :with_file) }

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      allow(DawarichSettings).to receive(:registration_enabled?).and_return(true)
      allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
      stub_const('MANAGER_URL', 'https://manager.example.com')
    end

    it 'claims the stashed ticket after successful password confirm' do
      get "/users/sign_up?import_ticket=#{pending.claim_ticket}"
      expect(session[:pending_import_ticket]).to eq(pending.claim_ticket)
      trigger_collision

      expect { post confirm_auth_account_link_path, params: { password: password } }
        .to change(user.imports, :count).by(1)

      expect(pending.reload.claimed_by_user_id).to eq(user.id)
    end
  end

  describe 'rack-attack throttle on /auth/account_link/challenge' do
    it 'declares both per-session and per-IP throttles' do
      throttle_names = Rack::Attack.throttles.keys
      expect(throttle_names).to include('auth/account_link_challenge_session')
      expect(throttle_names).to include('auth/account_link_challenge_ip')

      session_rule = Rack::Attack.throttles['auth/account_link_challenge_session']
      expect(session_rule.limit).to eq(5)
      expect(session_rule.period).to eq(15.minutes.to_i)

      ip_rule = Rack::Attack.throttles['auth/account_link_challenge_ip']
      expect(ip_rule.limit).to eq(20)
      expect(ip_rule.period).to eq(15.minutes.to_i)
    end
  end

  describe 'brute-force guard on /auth/account_link/challenge — kept on self-hosted' do
    before do
      Rack::Attack.enabled = true
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      Rack::Attack.reset!
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      freeze_time
    end

    after do
      Rack::Attack.enabled = false
      travel_back
    end

    it 'throttles auth/account_link_challenge_session at 5/15min for the same pending link' do
      6.times do
        reset!
        trigger_collision
        post confirm_auth_account_link_path, params: { password: 'wrong-password' }
      end

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'throttles auth/account_link_challenge_ip at 20/15min across different pending links' do
      21.times do |i|
        reset!
        other_user = create(:user, email: "ip-guard-#{i}@example.com", password: password, provider: nil, uid: nil)
        OmniAuth.config.mock_auth[:openid_connect] = OmniAuth::AuthHash.new(
          provider: 'openid_connect',
          uid: "ip-guard-sub-#{i}",
          info: { email: other_user.email, name: 'Test' },
          extra: { raw_info: { email_verified: true } }
        )
        Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:openid_connect]
        get '/users/auth/openid_connect/callback'

        post confirm_auth_account_link_path, params: { password: 'wrong-password' }
      end

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'POST /auth/account_link/email' do
    it 'enqueues the OAuth link mailer and flashes the affirmative notice on the genuine first send' do
      trigger_collision
      expect do
        post email_fallback_auth_account_link_path
      end.to have_enqueued_job(Users::MailerSendingJob)
        .with(user.id, 'oauth_account_link', hash_including(:provider_label, :link_url))

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:notice]).to match(/we sent a confirmation link/i)
      expect(flash[:alert]).to be_nil
    end

    it 'email fallback produces the same command' do
      trigger_collision
      JobOutbox.delete_all
      job_owner!('command:mail.user.oauth_account_link', :oban)

      expect { post email_fallback_auth_account_link_path }.not_to have_enqueued_job(Users::MailerSendingJob)

      row = JobOutbox.sole
      token = Rack::Utils.parse_query(URI.parse(row.payload.fetch('link_url')).query).fetch('token')
      digest = Digest::SHA256.hexdigest(token)
      expect(row).to have_attributes(command_type: 'mail.user.oauth_account_link', aggregate_id: user.id,
                                     dedupe_key: "oauth-link:#{user.id}:#{digest}")
      expect(row.payload).to include('user_id' => user.id, 'provider_label' => 'OpenID Connect',
                                     'link_token_sha256' => digest,
                                     'link_expires_at' => JWT.decode(token, nil, false).first.fetch('exp'))
    end

    it 'does not re-send within the rate-limit window' do
      trigger_collision
      post email_fallback_auth_account_link_path

      expect do
        post email_fallback_auth_account_link_path
      end.not_to have_enqueued_job(Users::MailerSendingJob)
    end

    it 'flashes a distinct rate-limit alert (not the affirmative notice) when the resend is rate-limited' do
      trigger_collision
      # Pre-seed the per-account rate-limit cache key, as if a prior send within
      # the 1-hour window already occurred.
      Rails.cache.write(
        "#{Auth::FindOrCreateOauthUser::LINK_EMAIL_RATE_LIMIT_KEY_PREFIX}#{user.id}",
        true,
        expires_in: Auth::FindOrCreateOauthUser::LINK_EMAIL_RATE_LIMIT_WINDOW
      )

      expect do
        post email_fallback_auth_account_link_path
      end.not_to have_enqueued_job(Users::MailerSendingJob)

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to match(/confirmation link was already sent|wait before requesting/i)
      expect(flash[:notice]).to be_nil
    end
  end
end

RSpec.describe 'A11e account link source oracle', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.utc(2026, 10, 5, 12) }
  let(:password) { 'a11e-synthetic-password-123' }
  let!(:user) { create(:user, email: 'a11e-oracle@example.invalid', password: password, provider: nil, uid: nil) }

  around do |example|
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  before(:context) do
    Rails.application.routes.append do
      devise_scope :user do
        get 'users/auth/openid_connect/callback', to: 'users/omniauth_callbacks#openid_connect'
      end
    end
    Rails.application.reload_routes!
  end

  before do
    @previous_auth = Rails.application.env_config['omniauth.auth']
    @previous_test_mode = OmniAuth.config.test_mode
    @previous_mock = OmniAuth.config.mock_auth[:openid_connect]
    Rails.application.env_config['devise.mapping'] = Devise.mappings[:user]
    OmniAuth.config.test_mode = true
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
  end

  after do
    Rails.application.env_config['omniauth.auth'] = @previous_auth
    OmniAuth.config.test_mode = @previous_test_mode
    OmniAuth.config.mock_auth[:openid_connect] = @previous_mock
  end

  def link_session(client)
    jar = ActionDispatch::Cookies::CookieJar.build(
      ActionDispatch::Request.new(Rails.application.env_config.dup),
      '_dawarich_session' => client.cookies['_dawarich_session']
    )
    jar.encrypted['_dawarich_session']
  end

  def link_seed(client, data)
    jar = ActionDispatch::Request.new(Rails.application.env_config.dup).cookie_jar
    jar.encrypted['_dawarich_session'] = { value: data }
    client.cookies['_dawarich_session'] = jar['_dawarich_session']
  end

  def link_client
    ActionDispatch::Integration::Session.new(Rails.application)
  end

  def link_collision(client, actor: user, uid: 'a11e-sub-A')
    auth = OmniAuth::AuthHash.new(provider: 'openid_connect', uid: uid,
                                  info: { email: actor.email, name: 'Synthetic' },
                                  extra: { raw_info: { email_verified: true } })
    OmniAuth.config.mock_auth[:openid_connect] = auth
    Rails.application.env_config['omniauth.auth'] = auth
    client.get('/users/auth/openid_connect/callback')
    expect(client.response.status).to eq(302)
    expect(client.response.location).to end_with('/auth/account_link/challenge')
    client.get('/auth/account_link/challenge')
    expect(client.response.status).to eq(200)
    client
  end

  def link_token(client, action: '/auth/account_link/challenge')
    Nokogiri::HTML5(client.response.body).at_css("form[action='#{action}'] input[name='authenticity_token']")['value']
  end

  def link_confirm(client, token: link_token(client), attempt: password, headers: {})
    params = { authenticity_token: token }
    params[:password] = attempt unless attempt == :missing
    client.post('/auth/account_link/challenge', params: params, headers: headers)
  end

  def link_pair(client)
    [client.cookies['_dawarich_session'], link_token(client)]
  end

  def link_copy(pair)
    client = link_client
    client.cookies['_dawarich_session'] = pair.first
    client
  end

  def link_state(actor = user)
    actor.reload.attributes.slice('provider', 'uid', 'encrypted_password', 'email', 'settings', 'api_key',
                                  'sign_in_count', 'current_sign_in_at', 'last_sign_in_at',
                                  'current_sign_in_ip', 'last_sign_in_ip', 'failed_attempts', 'locked_at',
                                  'unlock_token', 'remember_created_at', 'otp_required_for_login', 'otp_secret',
                                  'consumed_timestep', 'failed_otp_attempts', 'otp_locked_at', 'otp_backup_codes')
  end

  def link_completed(client, actor: user, otp: false)
    expect(client.response.status).to eq(302)
    expect(client.response.location).to end_with(otp ? '/users/sign_in' : '/')
    data = link_session(client)
    expect(data.keys & %w[pending_oauth_link pending_oauth_link_attempts]).to be_empty
    expect(data.key?('warden.user.user.key')).to eq(!otp)
    expect(data['warden.user.user.key'] == [[actor.id], actor.authenticatable_salt]).to be(true) unless otp
    expect(client.cookies['remember_user_token']).to be_nil
    expect(client.response.headers['Cache-Control']).to eq('no-store')
    expect(client.response.headers['Pragma']).to eq('no-cache')
  end

  it 'A11e pending challenge preserves source TTL form and no authentication effects' do
    travel_to(now) do
      before = link_state
      jobs = enqueued_jobs.size
      client = link_collision(link_client)
      pending = link_session(client)
      expect(pending['pending_oauth_link']).to eq('user_id' => user.id, 'provider' => 'openid_connect',
                                                  'uid' => 'a11e-sub-A', 'provider_label' => 'OpenID Connect',
                                                  'expires_at' => now.to_i + 900)
      expect(pending.keys).not_to include('warden.user.user.key')
      %w[en de fr].each do |locale|
        client.get('/auth/account_link/challenge', params: { locale: locale })
        doc = Nokogiri::HTML5(client.response.body)
        expect(client.response.status).to eq(200)
        expect(doc.css('form').map { |form| form['action'] })
          .to include('/auth/account_link/challenge', '/auth/account_link/email')
        expect(doc.at_css('input[name=password]')['value']).to be_nil
        expect(doc.at_css('input[name=password]')['autocomplete']).to eq('current-password')
        expect(doc.text).to include(user.email)
        expect(client.response.headers.values_at('Cache-Control', 'Pragma')).to eq(%w[no-store no-cache])
      end
      data = link_session(client).merge('pending_oauth_link_attempts' => 3)
      link_seed(client, data)
      link_collision(client, uid: 'a11e-sub-B')
      expect(link_session(client)['pending_oauth_link_attempts']).to eq(3)
      expect(link_session(client).dig('pending_oauth_link', 'uid')).to eq('a11e-sub-B')
      [now.to_i, now.to_i + 86_400, now.to_i - 1].each do |expiry|
        data = link_session(client)
        data['pending_oauth_link']['expires_at'] = expiry
        link_seed(client, data)
        client.get('/auth/account_link/challenge')
        expect(client.response.status).to eq(expiry < now.to_i ? 302 : 200)
        expect(link_session(client)['pending_oauth_link']['expires_at']).to eq(expiry)
      end
      data['pending_oauth_link'].merge!('expires_at' => now.to_i, 'provider_label' => '<script>synthetic</script>')
      link_seed(client, data)
      client.get('/auth/account_link/challenge')
      expect(client.response.body).to include('&lt;script&gt;synthetic&lt;/script&gt;')
      expect(client.response.body).not_to include('<script>synthetic</script>')
      data['pending_oauth_link'].delete('provider_label')
      link_seed(client, data)
      client.get('/auth/account_link/challenge')
      expect(Nokogiri::HTML5(client.response.body).text).to include(OIDC_PROVIDER_NAME)
      data['pending_oauth_link']['user_id'] = user.id + 999_999
      link_seed(client, data)
      client.get('/auth/account_link/challenge')
      expect(client.response.location).to end_with('/users/sign_in')
      expect(link_state).to eq(before)
      expect(enqueued_jobs.size).to eq(jobs)
    end
  end

  it 'A11e confirmation preserves identity save default sign-in and OTP no-bypass ordering' do
    travel_to(now) do
      other = create(:user)
      other_before = link_state(other)
      [false, true].each do |otp|
        user.update_columns(provider: nil, uid: nil, otp_required_for_login: otp, failed_attempts: 2,
                            failed_otp_attempts: 3, consumed_timestep: 42, otp_locked_at: now - 60,
                            remember_created_at: now - 86_400, unlock_token: 'a11e-synthetic-unlock')
        client = link_collision(link_client)
        data = link_session(client).merge('pending_oauth_link_attempts' => 3, 'user_return_to' => '/trips',
                                          'devise.synthetic' => 'expire',
                                          'warden.user.user.session' => { 'a11e' => 42 })
        link_seed(client, data)
        before = link_state
        order = []
        controller_stub = allow_any_instance_of(Auth::AccountLinksController)
        controller_stub.to receive(:clear_pending_oauth_link).and_wrap_original do |original|
          expect(user.reload.provider).to eq('openid_connect')
          expect(user.uid).to eq('a11e-sub-A')
          order << :clear
          original.call
        end
        allow_any_instance_of(Auth::AccountLinksController).to receive(:sign_in).and_wrap_original do |original, actor|
          controller = original.receiver
          expect(controller.session.keys & %w[pending_oauth_link pending_oauth_link_attempts]).to be_empty
          order << :sign_in
          original.call(actor)
        end
        writes = []
        listener = ->(*args) { writes << args.last[:sql] if args.last[:sql].start_with?('UPDATE "users"') }
        ActiveSupport::Notifications.subscribed(listener, 'sql.active_record') { link_confirm(client) }
        link_completed(client, otp: otp)
        after = link_state
        expect(after.slice('provider', 'uid')).to eq('provider' => 'openid_connect', 'uid' => 'a11e-sub-A')
        expect(after.except('provider', 'uid', 'sign_in_count', 'current_sign_in_at', 'last_sign_in_at',
                            'current_sign_in_ip', 'last_sign_in_ip', 'failed_attempts'))
          .to eq(before.except('provider', 'uid', 'sign_in_count', 'current_sign_in_at', 'last_sign_in_at',
                               'current_sign_in_ip', 'last_sign_in_ip', 'failed_attempts'))
        expect(after['sign_in_count']).to eq(before['sign_in_count'] + (otp ? 0 : 1))
        expect(after['failed_attempts']).to eq(otp ? 2 : 0)
        expect(order).to eq(otp ? [:clear] : %i[clear sign_in])
        completed = link_session(client)
        expect(completed['_csrf_token'] == data['_csrf_token']).to be(true)
        expect(completed['user_return_to']).to eq('/trips')
        expect(completed['session_id'] == data['session_id']).to eq(otp)
        expect(completed.key?('devise.synthetic')).to eq(otp)
        expect(completed['warden.user.user.session']).to eq('a11e' => 42)
        expect(completed.dig('flash', 'flashes', 'notice')).to match(otp ? /2FA/ : /now linked/)
        next if otp

        expect(writes.index { |sql| sql.include?('provider') }).to be < writes.index { |sql|
          sql.include?('sign_in_count')
        }
        expect(writes.index { |sql| sql.include?('failed_attempts') }).to be < writes.index { |sql|
          sql.include?('sign_in_count')
        }
      end
      expect(link_state(other)).to eq(other_before)
      user.update_columns(provider: nil, uid: nil, otp_required_for_login: false)
      client = link_collision(link_client)
      conflicting = create(:user, provider: 'openid_connect', uid: 'a11e-sub-A')
      before = link_state
      pending = link_session(client)
      expect { link_confirm(client) }.to raise_error(ActiveRecord::RecordNotUnique)
      expect(link_state).to eq(before)
      expect(link_session(client)['pending_oauth_link'] == pending['pending_oauth_link']).to be(true)
      conflicting.update_columns(provider: nil, uid: nil)

      user.update_columns(provider: 'google', uid: 'a11e-existing')
      client = link_collision(link_client)
      link_confirm(client)
      link_completed(client)
      expect(user.reload.uid).to eq('a11e-sub-A')

      user.update_columns(provider: nil, uid: nil, locked_at: now - 60, failed_attempts: 5)
      client = link_collision(link_client)
      count = user.sign_in_count
      link_confirm(client)
      expect(client.response.location).to end_with('/users/sign_in')
      expect(user.reload.provider).to eq('openid_connect')
      expect(user.sign_in_count).to eq(count)
      expect(link_session(client).keys).not_to include('pending_oauth_link', 'warden.user.user.key')
      user.update_columns(provider: nil, uid: nil, locked_at: nil)
      client = link_collision(link_client)
      data = link_session(client).merge('otp_user_id' => other.id, 'otp_failed_attempts' => 4,
                                        'partnero_referral' => 'a11e-synthetic')
      link_seed(client, data)
      link_confirm(client)
      link_completed(client)
      expect(link_session(client).slice('otp_user_id', 'otp_failed_attempts', 'partnero_referral'))
        .to eq(data.slice('otp_user_id', 'otp_failed_attempts', 'partnero_referral'))

      user.update_columns(provider: nil, uid: nil)
      client = link_collision(link_client)
      allow_any_instance_of(User).to receive(:update_tracked_fields!).and_raise('a11e-later-callback')
      expect { link_confirm(client) }.to raise_error(RuntimeError, 'a11e-later-callback')
      expect(user.reload.provider).to eq('openid_connect')
      expect(user.uid).to eq('a11e-sub-A')
    end
  end

  it 'A11e account link Rails CSRF negatives have no identity or authentication effects' do
    travel_to(now) do
      client = link_collision(link_client)
      pair = link_pair(client)
      foreign = link_collision(link_client)
      controller = Auth::AccountLinksController.new
      controller.set_request!(client.request)
      wrong_action = controller.send(:form_authenticity_token,
                                     form_options: { action: '/auth/account_link/email', method: 'post' })
      negatives = [['missing', nil, {}], ['foreign session', link_token(foreign), {}],
                   ['wrong action', wrong_action, {}],
                   ['foreign origin', pair.last, { 'HTTP_ORIGIN' => 'https://foreign.example.invalid' }]]
      before = link_state
      negatives.each do |name, token, headers|
        victim = link_copy(pair)
        link_confirm(victim, token: token, headers: headers)
        expect(victim.response.status).to eq(422), name
        expect(link_state).to eq(before)
        expect(link_session(victim).keys).not_to include('warden.user.user.key')
      end
      victim = link_copy(pair)
      link_confirm(victim, token: pair.last, headers: { 'HTTP_ORIGIN' => 'http://www.example.com' })
      link_completed(victim)
    end
  end

  it 'A11e account link saved-cookie sequential replay records Rails outcome' do
    travel_to(now) do
      client = link_collision(link_client)
      pair = link_pair(client)
      count = user.sign_in_count
      2.times do |index|
        victim = link_copy(pair)
        link_confirm(victim, token: pair.last)
        link_completed(victim)
        expect(user.reload.sign_in_count).to eq(count + index + 1)
        expect(user.attributes.slice('provider', 'uid')).to eq('provider' => 'openid_connect', 'uid' => 'a11e-sub-A')
      end
    end
  end

  it 'A11e account link superseded collision records Rails outcome' do
    travel_to(now) do
      client = link_collision(link_client)
      first = link_pair(client)
      link_collision(client, uid: 'a11e-sub-B')
      second = link_pair(client)
      count = user.sign_in_count
      [first, second].each_with_index do |pair, index|
        victim = link_copy(pair)
        link_confirm(victim, token: pair.last)
        link_completed(victim)
        expect(user.reload.uid).to eq(index.zero? ? 'a11e-sub-A' : 'a11e-sub-B')
        expect(user.sign_in_count).to eq(count + index + 1)
      end
    end
  end

  it 'A11e account link matching cookie token transplant records Rails outcome' do
    travel_to(now) do
      source = link_collision(link_client)
      pair = link_pair(source)
      unrelated_browser = link_client
      unrelated_browser.get('/users/sign_in')
      expect(link_session(unrelated_browser)['session_id'] == link_session(source)['session_id']).to be(false)
      unrelated_browser.cookies['_dawarich_session'] = pair.first
      count = user.sign_in_count
      link_confirm(unrelated_browser, token: pair.last)
      link_completed(unrelated_browser)
      expect(user.reload.sign_in_count).to eq(count + 1)
      expect(user.uid).to eq('a11e-sub-A')
    end
  end

  it 'A11e Rails refusal and mixed counter store remain authoritative' do
    before = link_state
    travel_to(now) do
      client = link_collision(link_client)
      4.times do |index|
        link_confirm(client, attempt: index.zero? ? :missing : '')
        expect(client.response.status).to eq(422)
        expect(link_session(client)['pending_oauth_link_attempts']).to eq(index + 1)
        expect(Nokogiri::HTML5(client.response.body).at_css('input[name=password]')['value']).to be_nil
        expect(link_state).to eq(before)
      end
      link_confirm(client, attempt: 'incorrect')
      expect(client.response.status).to eq(302)
      expect(link_session(client).keys & %w[pending_oauth_link pending_oauth_link_attempts]).to be_empty
      client.get('/auth/account_link/challenge')
      expect(client.response.location).to end_with('/users/sign_in')
      client = link_collision(link_client)
      token = link_token(client)
      data = link_session(client)
      data['pending_oauth_link']['expires_at'] = now.to_i - 1
      link_seed(client, data)
      link_confirm(client, token: token)
      expect(client.response.location).to end_with('/users/sign_in')
      expect(link_session(client).dig('pending_oauth_link', 'expires_at')).to eq(now.to_i - 1)
      expect(link_state).to eq(before)
    end

    previous_enabled = Rack::Attack.enabled
    previous_store = Rack::Attack.cache.store
    owned = []
    begin
      Rack::Attack.enabled = true
      Rack::Attack.cache.store = RackAttack::PhoenixCounterStore.new
      expect(Rack::Attack.enabled).to be(true)
      expect(Rack::Attack.cache.store).to be_a(RackAttack::PhoenixCounterStore)
      boundary = Time.at((Time.current.to_i / 900 + 1) * 900).utc
      travel_to(boundary) do
        client = link_collision(link_client)
        pair = link_pair(client)
        ip = '198.51.100.231'
        session_key = "rack::attack:#{boundary.to_i / 900}:auth/account_link_challenge_session:#{user.id}"
        ip_key = "rack::attack:#{boundary.to_i / 900}:auth/account_link_challenge_ip:#{ip}"
        second_ip_key = "rack::attack:#{boundary.to_i / 900}:auth/account_link_challenge_ip:198.51.100.232"
        [session_key, ip_key, second_ip_key].each do |key|
          expect(link_counter('count(*)', key)).to eq(0)
          owned << key
        end
        6.times do |index|
          victim = link_copy(pair)
          link_confirm(victim, token: pair.last, attempt: 'wrong', headers: { 'REMOTE_ADDR' => ip })
          expect(victim.response.status).to eq(index < 5 ? 422 : 429)
          expect(link_state).to eq(before)
          next unless index == 5

          expect(JSON.parse(victim.response.body)['error']).to eq('rate_limit_exceeded')
          expect(victim.response.headers['Retry-After']).to eq('900')
          expect(victim.response.headers['Cache-Control']).to eq('no-cache')
        end
        expect(link_counter('value', session_key)).to eq(6)
        expect(link_counter('value', ip_key)).to eq(5)
        21.times do |index|
          victim = link_copy(pair)
          data = link_session(victim)
          data['pending_oauth_link']['user_id'] = user.id + 10_000 + index
          link_seed(victim, data)
          suffix = data['pending_oauth_link']['user_id']
          key = "rack::attack:#{boundary.to_i / 900}:auth/account_link_challenge_session:#{suffix}"
          expect(link_counter('count(*)', key)).to eq(0)
          owned << key
          link_confirm(victim, token: pair.last, headers: { 'REMOTE_ADDR' => '198.51.100.232' })
          expect(victim.response.status).to eq(index < 20 ? 302 : 429)
        end
        key = "rack::attack:#{boundary.to_i / 900}:auth/account_link_challenge_ip:198.51.100.232"
        owned << key
        expect(link_counter('value', key)).to eq(21)
        travel_to(boundary + 900)
        victim = link_copy(pair)
        ["auth/account_link_challenge_session:#{user.id}", "auth/account_link_challenge_ip:#{ip}"].each do |suffix|
          owned << "rack::attack:#{(boundary.to_i + 900) / 900}:#{suffix}"
        end
        link_confirm(victim, token: pair.last, attempt: 'wrong', headers: { 'REMOTE_ADDR' => ip })
        expect(victim.response.status).to eq(422)
      end
    ensure
      Rack::Attack.enabled = previous_enabled
      Rack::Attack.cache.store = previous_store
      owned.each do |key|
        ActiveRecord::Base.connection.execute("DELETE FROM phoenix.counters WHERE key=#{ActiveRecord::Base.connection.quote(key)}")
      end
    end
  end

  it 'A11e account-link counter store failures preserve Rails fail-open confirmation' do
    previous_enabled = Rack::Attack.enabled
    previous_store = Rack::Attack.cache.store
    client = link_collision(link_client)
    pair = link_pair(client)
    store = RackAttack::PhoenixCounterStore.new
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = store
    expect(Rack::Attack.cache.store).to equal(store)
    allow(store).to receive(:table?).and_raise(ActiveRecord::ConnectionNotEstablished, 'a11e-counter-down')
    expect(store).to receive(:write).with(anything, 1, expires_in: anything).twice.and_call_original
    before = link_state
    link_confirm(client, token: pair.last)
    link_completed(client)
    expect(user.reload.provider).to eq('openid_connect')
    expect(user.uid).to eq('a11e-sub-A')
    expect(user.sign_in_count).to eq(before['sign_in_count'] + 1)
    expect(user.failed_attempts).to eq(0)
  ensure
    Rack::Attack.enabled = previous_enabled
    Rack::Attack.cache.store = previous_store
  end

  it 'A11e pending GET preserves and escapes the incoming alert for one request' do
    client = link_collision(link_client)
    data = link_session(client)
    alert = 'A11e <script>synthetic</script> & retry'
    before = link_state
    link_seed(client, data.merge('flash' => { 'discard' => [], 'flashes' => { 'alert' => alert } }))
    client.get('/auth/account_link/challenge')
    card = Nokogiri::HTML5(client.response.body).at_css('.card-body .alert-error')
    expect(card).not_to be_nil
    expect(card.text.strip).to eq(alert)
    expect(card.css('script')).to be_empty
    expect(link_state).to eq(before)
    expect(link_session(client)).not_to have_key('warden.user.user.key')
    client.get('/auth/account_link/challenge')
    expect(Nokogiri::HTML5(client.response.body).at_css('.card-body .alert-error')).to be_nil
    expect(link_state).to eq(before)
    link_seed(client, data.merge('flash' => { 'discard' => [], 'flashes' => { 'alert' => '  ' } }))
    client.get('/auth/account_link/challenge')
    expect(Nokogiri::HTML5(client.response.body).at_css('.card-body .alert-error')).to be_nil
  end

  it 'A11e pending GET renders non-string alerts without authentication effects' do
    client = link_collision(link_client)
    data = link_session(client)
    before = link_state

    [0, true].each do |alert|
      link_seed(client, data.merge('flash' => { 'discard' => [], 'flashes' => { 'alert' => alert } }))
      client.get('/auth/account_link/challenge')
      card = Nokogiri::HTML5(client.response.body).at_css('.card-body .alert-error')
      expect(client.response.status).to eq(200)
      expect(card).not_to be_nil
      expect(card.text.strip).to eq(alert.to_s)
      expect(link_state).to eq(before)
      expect(link_session(client)).not_to have_key('warden.user.user.key')
      client.get('/auth/account_link/challenge')
      expect(Nokogiri::HTML5(client.response.body).at_css('.card-body .alert-error')).to be_nil
      expect(link_state).to eq(before)
    end
  end

  it 'A11e first counter failure still enforces the healthy IP limit' do
    previous_enabled = Rack::Attack.enabled
    previous_store = Rack::Attack.cache.store
    store = RackAttack::PhoenixCounterStore.new
    client = link_collision(link_client)
    pair = link_pair(client)
    before = link_state
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = store
    boundary = Time.at((Time.current.to_i / 900 + 1) * 900).utc
    ip = '198.51.100.239'
    key = "rack::attack:#{boundary.to_i / 900}:auth/account_link_challenge_ip:#{ip}"
    expect(link_counter('count(*)', key)).to eq(0)
    owned_key = key
    travel_to(boundary) do
      store.increment(key, 20, expires_in: 901)
      connection = ActiveRecord::Base.connection
      allow(connection).to receive(:select_value).and_call_original
      allow(connection).to receive(:select_value).with(%r{auth/account_link_challenge_session:}) do
        raise ActiveRecord::ConnectionNotEstablished, 'a11e-session-counter-down'
      end
      link_confirm(client, token: pair.last, headers: { 'REMOTE_ADDR' => ip })
      expect(client.response.status).to eq(429)
      expect(link_counter('value', key)).to eq(21)
      expect(link_state).to eq(before)
      expect(link_session(client)).not_to have_key('warden.user.user.key')
      expect(JSON.parse(client.response.body)['error']).to eq('rate_limit_exceeded')
    end
  ensure
    Rack::Attack.enabled = previous_enabled
    Rack::Attack.cache.store = previous_store
    if owned_key
      connection = ActiveRecord::Base.connection
      connection.execute("DELETE FROM phoenix.counters WHERE key=#{connection.quote(owned_key)}")
    end
  end

  def link_counter(column, key)
    connection = ActiveRecord::Base.connection
    connection.select_value("SELECT #{column} FROM phoenix.counters WHERE key=#{connection.quote(key)}")
  end

  it 'A11e account link Rails password byte edges characterize valid_password and confirmation' do
    travel_to(now) do
      vectors = [
        ['normal', password, password, true],
        ['missing', password, :missing, false],
        ['empty', password, '', false],
        ['whitespace', ' ' * 12, ' ' * 12, true],
        ['72 bytes', "#{'a' * 71}b", "#{'a' * 71}b", true],
        ['73 bytes', "#{'a' * 71}bc", "#{'a' * 71}bd", true],
        ['prefix mismatch', "#{'a' * 71}b", "#{'a' * 71}c", false],
        ['multibyte crossing', "#{'a' * 71}é", "#{'a' * 71}ê", true],
        ['NUL', password, "#{password}\0ignored", :nul],
        ['blank hash', '', password, false],
        ['malformed hash', 'invalid-bcrypt', password, :invalid]
      ]
      vectors.each do |name, original, submitted, expected|
        hash = name.end_with?('hash') ? original : Devise::Encryptor.digest(User, original)
        user.update_columns(encrypted_password: hash, provider: nil, uid: nil, failed_attempts: 2,
                            failed_otp_attempts: 3, consumed_timestep: 42, remember_created_at: now - 86_400)
        before = link_state
        value = submitted == :missing ? '' : submitted
        result = begin
          user.valid_password?(value)
        rescue StandardError => e
          e.class.name
        end
        outcome = { nul: 'ArgumentError', invalid: 'BCrypt::Errors::InvalidHash' }.fetch(expected, expected)
        expect(result).to eq(outcome), name
        expect(link_state).to eq(before)
        client = link_collision(link_client)
        if outcome.is_a?(String)
          expect { link_confirm(client, attempt: submitted) }.to raise_error(Object.const_get(outcome)), name
          expect(link_state).to eq(before)
        else
          link_confirm(client, attempt: submitted)
          expect(client.response.status).to eq(expected ? 302 : 422), name
          after = link_state
          if expected
            link_completed(client)
            expect(after.except('provider', 'uid', 'failed_attempts', 'sign_in_count', 'current_sign_in_at',
                                'last_sign_in_at', 'current_sign_in_ip', 'last_sign_in_ip'))
              .to eq(before.except('provider', 'uid', 'failed_attempts', 'sign_in_count', 'current_sign_in_at',
                                   'last_sign_in_at', 'current_sign_in_ip', 'last_sign_in_ip')), name
            expect(after['sign_in_count']).to eq(before['sign_in_count'] + 1)
            expect(after['failed_attempts']).to eq(0)
          else
            expect(after).to eq(before), name
            expect(link_session(client)['pending_oauth_link_attempts']).to eq(1)
          end
        end
      end
    end
  end

  context 'committed A11e source schedules' do
    before(:context) do
      @previous_transactional_tests = self.class.use_transactional_tests
      self.class.use_transactional_tests = false
    end

    after(:context) do
      self.class.use_transactional_tests = @previous_transactional_tests
    end

    let!(:user) { committed_link_actor(911_450_001, 'a11e-overlap-1@example.invalid') }

    before do
      expect(ActiveRecord::Base.connection_pool.size).to be >= 3
      @observer = ActiveRecord::Base.connection_pool.checkout
    end

    after do
      ActiveRecord::Base.connection_pool.checkin(@observer) if @observer
      Array(@owned_actors).each do |id, email|
        User.unscoped.where(id: id, email: email).delete_all
      end
    end

    def committed_link_actor(id, email)
      expect(User.unscoped.where('id = ? OR email = ?', id, email).exists?).to be(false)
      @owned_actors ||= []
      @owned_actors << [id, email]
      create(:user, id: id, email: email, password: password, provider: nil, uid: nil,
                    skip_auto_trial: true, skip_family_sync: true)
    end

    def prepared_link_requests(actors, pairs)
      ready = Queue.new
      release = [Queue.new, Queue.new]
      allow_any_instance_of(User).to receive(:valid_password?).and_wrap_original do |original, value|
        valid = original.call(value)
        index = Thread.current[:a11e_worker]
        unless index.nil?
          connection = ActiveRecord::Base.connection
          ready << [index, connection.select_value('SELECT pg_backend_pid()'),
                    original.receiver.id, valid, User.where(id: actors[index].id).exists?]
          release[index].pop
        end
        valid
      end
      workers = actors.each_index.map do |index|
        Thread.new do
          Thread.current[:a11e_worker] = index
          ActiveRecord::Base.connection_pool.with_connection do
            client = link_copy(pairs[index])
            link_confirm(client, token: pairs[index].last)
            { status: client.response.status, session: link_session(client) }
          rescue StandardError => e
            { error: e.class.name }
          end
        end
      end
      prepared = Timeout.timeout(5) { [ready.pop, ready.pop] }
      expect(prepared.map { |row| row[1] }.uniq.size).to eq(2)
      expect(prepared.map { |row| row[2] }.sort).to eq(actors.map(&:id).sort)
      expect(prepared.all? { |row| row[3] && row[4] }).to be(true)
      outcomes = workers.each_index.map do |index|
        release[index] << true
        workers[index].value
      end
      yield outcomes, prepared.map { |row| row[1] }
    ensure
      release&.each { |queue| queue << true }
      workers&.each(&:join)
    end

    def independent_link_read(id, worker_pids = [])
      expect(worker_pids).not_to include(@observer.select_value('SELECT pg_backend_pid()'))
      expect(@observer.transaction_open?).to be(false)
      @observer.select_one(User.sanitize_sql_array(['SELECT * FROM users WHERE id = ?', id]))
    end

    it 'A11e account link overlapping confirmation records Rails outcome' do
      travel_to(now) do
        client = link_collision(link_client)
        pair = link_pair(client)
        count = user.sign_in_count
        prepared_link_requests([user, user], [pair, pair]) do |outcomes, pids|
          expect(outcomes.map { |result| result[:status] }).to eq([302, 302])
          expect(outcomes.all? { |result| result[:session].key?('warden.user.user.key') }).to be(true)
          expect(outcomes.all? do |result|
            (result[:session].keys & %w[pending_oauth_link pending_oauth_link_attempts]).empty?
          end).to be(true)
          observed = independent_link_read(user.id, pids)
          expect(observed.slice('provider', 'uid')).to eq('provider' => 'openid_connect', 'uid' => 'a11e-sub-A')
          expect(observed['sign_in_count']).to eq(count + 1)
        end
      end
    end

    it 'A11e prepared account-link overlap preserves source unique and callback commit behavior' do
      travel_to(now) do
        second = committed_link_actor(911_450_002, 'a11e-overlap-2@example.invalid')
        first_pair = link_pair(link_collision(link_client))
        second_pair = link_pair(link_collision(link_client, actor: second))
        prepared_link_requests([user, second], [first_pair, second_pair]) do |outcomes, pids|
          expect(outcomes.first[:status]).to eq(302)
          expect(outcomes.last[:error]).to eq('ActiveRecord::RecordNotUnique')
          expect(independent_link_read(user.id, pids)['uid']).to eq('a11e-sub-A')
          expect(independent_link_read(second.id, pids).slice('provider', 'uid', 'sign_in_count'))
            .to eq('provider' => nil, 'uid' => nil, 'sign_in_count' => 0)
        end
        user.update_columns(provider: nil, uid: nil)
        client = link_collision(link_client)
        count = user.reload.sign_in_count
        callback_pid = nil
        allow_any_instance_of(User).to receive(:update_tracked_fields!) do
          callback_pid = ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')
          raise 'a11e-durable-callback'
        end
        expect { link_confirm(client) }.to raise_error(RuntimeError, 'a11e-durable-callback')
        observed = independent_link_read(user.id, [callback_pid])
        expect(observed.slice('provider', 'uid', 'sign_in_count'))
          .to eq('provider' => 'openid_connect', 'uid' => 'a11e-sub-A', 'sign_in_count' => count)
      end
    end
  end
end
