# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: public achievement cards and retained routes', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/achievement_public') }
  let(:now) { Time.utc(2026, 10, 4, 10) }

  around do |example|
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    travel_to(now) { example.run }
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

  def synthetic_user(id, locale: 'en', admin: false)
    create(:user, id:, email: "a10c-public-#{id}@example.invalid", password: 'a10c-synthetic-password', admin:,
                  settings: { 'locale' => locale, 'timezone' => 'Europe/Berlin', 'onboarding_completed' => true })
  end

  def seed_owner(id, locale: 'en', key: 'country_de', state: nil)
    owner = synthetic_user(id, locale:)
    state ||= { 'earned' => { 'DE-BY' => now.iso8601 } }
    exploration = create(:achievement_progress, id: id * 10 + 1, user: owner,
                                               achievement_key: 'exploration', state:)
    carrier = create(:achievement_progress, id: id * 10 + 2, user: owner, achievement_key: key,
                                           sharing_enabled: true,
                                           sharing_uuid: format('a10c0000-0000-4000-8000-%012d', id),
                                           created_at: now - 1.day, updated_at: now - 1.day)
    [owner, exploration, carrier]
  end

  def shapes
    Rails.cache.clear
    square = 'MULTIPOLYGON (((12.25 51.25,12.25 51.5,12.5 51.5,12.5 51.25,12.25 51.25)))'
    create(:country, id: 43_901, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU', geom: square)
    create(:country, id: 43_902, name: 'France', iso_a2: 'FR', iso_a3: 'FRA', geom: square)
    create(:region, id: 43_903, code: 'DE-BY', geom: square)
  end

  def response_row(name)
    headers = response.headers.slice('Content-Type', 'Cache-Control', 'Content-Security-Policy', 'X-Frame-Options')
    headers.transform_values! { |value| value.gsub(/nonce-[^'\s;]+/, 'nonce-REDACTED') }
    { 'name' => name, 'status' => response.status, 'location' => response.location,
      'headers' => headers,
      'flash' => flash.to_hash.stringify_keys, 'empty_body' => response.body.empty? }
  end

  def public_capture(name, carrier, owner:, viewer: nil, params: {}, method: :get)
    reset!
    sign_in viewer.reload if viewer
    path = shared_achievement_path(carrier.sharing_uuid)
    public_send(method, path, params: params)
    row = response_row(name).merge('path' => path, 'method' => method.to_s.upcase, 'params' => params,
                                   'owner_id' => owner.id, 'viewer_id' => viewer&.id)
    expect(response.headers['X-Frame-Options']).to be_nil
    expect(response.headers['Content-Security-Policy']).to eq('frame-ancestors *')
    return row unless response.status == 200 && method == :get

    html = response.body.gsub(/(<meta name="csrf-token" content=")[^"]*/, '\1CSRF')
    doc = Nokogiri::HTML5(html)
    expect(doc.at_css('html')['lang']).to eq(owner.locale.to_s)
    expect(doc.css('.ach-page .ach-card').size).to eq(1)
    expect(html).not_to include(owner.email, viewer&.email.to_s.presence || 'a10c-private-sentinel')
    expect(doc.css('[data-controller="achievement-unlocks"], .ach-child-grid')).to be_empty
    embed = params[:embed] == '1'
    expect(doc.at_css('header').present?).to eq(!embed)
    expect(doc.at_css('footer').present?).to eq(!embed)
    metadata = doc.css('meta[property^="og:"], meta[name^="twitter:"]').to_h do |node|
      [node['property'] || node['name'], node['content']]
    end
    expect(metadata.fetch('og:url')).to eq("http://www.example.com#{path}")
    expect(metadata.fetch('og:image')).to eq("http://www.example.com#{path}/og.png")
    expect(metadata.fetch('twitter:image')).to eq(metadata.fetch('og:image'))
    expect(metadata.slice('og:image:type', 'og:image:width', 'og:image:height'))
      .to eq('og:image:type' => 'image/png', 'og:image:width' => '1200', 'og:image:height' => '630')
    set = controller.view_assigns.fetch('set')
    expect(doc.at_css('.ach-page').text).to include("#{set.display_count}/#{set.target}")
    save_html(name, html)
    row.merge('lang' => doc.at_css('html')['lang'], 'title' => doc.at_css('title').text,
              'metadata' => metadata, 'chrome' => doc.at_css('header').present?, 'count' => set.earned_count,
              'target' => set.target, 'completed' => set.completed?, 'locked' => set.locked?,
              'html_file' => "#{name}.html")
  end

  def public_cases
    shapes
    rows = %w[en de es fr pl ca zh].each_with_index.flat_map do |locale, index|
      owner, exploration, carrier = seed_owner(43_001 + index, locale:)
      before = [owner.settings, exploration.state, carrier.attributes.slice('state', 'updated_at')]
      captured = [public_capture("#{locale}_direct", carrier, owner:, params: { locale: locale == 'en' ? 'de' : 'en' }),
                  public_capture("#{locale}_embed", carrier, owner:, params: { embed: '1' }),
                  public_capture("#{locale}_embed_other", carrier, owner:, params: { embed: 'true' }),
                  public_capture("#{locale}_head", carrier, owner:, method: :head)]
      expect(captured.map { |row| row['status'] }).to eq([200, 200, 200, 200])
      expect(captured.last['empty_body']).to be(true)
      expect([owner.reload.settings, exploration.reload.state, carrier.reload.attributes.slice('state', 'updated_at')])
        .to eq(before)
      captured
    end
    rows.concat(state_cases)
    rows.concat(availability_cases)
    rows
  end

  def state_cases
    complete = { 'earned' => Achievements::Registry.find('country_de').region_codes.index_with { now.iso8601 } }
    [[43_021, 'locked', 'country_de', { 'earned' => {} }],
     [43_022, 'completed', 'country_de', complete],
     [43_023, 'continent', 'continent_europe', { 'earned' => { 'DE' => now.iso8601 } }],
     [43_024, 'flat', 'country_fr', { 'earned' => { 'FR' => now.iso8601 } }]].map do |id, name, key, state|
      owner, exploration, carrier = seed_owner(id, key:, state:)
      row = public_capture(name, carrier, owner:)
      expect(exploration.reload.state).to eq(state)
      expect(row['locked']).to be(true) if name == 'locked'
      expect(row['completed']).to be(true) if %w[completed flat].include?(name)
      row
    end
  end

  def availability_cases
    owner, _exploration, carrier = seed_owner(43_031, locale: 'de')
    carrier.update!(sharing_enabled: false)
    disabled = public_capture('disabled', carrier, owner:, params: { locale: 'de' })
    carrier.update!(sharing_enabled: true, achievement_key: 'missing_definition')
    missing = public_capture('missing_definition', carrier, owner:, params: { locale: 'de' })
    carrier.update!(achievement_key: 'country_de')
    owner.mark_as_deleted!
    expect(carrier.reload.user).to be_nil
    deleted = public_capture('deleted_owner', carrier, owner:, params: { locale: 'de' })
    unknown = carrier.dup
    unknown.sharing_uuid = 'a10c0000-0000-4000-8000-000000099999'
    unknown_row = public_capture('unknown_uuid', unknown, owner:, params: { locale: 'de' })
    head_row = public_capture('unknown_head', unknown, owner:, params: { locale: 'de' }, method: :head)
    [disabled, missing, deleted, unknown_row, head_row].each do |row|
      expect(row['status']).to eq(302)
      expect(row['location']).to eq('http://www.example.com/')
      expect(row.dig('flash', 'alert')).to eq(I18n.t('achievements.public.not_found', locale: :de))
    end
  end

  def separate_owner_cases
    shapes
    first_owner, first_state, first_carrier = seed_owner(43_101, locale: 'de')
    complete = { 'earned' => Achievements::Registry.find('country_de').region_codes.index_with { now.iso8601 } }
    second_owner, second_state, second_carrier = seed_owner(43_102, state: complete)
    viewer = synthetic_user(43_103, locale: 'fr')
    viewer_state = create(:achievement_progress, id: 431_031, user: viewer, achievement_key: 'exploration', state: {})
    people = [first_owner, second_owner, viewer]
    states = [first_state, second_state, viewer_state]
    before = [people.map(&:settings), states.map(&:state)]
    first = public_capture('owner_first_guest', first_carrier, owner: first_owner)
    second = public_capture('owner_second_guest', second_carrier, owner: second_owner)
    first_view = public_capture('owner_first_viewer', first_carrier, owner: first_owner, viewer:)
    second_view = public_capture('owner_second_viewer', second_carrier, owner: second_owner, viewer:)
    shared_fields = %w[count target completed locked lang title metadata]
    same = first.slice(*shared_fields) == first_view.slice(*shared_fields) &&
           second.slice(*shared_fields) == second_view.slice(*shared_fields)
    expect([people.map { |person| person.reload.settings }, states.map { |state| state.reload.state }]).to eq(before)
    expect(first['title']).to eq('Germany-Entdecker — Dawarich')
    expect(second['title']).to eq('Germany Explorer — Dawarich')
    { 'first' => first, 'second' => second, 'viewer_first' => first_view, 'viewer_second' => second_view,
      'viewer_matches_owner' => same }
  end

  def login(actor)
    reset!
    sign_in actor.reload if actor
    get actor ? achievements_path : new_user_session_path, params: { locale: 'en' }
    expect(response.status).to eq(200)
    Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
  end

  def form_request(actor, method, path, params = {}, accept: 'text/html')
    token = login(actor)
    clear_enqueued_jobs
    public_send(method, path, params: URI.encode_www_form(params.merge(authenticity_token: token)),
                              headers: { 'Content-Type' => 'application/x-www-form-urlencoded', 'Accept' => accept })
    response_row(path).merge('jobs' => enqueued_jobs.map { |job| job.fetch(:job).name })
  end

  def png_cases(owner, carrier)
    reset!
    get shared_achievement_image_path(carrier.sharing_uuid)
    expect(response.status).to eq(200)
    expect(response.body.b).to start_with("\x89PNG\r\n\x1A\n".b)
    dimensions = response.body.byteslice(16, 8).unpack('NN')
    expect(dimensions).to eq([1200, 630])
    expect(response.headers['Cache-Control']).to include('private', 'no-store')
    row = response_row('png').merge('type' => response.media_type, 'dimensions' => dimensions)
    head shared_achievement_image_path(carrier.sharing_uuid)
    expect([response.status, response.body.empty?]).to eq([200, true])
    row['head'] = response_row('png_head')
    carrier.update!(sharing_enabled: false)
    get shared_achievement_image_path(carrier.sharing_uuid)
    expect(response.status).to eq(404)
    expect(response.headers['Cache-Control']).to include('private', 'no-store')
    row['disabled'] = response_row('png_disabled')
    owner.mark_as_deleted!
    row
  end

  def retained_cases
    shapes
    owner, _state, carrier = seed_owner(43_201)
    png = png_cases(owner, carrier)
    admin = synthetic_user(43_202, admin: true)
    actor = synthetic_user(43_203)
    exported = export_cases(actor)
    jobs = cloud_producer_cases(actor)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    { 'png' => png, 'export' => exported, 'cloud_producers' => jobs,
      'provider' => provider_cases(admin, actor), 'deletion' => deletion_cases(admin),
      'mounts' => mount_cases(admin, actor) }
  end

  def export_cases(actor)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    login(actor)
    clear_enqueued_jobs
    get export_settings_users_path
    expect(response).to redirect_to(exports_path)
    expect(enqueued_jobs).not_to be_empty
    row = response_row('nonadmin_cloud_export').merge('admin_only' => false,
                                                      'jobs' => enqueued_jobs.map { |job| job.fetch(:job).name })
    imported = form_request(actor, :post, import_settings_users_path)
    expect(response).to redirect_to(edit_user_registration_path)
    row['import_missing'] = imported
    login(nil)
    get export_settings_users_path
    expect(response).to redirect_to(new_user_session_path)
    row['guest'] = response_row('guest_export')
    row
  end

  def cloud_producer_cases(actor)
    rows = Settings::BackgroundJobsController::CLOUD_ALLOWED_JOBS.map do |name|
      row = form_request(actor, :post, settings_background_jobs_path, { job_name: name })
      expect(row['status']).to eq(302)
      expect(enqueued_jobs.map { |job| [job[:job], job[:args]] }).to eq([[EnqueueBackgroundJob, [name, actor.id]]])
      row.merge('job_name' => name)
    end
    refused = form_request(actor, :post, settings_background_jobs_path, { job_name: 'start_reverse_geocoding' })
    expect(refused['status']).to eq(303)
    expect(refused['jobs']).to eq([])
    rows << refused
  end

  def provider_cases(admin, actor)
    InstanceSetting.create!(key: 'photon_api_host', value: 'a10c-photon.example.invalid')
    InstanceSettings::Resolver.reset!
    use_real_geocoding_lookups
    allow_any_instance_of(Geocoder::Lookup::Base).to receive(:cache).and_return(nil)
    feature = { type: 'Feature', properties: { city: 'Synthetic City', country: 'Germany' },
                geometry: { type: 'Point', coordinates: [12.3712, 51.3402] } }
    lookup = stub_request(:get, %r{a10c-photon\.example\.invalid/reverse}).to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { type: 'FeatureCollection', features: [feature] }.to_json
    )
    expect(Geocoding::ProviderTest::MAX_WAIT).to eq(5.0)
    row = form_request(admin, :post, '/admin/settings/test_geocoding')
    expect(row['status']).to eq(303)
    expect(row.dig('flash', 'notice')).to eq(I18n.t('admin.settings.test_geocoding.success',
                                                    place: 'Synthetic City, Germany'))
    expect(lookup).to have_been_requested.once
    turbo = form_request(admin, :post, '/admin/settings/test_geocoding', {}, accept: 'text/vnd.turbo-stream.html')
    expect(turbo['status']).to eq(200)
    expect(response.body).to include('turbo-stream', 'Synthetic City')
    refused = form_request(actor, :post, '/admin/settings/test_geocoding')
    expect(refused['status']).not_to eq(200)
    expect(lookup).to have_been_requested.twice
    [row, turbo, refused]
  end

  def deletion_cases(admin)
    owner = synthetic_user(43_211)
    member = synthetic_user(43_212)
    family = create(:family, id: 43_211, creator: owner, name: 'Synthetic A10c family')
    create(:family_membership, user: owner, family:, role: :owner)
    create(:family_membership, user: member, family:, role: :member)
    refused = form_request(admin, :delete, settings_user_path(owner))
    expect([refused['status'], owner.reload.deleted?]).to eq([303, false])
    expect(refused['jobs']).to eq([])
    deleted = form_request(admin, :post, settings_user_path(member), { _method: 'delete' })
    expect([deleted['status'], member.reload.deleted?]).to eq([302, true])
    expect(deleted['jobs']).to eq(['Users::DestroyJob'])
    last = form_request(admin, :delete, settings_user_path(admin))
    expect([last['status'], admin.reload.deleted?]).to eq([302, true])
    expect(last['jobs']).to eq(['Users::DestroyJob'])
    [refused, deleted, last]
  end

  def mount_cases(_deleted_admin, actor)
    admin = synthetic_user(43_221, admin: true)
    [nil, actor, admin].flat_map do |person|
      login(person)
      %w[/sidekiq /admin/flipper].map do |path|
        get path
        role = if person.nil?
                 'guest'
               else
                 person.admin? ? 'admin' : 'user'
               end
        row = response_row(path).merge('actor' => role)
        if person&.admin?
          if response.redirect?
            expect(URI(response.location).path).to start_with("#{path}/")
            get response.location
            row['destination_status'] = response.status
          end
          expect(response.status).to eq(200)
        end
        expect(row['status']).not_to eq(200) unless person&.admin?
        row
      end
    end
  end

  def save_html(name, html)
    path = dir.join("#{name}.html")
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(dir)
      File.write(path, html)
    else
      expect(path.read).to eq(html)
    end
  end

  def save_json(name, cases)
    path = dir.join("#{name}.json")
    bytes = "#{Oj.dump(cases, mode: :strict, float_precision: 0, indent: 2).rstrip}\n"
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(dir)
      File.write(path, bytes)
    else
      expect(path.read).to eq(bytes)
    end
  end

  it 'captures public owner locale availability embed and headers' do
    cases = public_cases
    expect(cases.find { |row| row['name'] == 'de_direct' }.fetch('lang')).to eq('de')
    expect(cases.find { |row| row['name'] == 'en_embed' }.fetch('chrome')).to eq(false)
    save_json('public', cases)
  end

  it 'captures separate owners earned state for the same public key' do
    cases = separate_owner_cases
    expect(cases.fetch('first').fetch('count')).to eq(1)
    expect(cases.fetch('second').fetch('count')).to eq(16)
    expect(cases.fetch('viewer_matches_owner')).to be(true)
    save_json('owners', cases)
  end

  it 'records retained PNG provider mounts and producer route fates' do
    cases = retained_cases
    expect(cases.fetch('export').fetch('admin_only')).to be(false)
    expect(cases.fetch('png').fetch('type')).to eq('image/png')
    save_json('retained', cases)
  end
end
