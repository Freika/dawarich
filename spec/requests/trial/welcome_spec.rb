# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /trial/welcome', type: :request do
  let(:user) { create(:user, status: :trial, active_until: 7.days.from_now) }
  let(:token) do
    JWT.encode(
      {
        user_id: user.id,
        purpose: 'trial_welcome',
        jti: SecureRandom.uuid,
        exp: 30.minutes.from_now.to_i
      },
      ENV.fetch('JWT_SECRET_KEY', 'test_secret'),
      'HS256'
    )
  end

  before { Rails.cache.clear }

  around do |example|
    if example.metadata[:legacy_welcome]
      with_legacy_welcome { example.run }
    else
      example.run
    end
  end

  it 'signs in the user and redirects to the map with a welcome flash' do
    get "/trial/welcome?token=#{token}"
    expect(response).to have_http_status(:found)
    expect(response).to redirect_to(%r{/map/v\d})
    expect(flash[:notice]).to include('Welcome to Dawarich')
    expect(flash[:notice]).to include(user.active_until.strftime('%B %d, %Y'))
  end

  context 'when active_until is not yet populated (webhook race)' do
    # skip_auto_trial suppresses the `activate` (self-hosted) and
    # `start_trial` (cloud) after_commit hooks so active_until stays nil and
    # we can exercise the path where the subscription callback is still
    # in flight.
    let(:user) do
      create(:user, skip_auto_trial: true, status: :pending_payment, active_until: nil)
    end

    it 'still redirects to the map without raising NoMethodError on nil#strftime' do
      get "/trial/welcome?token=#{token}"

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(%r{/map/v\d})
      expect(flash[:notice]).to include('activated')
    end
  end

  it 'redirects an invalid token to sign-in with a "link invalid or expired" alert' do
    get '/trial/welcome?token=not_a_real_jwt'

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to eq('Link invalid or expired. Please sign in.')
  end

  it 'redirects an expired token to sign-in with the same alert' do
    expired_token = token # generate before stubbing time so exp is based on real "now"
    allow(Time).to receive(:now).and_return(1.hour.from_now)
    get "/trial/welcome?token=#{expired_token}"

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to eq('Link invalid or expired. Please sign in.')
  end

  describe 'security hardening' do
    def issue_welcome_token(user, overrides = {})
      payload = {
        user_id: user.id,
        purpose: 'trial_welcome',
        jti: SecureRandom.uuid,
        exp: 30.minutes.from_now.to_i
      }.merge(overrides)
      JWT.encode(payload, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), 'HS256')
    end

    it 'sends Cache-Control: no-store on the response' do
      t = issue_welcome_token(user)
      get "/trial/welcome?token=#{t}"
      expect(response.headers['Cache-Control']).to include('no-store')
    end

    it 'rejects tokens missing purpose=trial_welcome' do
      payload = {
        user_id: user.id,
        jti: SecureRandom.uuid,
        exp: 30.minutes.from_now.to_i
      }
      bad_token = JWT.encode(payload, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), 'HS256')
      get "/trial/welcome?token=#{bad_token}"
      expect(response).to have_http_status(:found)
    end

    it 'consumes the welcome token so it cannot be reused by an attacker' do
      Rails.cache.clear
      t = issue_welcome_token(user)
      get "/trial/welcome?token=#{t}"
      expect(response).to have_http_status(:found)

      # Simulate the "attacker replays the captured URL from the magic email"
      # after the legitimate user has already visited it.
      delete destroy_user_session_path
      get "/trial/welcome?token=#{t}"
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'silently redirects to the map when the same signed-in user reloads a consumed link' do
      # Browser back / reload / accidental re-visit of the welcome URL after
      # the user has already been onboarded. For the same signed-in user we
      # just send them to the map without adding a new flash (they already
      # saw the welcome notice on first visit) — and never to /users/sign_in
      # (which would trigger Devise's "You are already signed in" alert).
      Rails.cache.clear
      t = issue_welcome_token(user)
      get "/trial/welcome?token=#{t}"
      expect(response).to redirect_to(%r{/map/v\d})

      # Follow the redirect so the first request's flash gets consumed —
      # otherwise Rack carries it into the next request and masks what the
      # reload branch actually sets.
      follow_redirect! if response.redirect?

      # Same session, same signed-in user — simulate reload.
      get "/trial/welcome?token=#{t}"
      expect(response).to redirect_to(%r{/map/v\d})
      expect(flash[:alert]).to be_blank
      # The reload branch intentionally does NOT set a new flash; the prior
      # redirect's notice has already been consumed above.
      expect(flash[:notice]).to be_blank
    end

    it 'refuses auto-signin if a different user is already signed in' do
      other = create(:user, email: 'other@example.com')
      sign_in(other)
      t = issue_welcome_token(user)
      get "/trial/welcome?token=#{t}"
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(root_path)
    end

    it 'sets Referrer-Policy: no-referrer on the response' do
      t = issue_welcome_token(user)
      get "/trial/welcome?token=#{t}"
      expect(response.headers['Referrer-Policy']).to eq('no-referrer')
    end

    it 'sets Referrer-Policy: no-referrer on rejection (invalid token)' do
      get '/trial/welcome?token=garbage'
      expect(response.headers['Referrer-Policy']).to eq('no-referrer')
    end

    it 'unmigrated welcome still writes the original cache DB0 NX entry', :legacy_welcome do
      Rails.cache.clear
      t = issue_welcome_token(user)

      writes = []
      allow(Rails.cache).to receive(:write).and_wrap_original do |original, *args, **opts|
        writes << opts.dup
        original.call(*args, **opts)
      end

      get "/trial/welcome?token=#{t}"
      expect(response).to redirect_to(%r{/map/v\d})

      consume_writes = writes.select { |o| o.key?(:unless_exist) }
      expect(consume_writes).not_to(
        be_empty,
        'Trial welcome consumption MUST use Rails.cache.write(..., unless_exist: true) ' \
        'to be atomic. The non-atomic exist?+write pattern is a TOCTOU bug.'
      )
      expect(consume_writes.first[:unless_exist]).to be(true)
    end

    it 'rejects a second visit when the atomic write returns false (lost the race)', :legacy_welcome do
      Rails.cache.clear
      t = issue_welcome_token(user)

      call_count = 0
      allow(Rails.cache).to receive(:write).and_wrap_original do |original, *args, **opts|
        if opts[:unless_exist]
          call_count += 1
          call_count == 1 ? original.call(*args, **opts) : false
        else
          original.call(*args, **opts)
        end
      end

      get "/trial/welcome?token=#{t}"
      expect(response).to redirect_to(%r{/map/v\d})

      delete destroy_user_session_path
      get "/trial/welcome?token=#{t}"
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to include('already been used')
    end

    it 'Rails welcome consumes PG claim and rejects a PG replay with no cache write' do
      phoenix_state!
      signed = issue_welcome_token(user, jti: 'a13g-rails-pg', exp: 30.minutes.from_now.to_i)
      expect(Rails.cache).not_to receive(:write)
      count = user.reload.sign_in_count
      get '/trial/welcome', params: { token: signed }
      expect(response).to redirect_to(%r{/map/v\d})
      key = "trial_welcome:consumed:sha256:#{Digest::SHA256.hexdigest('a13g-rails-pg')}"
      expect(claim_seconds(key)).to be_between(1798, 1800)
      expect(user.reload.sign_in_count).to eq(count + 1)
      get '/trial/welcome', params: { token: signed }
      expect(response).to redirect_to(%r{/map/v\d})
      expect(user.reload.sign_in_count).to eq(count + 1)
      guest = ActionDispatch::Integration::Session.new(Rails.application)
      guest.get('/trial/welcome', params: { token: signed })
      expect(guest.response.status).to eq(302)
      expect(guest.response.headers['Location']).to end_with(new_user_session_path)
      expect(user.reload.sign_in_count).to eq(count + 1)
    end

    %w[NUL large].each do |kind|
      it "PG Rails welcome preserves signed #{kind} jti source replay outcomes" do
        phoenix_state!
        jti = if kind == 'NUL'
                "a13g-legacy-#{0.chr}-nul"
              else
                Array.new(128) { |index| Digest::SHA256.hexdigest("a13g-legacy-large-#{index}") }.join
              end
        signed = issue_welcome_token(user, jti: jti)
        client = ActionDispatch::Integration::Session.new(Rails.application)
        count = user.reload.sign_in_count
        client.get('/trial/welcome', params: { token: signed })
        expect(client.response.status).to eq(302)
        expect(client.response.headers['Location']).to match(%r{/map/v\d\z})
        expect(user.reload.sign_in_count).to eq(count + 1)
        client.get('/trial/welcome', params: { token: signed })
        expect(client.response.status).to eq(302)
        expect(client.response.headers['Location']).to match(%r{/map/v\d\z})
        guest = ActionDispatch::Integration::Session.new(Rails.application)
        guest.get('/trial/welcome', params: { token: signed })
        expect(guest.response.status).to eq(302)
        expect(guest.response.headers['Location']).to end_with(new_user_session_path)
        expect(guest.response.headers).to include('Cache-Control' => 'no-store', 'Pragma' => 'no-cache',
                                                  'Referrer-Policy' => 'no-referrer')
        expect(user.reload.sign_in_count).to eq(count + 1)
        key = "trial_welcome:consumed:sha256:#{Digest::SHA256.hexdigest(jti)}"
        expect(claim_seconds(key)).to be_between(1798, 1800)
        expect(Rails.cache.read("trial_welcome:consumed:#{jti}")).to be_nil
      end
    end

    it 'PG welcome claim error prevents sign-in and never uses Redis' do
      phoenix_state!
      signed = issue_welcome_token(user)
      count = user.reload.sign_in_count
      expect(Rails.cache).not_to receive(:write)
      connection = ActiveRecord::Base.connection
      connection.execute('ALTER TABLE phoenix.once_claims RENAME COLUMN expires_at TO unavailable')
      expect do
        connection.transaction(requires_new: true) { get '/trial/welcome', params: { token: signed } }
      end.to raise_error(ActiveRecord::StatementInvalid)
      expect(user.reload.sign_in_count).to eq(count)
    end
  end
end
