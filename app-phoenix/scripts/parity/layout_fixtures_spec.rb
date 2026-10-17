# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixtures: the application layout as Rails renders it', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/layout') }
  let(:now) { Time.utc(2026, 9, 26, 12, 0, 0) }
  let(:header_names) do
    %w[x-frame-options x-xss-protection x-content-type-options x-permitted-cross-domain-policies referrer-policy]
  end

  def capture(name, path, state, headers = {}, head: true)
    reset! if state[:user].nil?
    I18n.locale = :en
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML5(response.body)
    content = doc.at_css('body > div.container > div.w-full > div.flex')
    raise "#{path} does not render layouts/application" unless content

    content.children.remove
    scrub!(doc)
    assert_safe!(doc)
    FixtureRecording.verify(dir.join("#{name}.html"), doc.at_css('body').to_html.gsub(/[ \t]+\n/, "\n"))
    FixtureRecording.verify(dir.join("#{name}.head.html"), doc.at_css('head').to_html.gsub(/[ \t]+\n/, "\n")) if head
    meta = {
      state: state.merge(path:),
      html: doc.at_css('html').attributes.transform_values(&:value),
      headers: header_names.index_with { |header| response.headers[header] }
    }
    FixtureRecording.verify(dir.join("#{name}.json"), "#{JSON.pretty_generate(meta)}\n")
  end

  def scrub!(doc)
    doc.css('[signed-stream-name]').each { |node| node['signed-stream-name'] = 'SIGNED' }
    doc.css('meta[name="csrf-token"]').each { |node| node['content'] = 'CSRF' }

    doc.css('a[href]').each do |node|
      uri = URI.parse(node['href'])
      next unless uri.path == '/auth/dawarich'

      node['href'] = node['href'].sub(/([?&]token=)[^&]+/, '\\1REDACTED')
    rescue URI::InvalidURIError
      next
    end
  end

  def assert_safe!(doc)
    html = doc.to_html
    raise 'fixture contains a JWT-shaped value' if html.match?(/eyJ[A-Za-z0-9_-]+\./)
    raise 'fixture contains an unsigned stream name' if html.match?(/signed-stream-name="(?!SIGNED")/)
  end

  def navbar_state(user, **extra)
    user.reload
    raise "#{user.email} carries a factory API key" unless user.api_key.match?(/\Aa51b-k-\d{4}\z/)

    membership = user.family_membership
    creator = membership&.family&.creator
    { user: { id: user.id, email: user.email, api_key: user.api_key, theme: user.theme, settings: user.settings,
              admin: user.admin,
              status: User.statuses[user.status], plan: User.plans[user.plan],
              active_until: user.active_until&.utc&.iso8601(6),
              subscription_source: User.subscription_sources[user.subscription_source],
              changelog_consent: User.changelog_consents[user.changelog_consent] },
      notifications: user.notifications.order(:id).map do |n|
        { id: n.id, title: n.title, kind: Notification.kinds[n.kind], read: n.read_at.present?,
          created_at: n.created_at.utc.iso8601(6) }
      end,
      imports: user.imports.order(:id).map { |import| { id: import.id, name: import.name, demo: import.demo } },
      family: membership && { id: membership.family_id, role: Family::Membership.roles[membership.role],
                              access_until: membership.family.access_until&.utc&.iso8601(6),
                              creator: creator && creator_fixture(creator) } }.merge(extra)
  end

  def creator_fixture(creator)
    { id: creator.id, email: creator.email, plan: User.plans[creator.plan],
      active_until: creator.active_until&.utc&.iso8601(6) }
  end

  def navbar_user(email, **columns)
    user = create(:user, id: Zlib.crc32(email), email:)
    user.update_columns({ changelog_consent: User.changelog_consents[:declined],
                          settings: user.settings.merge('onboarding_completed' => true),
                          api_key: format('a51b-k-%04d', Zlib.crc32(email) % 10_000) }.merge(columns))
    user
  end

  def shot(name, user, path = '/notifications', **extra)
    reset!
    sign_in user
    capture(name, path, navbar_state(user, accept_language: nil, **extra), {}, head: false)
    sign_out user
    original = user.settings
    (%w[en de es fr pl ca zh] - [name.split('_').last]).each do |locale|
      user.update_columns(settings: original.merge('locale' => locale))
      reset!
      sign_in user
      capture(name.sub(/_(en|de)$/) { "_#{Regexp.last_match(1)}_#{locale}" }, path,
              navbar_state(user, accept_language: nil, **extra), {}, head: false)
      sign_out user
    end
    user.update_columns(settings: original)
  end

  before { FileUtils.mkdir_p(dir) }

  it 'rejects a fixture containing a JWT-shaped value and unsigned stream name' do
    doc = Nokogiri::HTML5.fragment(
      '<turbo-cable-stream-source signed-stream-name="not-signed">' \
      'eyJhbGciOiJIUzI1NiJ9.payload</turbo-cable-stream-source>'
    )

    expect { assert_safe!(doc) }.to raise_error(RuntimeError, 'fixture contains a JWT-shaped value')
  end

  it 'writes the layout for each state' do
    travel_to now do
      capture('signed_out_en', '/users/sign_in', { user: nil, self_hosted: true, accept_language: nil })
      %w[de es fr pl ca zh].each do |locale|
        capture("signed_out_#{locale}", "/users/sign_in?locale=#{locale}",
                { user: nil, self_hosted: true, accept_language: nil, locale: })
      end
      capture('signed_out_de_suggested', '/users/sign_in',
              { user: nil, self_hosted: true, accept_language: 'de-DE,de;q=0.9' },
              { 'Accept-Language' => 'de-DE,de;q=0.9' })

      %w[es fr pl ca zh].each do |locale|
        language = "#{locale};q=0.9"
        capture("signed_out_#{locale}_suggested", '/users/sign_in',
                { user: nil, self_hosted: true, accept_language: language }, { 'Accept-Language' => language })
      end

      dark = navbar_user('layout-dark@dawarich.test', theme: 'dark')
      reset!
      sign_in dark
      capture('self_hosted_dark_en', '/notifications', navbar_state(dark, self_hosted: true, accept_language: nil))
      sign_out dark
      %w[de es fr pl ca zh].each do |locale|
        dark.update_columns(settings: dark.settings.merge('locale' => locale))
        reset!
        sign_in dark
        capture("self_hosted_dark_#{locale}", '/notifications',
                navbar_state(dark, self_hosted: true, accept_language: nil))
        sign_out dark
      end

      light = navbar_user('layout-light@dawarich.test', theme: 'light')
      light.update_columns(settings: light.settings.merge('locale' => 'de'))
      reset!
      sign_in light
      capture('self_hosted_light_de', '/notifications', navbar_state(light, self_hosted: true, accept_language: nil))
      sign_out light
      %w[en es fr pl ca zh].each do |locale|
        light.update_columns(settings: light.settings.merge('locale' => locale))
        reset!
        sign_in light
        capture("self_hosted_light_#{locale}", '/notifications',
                navbar_state(light, self_hosted: true, accept_language: nil))
        sign_out light
      end

      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      stub_const('SELF_HOSTED', false)
      cloud = navbar_user('layout-cloud@dawarich.test')
      reset!
      sign_in cloud
      capture('cloud_en', '/notifications', navbar_state(cloud, self_hosted: false, accept_language: nil))
      sign_out cloud
      %w[de es fr pl ca zh].each do |locale|
        cloud.update_columns(settings: cloud.settings.merge('locale' => locale))
        reset!
        sign_in cloud
        capture("cloud_#{locale}", '/notifications', navbar_state(cloud, self_hosted: false, accept_language: nil))
        sign_out cloud
      end
    end

    flashes = %w[notice success alert error warning info].flat_map do |type|
      %w[en de es fr pl ca zh].map do |locale|
        html = I18n.with_locale(locale) do
          ApplicationController.render(partial: 'shared/flash_message',
                                       locals: { type: type, message: 'Gespeichert & <b>ok</b>' })
        end
        { type: type, locale: locale, html: html }
      end
    end
    FixtureRecording.verify(dir.join('flash_messages.json'), "#{JSON.pretty_generate(flashes)}\n")
  end

  it 'writes the navbar states' do
    travel_to now do
      %w[es fr pl ca zh].each do |locale|
        capture("navbar_signed_out_#{locale}", "/users/sign_in?locale=#{locale}",
                { user: nil, self_hosted: true, accept_language: nil, locale: }, {}, head: false)
      end
      capture('navbar_signed_out_de', '/users/sign_in?locale=de',
              { user: nil, self_hosted: true, accept_language: nil, locale: 'de' }, {}, head: false)

      admin = navbar_user('navbar-admin@dawarich.test', admin: true)
      admin.update_columns(settings: admin.settings.merge('supporter_email' => 'navbar-supporter@dawarich.test'))
      allow_any_instance_of(User).to receive(:supporter?).and_return(true)
      shot('navbar_admin_supporter_en', admin, self_hosted: true, supporter: true)
      allow_any_instance_of(User).to receive(:supporter?).and_call_original

      reader = navbar_user('navbar-reader@dawarich.test', changelog_consent: User.changelog_consents[:granted])
      1.upto(13) do |n|
        reader.notifications.create!(id: 2_000_000 + n, title: "Navbar #{n}", content: 'x', kind: n % 3,
                                     read_at: n == 13 ? now : nil, created_at: now - n.minutes)
      end
      shot('navbar_unread_12_en', reader, self_hosted: true)

      flood = navbar_user('navbar-flood@dawarich.test', settings: {})
      Notification.insert_all(Array.new(120) do |i|
        { id: 3_000_000 + i, user_id: flood.id, title: "Flood #{i}", content: 'x', kind: 0, created_at: now - i.minutes,
       updated_at: now }
      end)
      shot('navbar_unread_120_onboarding_en', flood, self_hosted: true)

      owner = navbar_user('navbar-owner@dawarich.test')
      family = Family.create!(id: 1_000_001, name: 'Navbar', creator: owner)
      Family::Membership.create!(family:, user: owner, role: :owner)
      member = navbar_user('navbar-member@dawarich.test')
      Family::Membership.create!(family:, user: member, role: :member)
      member.update_columns(settings: member.settings.merge('locale' => 'de',
                                                            'family' => { 'location_sharing' => { 'enabled' => true,
'expires_at' => (now + 1.day).iso8601 } }))
      shot('navbar_family_sharing_de', member, self_hosted: true)
      shot('navbar_family_owner_en', owner, self_hosted: true)
      shot('navbar_active_stats_en', navbar_user('navbar-stats@dawarich.test'), '/stats', self_hosted: true)

      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      stub_const('SELF_HOSTED', false)
      stub_const('MANAGER_URL', 'https://manager.dawarich.test')
      cloud = { self_hosted: false, manager_url: 'https://manager.dawarich.test' }
      shot('navbar_cloud_trial_en', navbar_user('navbar-trial@dawarich.test', status: 2, active_until: now + 5.days),
           **cloud)
      trial_de = navbar_user('navbar-trial-de@dawarich.test', status: 2, active_until: now + 2.days)
      trial_de.update_columns(settings: trial_de.settings.merge('locale' => 'de'))
      shot('navbar_cloud_trial_de', trial_de, **cloud)
      imports_user = navbar_user('navbar-onboarding-imports@dawarich.test', status: 2, active_until: now + 5.days,
                                                                             settings: {})
      Import.insert_all([{ id: 4_000_001, user_id: imports_user.id, name: 'Onboarding one', demo: false,
                           created_at: now, updated_at: now },
                         { id: 4_000_002, user_id: imports_user.id, name: 'Onboarding demo', demo: true,
                           created_at: now, updated_at: now }])
      shot('navbar_onboarding_trial_imports_en', imports_user, **cloud)
      shot('navbar_onboarding_trial_store_en',
           navbar_user('navbar-onboarding-store@dawarich.test', status: 2, active_until: now + 5.days,
                                                                 subscription_source: 1), **cloud)
      shot('navbar_cloud_pending_en', navbar_user('navbar-pending@dawarich.test', status: 3, active_until: nil),
           **cloud)
      shot('navbar_cloud_expired_en',
           navbar_user('navbar-expired@dawarich.test', status: 1, active_until: now - 3.days), **cloud)
      shot('navbar_cloud_family_plan_en',
           navbar_user('navbar-family-plan@dawarich.test', status: 1, plan: 2, active_until: now + 300.days), **cloud)
      lapsed_owner = navbar_user('navbar-lapsed-owner@dawarich.test', status: 1, plan: 1, active_until: now + 300.days)
      lapsed_family = Family.create!(id: 1_000_002, name: 'Lapsed', creator: lapsed_owner)
      Family::Membership.create!(family: lapsed_family, user: lapsed_owner, role: :owner)
      lapsed = navbar_user('navbar-lapsed@dawarich.test', status: 1, active_until: now + 300.days)
      Family::Membership.create!(family: lapsed_family, user: lapsed, role: :member)
      shot('navbar_cloud_lapsed_member_en', lapsed, **cloud)
    end
  end

  it 'writes the subscription token Rails generates for fixed inputs' do
    secret = 'phoenix-a5-jwt-fixture-secret-not-for-production'
    user = create(:user, id: 1, email: 'token@dawarich.test')
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('JWT_SECRET_KEY').and_return(secret)
    allow(SecureRandom).to receive(:uuid).and_return('00000000-0000-4000-8000-000000000000')
    header, payload, signature = travel_to(now) { user.generate_subscription_token }.split('.')
    decode = ->(part) { Base64.urlsafe_decode64(part + ('=' * ((4 - (part.length % 4)) % 4))) }

    FixtureRecording.verify(dir.join('../subscription_token.json'), "#{JSON.pretty_generate(
      secret:, user_id: user.id, email: user.email, now: now.to_i, jti: '00000000-0000-4000-8000-000000000000',
      header: decode.call(header), payload: decode.call(payload), signature: decode.call(signature).unpack1('H*')
    )}\n")
  end

  it 'writes the size-3 QR codes the onboarding modal renders' do
    corpus = [['http://www.example.com/', 'a51b-k-0001'], ['https://a.test:8443/?a=1&b=<2>', 'a51b-k-0002']]
             .map do |url, key|
      { root_url: url, api_key: key,
        svg: ResponsiveQrSvg.call({ 'server_url' => url, 'api_key' => key }.to_json, size: 3) }
    end

    FixtureRecording.verify(dir.join('../onboarding_qr.json'), "#{JSON.pretty_generate(corpus)}\n")
  end
end
