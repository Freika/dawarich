# frozen_string_literal: true

require 'rails_helper'
require 'aws-sdk-s3'

RSpec.describe 'Phoenix wave 2 fixtures' do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to(Time.utc(2026, 3, 29, 1, 30)) { example.run }
  end

  it 'pins rendered wave-2 mail in every supported locale' do
    verify_fixture('mail.json', mail_fixture)
  end

  it 'pins point rows, Rails column order, and export payloads' do
    verify_fixture('points.json', points_fixture)
  end

  it 'pins S3 addressing and Active Storage content dispositions' do
    verify_fixture('storage.json', storage_fixture)
  end

  it 'pins archival warning cutoffs across calendar boundaries' do
    verify_fixture('archival_cutoffs.json', archival_cutoffs_fixture)
  end

  it 'pins every wave-2 producer payload' do
    verify_fixture('payloads.json', payloads_fixture)
  end

  private

  def fixture_dir
    Rails.root.join('app-phoenix/test/fixtures/wave2')
  end

  def locales
    %w[en de es fr pl ca zh]
  end

  def verify_fixture(filename, structure)
    path = fixture_dir.join(filename)
    json = JSON.pretty_generate(structure)

    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(fixture_dir)
      File.write(path, "#{json}\n")
    else
      expect(JSON.parse(path.read)).to eq(JSON.parse(json))
    end
  end

  def mail_fixture
    stub_const('MANAGER_URL', 'https://manager.example.test')
    user = create(:user, email: 'wave2-user@example.test')
    inviter = create(:user, email: 'wave2-inviter@example.test', settings: { 'locale' => 'de' })
    recipient = create(:user, email: 'wave2-recipient@example.test')
    family = create(:family, creator: inviter, name: 'Wave Two Family')
    invitation = create(:family_invitation, family: family, invited_by: inviter, email: recipient.email,
                                             token: 'wave2-fixed-invitation-token')
    link_url = 'https://dawarich.example.test/auth/account_links/confirm?token=wave2-link-token'
    urls = Rails.application.routes.url_helpers
    accept_url = urls.family_invitation_url(invitation.token, **ActionMailer::Base.default_url_options)

    surfaces = {
      'welcome' => [true, -> { UsersMailer.with(user: user).welcome }],
      'archival_approaching' => [false, -> { UsersMailer.with(user: user).archival_approaching }],
      'oauth_account_link' => [true, lambda {
        UsersMailer.with(user: user, provider_label: 'Google', link_url: link_url).oauth_account_link
      }],
      'account_destroy_confirmation' => [true, lambda {
        UsersMailer.with(user: user, link_url: link_url).account_destroy_confirmation
      }],
      'family_invitation' => [true, -> { FamilyMailer.invitation(invitation) }],
      'family_lapse' => [true, -> { FamilyMailer.plan_lapsed(user, family) }],
      'family_lapse_cloud' => [false, -> { FamilyMailer.plan_lapsed(user, family) }]
    }

    {
      'inputs' => {
        'job_locale' => 'en',
        'user_email' => user.email,
        'recipient_email' => recipient.email,
        'recipient_settings' => locales.index_with { |locale| { 'locale' => locale } },
        'inviter_email' => inviter.email,
        'inviter_settings' => inviter.settings,
        'family_name' => family.name,
        'owner_email' => family.owner.email,
        'invitation_token' => invitation.token,
        'accept_url_base' => accept_url.delete_suffix(urls.family_invitation_path(invitation.token)),
        'provider_label' => 'Google',
        'link_url' => link_url,
        'manager_url' => MANAGER_URL,
        'self_hosted' => surfaces.transform_values(&:first)
      },
      'messages' => surfaces.transform_values do |(self_hosted, build)|
        allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
        locales.index_with do |locale|
          [user, recipient].each { |person| person.update_columns(settings: { 'locale' => locale }) }
          I18n.with_locale(:en) { encoded_mail(build.call) }
        end
      end
    }
  end

  def encoded_mail(message)
    {
      'subject' => message.subject,
      'text' => message.text_part&.body&.decoded || message.body.decoded,
      'html' => message.html_part&.body&.decoded || ''
    }.transform_values { |value| value.gsub(/token=[^&\s"<]+/, 'token={{token}}') }
  end

  def points_fixture
    user = create(:user, id: 42, email: 'wave2-points@example.test')
    sources = [
      PointSource.create!(id: 101, digest: 'a' * 32, tracker_id: 'wave-phone', topic: 'owntracks/wave',
                          ssid: 'wave-wifi', bssid: 'aa:bb:cc:dd:ee:ff', connection: :wifi, trigger: :manual_event,
                          battery_status: :charging, inrids: %w[a b], in_regions: ['home']),
      PointSource.create!(id: 102, digest: 'b' * 32, tracker_id: 'wave-watch', topic: 'watch/wave', ssid: nil,
                          bssid: nil, connection: :mobile, trigger: :timer_based_event,
                          battery_status: :full, inrids: [], in_regions: [])
    ]
    points = build_points(user, sources)
    range = points.map(&:timestamp).min..points.map(&:timestamp).max

    payloads = %w[Europe/Berlin Etc/UTC America/St_Johns].index_with do |zone|
      Time.use_zone(zone) do
        geojson = Exports::PointGeojsonSerializer.new(ties_by_id(user.points.where(timestamp: range))).call
        gpx = Exports::PointGpxSerializer.new(ties_by_id(user.points.where(timestamp: range)), 'wave2 export').call
        { 'geojson' => geojson.read, 'gpx' => gpx.read }
      ensure
        geojson&.close!
        gpx&.close!
      end
    end

    {
      'points_column_order' => Point.column_names,
      'point_sources' => sources.map { |source| source.attributes.slice(*PointSource.column_names) },
      'points' => points.sort_by(&:id).map { |point| point.attributes.slice(*Point.column_names) },
      'exports' => payloads
    }
  end

  def ties_by_id(scope)
    allow(scope).to receive(:in_batches).and_wrap_original do |original, **options, &block|
      original.call(**options) { |batch| block.call(batch.order(:timestamp, :id)) }
    end
    scope
  end

  def build_points(user, sources)
    base = 1_774_748_800
    geodata = {
      'nested' => { 'float' => 1.2345678901234567, 'big' => 9_007_199_254_740_993 },
      'text' => "<&> \"\\\u0001"
    }
    points = 20.times.map do |index|
      create(:point, id: index + 1, user: user, timestamp: base + index,
                     lonlat: "POINT(0.000#{50 + index} #{50 + index}.0)",
                     altitude: index.even? ? 123.45 : nil, velocity: ['12.5 km/h', '0', '', nil][index % 4],
                     course: index.even? ? 12.34567 : nil, battery_status: index % 6,
                     trigger: index % 8, connection: [0, 1, 2, 4][index % 4], mode: index,
                     inrids: %w[a b], in_regions: ['home'], geodata: geodata,
                     source_id: index < 8 ? sources[index % 2].id : nil)
    end
    points.first.update_columns(altitude_decimal: 123.45, altitude: 123)
    points[1].update_columns(source_id: 99_999)
    points.concat([998, 999, 1000, 1001, 1002, 1003].map do |id|
      Point.create!(id: id, user: user, timestamp: base + 10_000, lonlat: "POINT(#{id / 10_000.0} 51.0)", altitude: nil,
                    velocity: '0', mode: 99, inrids: [], in_regions: [], geodata: {})
    end)
    points.each(&:reload)
  end

  def storage_fixture
    endpoints = ['https://s3.example.test', 'http://minio:9000', 'http://10.0.0.5:9000']
    buckets = %w[dawarich my.bucket Bad_Bucket]
    regions = %w[eu-central-1 us-east-1]
    addresses = regions.product(endpoints, buckets).map do |region, endpoint, bucket|
      client = Aws::S3::Client.new(region: region, endpoint: endpoint, force_path_style: false,
                                   credentials: Aws::Credentials.new('key', 'secret'))
      url = Aws::S3::Presigner.new(client: client).presigned_url(:put_object, bucket: bucket, key: 'abc')
      uri = URI.parse(url)
      { 'region' => region, 'endpoint' => endpoint, 'bucket' => bucket, 'host' => uri.host, 'path' => uri.path }
    end
    filenames = ['report.zip', 'report name.zip', ' leading.zip', '100%.zip', 'semi;colon.zip', 'slash/name.zip',
                 'quote"name.zip', 'apostrophe\'name.zip', 'two  spaces.zip', 'brackets[1].zip']
    service = ActiveStorage::Service.new
    {
      'addresses' => addresses,
      'content_dispositions' => filenames.index_with do |name|
        service.send(:content_disposition_with, type: 'attachment', filename: ActiveStorage::Filename.new(name))
      end
    }
  end

  def archival_cutoffs_fixture
    instants = [
      Time.utc(2024, 1, 31, 23, 30), Time.utc(2024, 2, 29, 1, 30), Time.utc(2024, 3, 31, 0, 30),
      Time.utc(2024, 10, 27, 0, 30), Time.utc(2025, 2, 28, 23, 30), Time.utc(2025, 3, 30, 1, 30),
      Time.utc(2025, 10, 26, 1, 30), Time.utc(2026, 3, 29, 1, 30)
    ]
    %w[Europe/Berlin Etc/UTC].index_with do |zone|
      instants.index_with do |instant|
        Time.use_zone(zone) do
          Lite::ArchivalWarningJob::THRESHOLDS.map do |threshold|
            threshold[:duration].ago(instant.in_time_zone).to_i
          end
        end
      end
    end
  end

  def payloads_fixture
    token = JWT.encode({ 'exp' => 1_774_747_000, 'jti' => '11111111-1111-4111-8111-111111111111' }, 'fixture', 'HS256')
    link_url = "https://dawarich.example.test/auth?token=#{token}"
    user = create(:user, id: 42, email: 'wave2-payload@example.test')
    I18n.with_locale(:de) do
      {
        'exports.points' => { 'export_id' => 11, 'user_id' => user.id },
        'mail.family_invitation' => { 'invitation_id' => 12, 'locale' => 'de' },
        'mail.family_lapse' => {
          'user_id' => user.id, 'family_id' => 13, 'locale' => 'de', 'lapse_at' => '2026-03-29T01:30:00Z'
        },
        'mail.user.welcome' => UserMailCommands.payload('welcome', user.id, {}),
        'mail.user.archival_approaching' => UserMailCommands.payload('archival_approaching', user.id,
                                                                     epoch: '2026-03-29T01:30:00Z'),
        'mail.user.oauth_account_link' => UserMailCommands.payload('oauth_account_link', user.id,
                                                                   provider_label: 'Google', link_url:),
        'mail.user.account_destroy_confirmation' => UserMailCommands.payload('account_destroy_confirmation', user.id,
                                                                             link_url:)
      }
    end
  end
end
