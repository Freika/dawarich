# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: trial checkout and home responses', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/trial_home') }
  let(:now) { Time.utc(2026, 10, 3, 10) }
  let(:jti) { '00000000-0000-4000-8000-000000010001' }
  let(:signing_phrase) { 'a10-checkout-synthetic-signing-phrase-not-for-production' }

  around do |example|
    saved = ENV['JWT_SECRET_KEY']
    ENV['JWT_SECRET_KEY'] = signing_phrase
    ActionController::Base.allow_forgery_protection = true
    travel_to(now) { example.run }
  ensure
    ENV['JWT_SECRET_KEY'] = saved
    ActionController::Base.allow_forgery_protection = false
  end

  before do
    allow(ENV).to receive(:fetch).with('JWT_SECRET_KEY').and_return(signing_phrase)
    FileUtils.mkdir_p(dir)
    stub_const('MANAGER_URL', 'https://manager.example.test')
    allow(SecureRandom).to receive(:uuid).and_return(jti)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
  end

  def actor
    user = create(:user, id: 10_001, email: 'a10-checkout@example.invalid', password: 'a10-synthetic-password',
                         skip_auto_trial: true, changelog_consent: :declined, created_at: now, updated_at: now)
    user.update_columns(settings: { 'timezone' => 'Europe/Berlin', 'onboarding_completed' => true },
                        theme: 'dark', api_key: 'a10-k-10001')
    user.reload
  end

  def user_row(user)
    { 'id' => user.id, 'email' => user.email, 'theme' => user.theme, 'admin' => user.admin,
      'settings' => user.settings, 'status' => User.statuses.fetch(user.status),
      'plan' => User.plans.fetch(user.plan), 'active_until' => user.active_until.utc.iso8601(6),
      'changelog_consent' => User.changelog_consents.fetch(user.changelog_consent) }
  end

  def capture(name, user, path, params: {})
    reset!
    sign_in user if user
    get(path, params:)
    { 'name' => name, 'path' => path, 'query' => params.except(:token).stringify_keys,
      'now' => now.iso8601, 'self_hosted' => DawarichSettings.self_hosted?, 'status' => response.status,
      'user' => user && user_row(user), 'html' => '',
      'headers' => response.headers.slice('Location', 'Cache-Control', 'Pragma', 'Referrer-Policy',
                                          'Content-Type', 'X-Frame-Options', 'X-Content-Type-Options'),
      'flash' => flash.to_hash.slice('alert', 'notice') }
  end

  def jwt_projection(token, user, **options)
    parts = token.split('.')
    expect(parts.length).to eq(3)
    header_json = Base64.urlsafe_decode64(parts[0])
    payload_json = Base64.urlsafe_decode64(parts[1])
    payload, header = JWT.decode(token, signing_phrase, true, algorithm: 'HS256')
    expect(header).to eq('alg' => 'HS256')
    expected_keys = %w[user_id email purpose jti exp] + options.select { |_, value| value.present? }.keys.map(&:to_s)
    expect(payload.keys).to eq(expected_keys)
    expect(payload.slice(*options.keys.map(&:to_s))).to eq(options.select { |_, value| value.present? }.stringify_keys)
    expect(token).to eq(user.generate_subscription_token(**options))
    signature = Base64.urlsafe_decode64(parts[2])
    expect(signature).to eq(OpenSSL::HMAC.digest('SHA256', signing_phrase, parts[0..1].join('.')))
    { 'header' => header, 'header_json' => header_json, 'payload' => payload,
      'payload_json' => payload_json, 'signature_hex' => signature.unpack1('H*') }
  end

  def trial_cases
    user = actor
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    upgrades = [['upgrade_pro_annual', { plan: 'pro', interval: 'annual' }, { plan: 'pro', interval: 'annual' }],
                ['upgrade_lite_monthly', { plan: 'lite', interval: 'monthly' }, { plan: 'lite', interval: 'monthly' }],
                ['upgrade_invalid', { plan: 'enterprise', interval: 'weekly' }, {}],
                ['upgrade_array', { plan: ['pro'], interval: ['annual'] }, {}]]
    results = upgrades.map do |name, params, options|
      captured = capture(name, user, '/trial/upgrade', params:)
      token = CGI.parse(URI(response.location).query).fetch('token').first
      captured['jwt'] = jwt_projection(token, user, **options)
      captured['headers']['Location'] = 'https://manager.example.test/auth/dawarich?token=TOKEN'
      captured
    end
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    results << capture('upgrade_self_hosted', user, '/trial/upgrade')
    [[false, 'cloud'], [true, 'self_hosted']].each do |self_hosted, mode|
      allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
      user.update_columns(status: User.statuses.fetch('pending_payment'))
      user.reload
      captured = capture("resume_#{mode}_pending", user, '/trial/resume')
      doc = Nokogiri::HTML5(response.body)
      hero = doc.at_css('.hero')
      link = hero.at_css('a[href^="https://manager.example.test/checkout"]')
      token = CGI.parse(URI(link['href']).query).fetch('token').first
      captured['jwt'] = jwt_projection(token, user, variant: 'reverse_trial')
      link['href'] = 'https://manager.example.test/checkout?token=TOKEN'
      captured['html'] = hero.to_html
      captured['title'] = doc.at_css('title').text
      results << captured
    end
    user.update_columns(status: User.statuses.fetch('active'))
    user.reload
    [[false, 'cloud'], [true, 'self_hosted']].each do |self_hosted, mode|
      allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
      results << capture("resume_#{mode}_active", user, '/trial/resume')
    end
    results << capture('resume_guest', nil, '/trial/resume')
    results
  end

  def home_cases
    user = actor
    results = [capture('home_signed_in', user, '/')]
    expect(response.body).to eq('')
    [true, false].each do |enabled|
      Rails.cache.clear
      Rails.cache.write('dawarich/registration_enabled', enabled)
      name = enabled ? 'home_registration_enabled' : 'home_registration_disabled'
      captured = capture(name, nil, '/')
      doc = Nokogiri::HTML5(response.body)
      captured['registration_link'] = doc.at_css('a[href="/users/sign_up"]').present?
      captured['sign_in_link'] = doc.at_css('a[href="/users/sign_in"]').present?
      results << captured
    end
    results << capture('welcome_invalid', nil, '/trial/welcome', params: { token: 'invalid-synthetic' })
    results
  end

  def save_capture(capture)
    expect(Oj.dump(capture.except('html'), mode: :strict)).not_to include(signing_phrase)
    name = capture.fetch('name')
    html = capture.fetch('html').gsub(/[ \t]+$/, '').rstrip
    File.write(dir.join("#{name}.html"), html.empty? ? '' : "#{html}\n")
    File.write(dir.join("#{name}.json"),
               "#{Oj.dump(capture.except('html'), mode: :strict, float_precision: 0, indent: 2).rstrip}\n")
  end

  it 'writes sanitized trial claims and resume header cases' do
    cases = trial_cases
    expect(cases.map { |capture| capture.fetch('name') })
      .to eq(%w[upgrade_pro_annual upgrade_lite_monthly upgrade_invalid upgrade_array upgrade_self_hosted
                resume_cloud_pending resume_self_hosted_pending resume_cloud_active resume_self_hosted_active
                resume_guest])
    cases.each do |capture|
      if capture.fetch('name').start_with?('resume')
        expected_cache = capture.fetch('name') == 'resume_guest' ? 'no-cache' : 'no-store'
        expect(capture.dig('headers', 'Cache-Control')).to eq(expected_cache)
        expected_pragma = capture.fetch('name') == 'resume_guest' ? nil : 'no-cache'
        expect(capture.dig('headers', 'Pragma')).to eq(expected_pragma)
      end
      if capture['jwt']
        payload = capture.fetch('jwt').fetch('payload')
        expect(payload.slice('user_id', 'email', 'purpose', 'jti', 'exp'))
          .to eq('user_id' => 10_001, 'email' => 'a10-checkout@example.invalid', 'purpose' => 'checkout',
                 'jti' => jti, 'exp' => now.to_i + 1800)
        if capture['name'].include?('resume')
          expect(payload.fetch('variant')).to eq('reverse_trial')
        elsif capture['name'].include?('invalid') || capture['name'].include?('array')
          expect(payload.keys).to eq(%w[user_id email purpose jti exp])
        end
      end
      expect(capture.fetch('html', '')).not_to match(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/)
      save_capture(capture)
    end
  end

  it 'writes home redirect and Rails fallback controls' do
    cases = home_cases
    expect(cases.map { |capture| capture.fetch('name') })
      .to eq(%w[home_signed_in home_registration_enabled home_registration_disabled welcome_invalid])
    signed_in = cases.first
    expect(signed_in.fetch('status')).to eq(302)
    expect(signed_in.dig('headers', 'Location')).to eq('http://www.example.com/map/v2')
    expect(signed_in.fetch('html')).to eq('')
    expect(signed_in.dig('headers', 'Cache-Control')).to eq('no-cache')
    expect(cases[1].fetch('registration_link')).to be(true)
    expect(cases[2].fetch('registration_link')).to be(false)
    expect(cases.last.dig('headers', 'Cache-Control')).to eq('no-store')
    expect(cases.last.dig('headers', 'Referrer-Policy')).to eq('no-referrer')
    cases.each { |capture| save_capture(capture) }
  end

  it 'characterizes residual entitlement boundaries and marker session writes' do
    user = actor
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    %w[pending_payment trial active inactive].each do |status|
      %w[lite pro family].each do |plan|
        [now - 1.second, now, now + 1.second].each do |expires|
          user.update_columns(status: User.statuses.fetch(status), plan: User.plans.fetch(plan), active_until: expires)
          captured = capture('residual', user.reload, '/trial/resume', params: { client: 'ios', aff: 'partner' })
          expect(captured.fetch('status')).to eq(status == 'pending_payment' ? 200 : 302)
          expect(response.headers).to include('Cache-Control' => 'no-store', 'Pragma' => 'no-cache')
          expect(request.session[:dawarich_client]).to eq('ios')
          expect(request.session[:partnero_referral]).to eq('partner')
          expect(response.location).to eq('http://www.example.com/') unless status == 'pending_payment'
        end
      end
    end
    user.update_columns(status: User.statuses.fetch('pending_payment'))
    reset!
    sign_in user.reload
    head '/trial/resume'
    expect(response.status).to eq(200)
    expect(response.body).to eq('')
    expect(response.headers).to include('Cache-Control' => 'no-store', 'Pragma' => 'no-cache')
    ENV.delete('JWT_SECRET_KEY')
    allow(ENV).to receive(:fetch).with('JWT_SECRET_KEY').and_call_original
    expect { get '/trial/upgrade' }.to raise_error(KeyError)
  end
end
