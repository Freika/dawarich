# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: admin instance and background pages', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/admin_pages') }
  let(:now) { Time.utc(2026, 10, 3, 10) }
  let(:secret) { 'synthetic-a10-secret-not-for-production' }

  around do |example|
    saved = InstanceSettings::Registry::DEFINITIONS.values.to_h { |definition| [definition.env_var, ENV[definition.env_var]] }
    saved['DAWARICH_PHOENIX_NODE'] = ENV['DAWARICH_PHOENIX_NODE']
    saved.each_key { |key| ENV.delete(key) }
    ActionController::Base.allow_forgery_protection = true
    travel_to(now) { example.run }
  ensure
    saved.each { |key, value| ENV[key] = value }
    InstanceSettings::Resolver.reset!
    ActionController::Base.allow_forgery_protection = false
  end

  before do
    FileUtils.mkdir_p(dir)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
  end

  def actor(id, admin: true, settings: {})
    user = create(:user, id:, email: "a10-#{id}@example.invalid", admin:, changelog_consent: :declined,
                         password: 'a10-synthetic-password', created_at: now - 1.day, updated_at: now)
    user.update_columns(api_key: "a10-synthetic-key-#{id}", theme: 'dark',
                        settings: { 'timezone' => 'Europe/Berlin', 'onboarding_completed' => true }.merge(settings))
    user.reload
  end

  def user_row(user)
    { 'id' => user.id, 'email' => user.email, 'admin' => user.admin, 'theme' => user.theme,
      'settings' => user.settings, 'status' => User.statuses.fetch(user.status),
      'plan' => User.plans.fetch(user.plan), 'active_until' => user.active_until.utc.iso8601(6),
      'changelog_consent' => User.changelog_consents.fetch(user.changelog_consent) }
  end

  def capture(name, user, path, headers: {})
    Rails.cache.clear
    reset!
    InstanceSettings::Resolver.reset!
    sign_in(user) if user
    get(path, headers:)
    doc = Nokogiri::HTML5(response.body)
    fragment = doc.at_css('body > div.container > div.w-full > div.flex')
    html = fragment ? fragment.inner_html.gsub(/(name="authenticity_token" value=")[^"]*/, '\1CSRF') : ''
    html = html.gsub(/[ \t]+$/, '')
    { 'name' => name, 'path' => path, 'now' => now.iso8601, 'self_hosted' => DawarichSettings.self_hosted?,
      'status' => response.status, 'title' => doc.at_css('title')&.text, 'html' => html, 'request_headers' => headers,
      'headers' => response.headers.slice('Location', 'Content-Type', 'Cache-Control', 'Pragma'),
      'flash' => flash.to_hash.slice('alert', 'notice'), 'user' => user && user_row(user) }
  end

  def save_capture(capture)
    expect(Oj.dump(capture.except('html'), mode: :strict)).not_to include(secret)
    name = capture.fetch('name')
    html = capture.fetch('html', '').gsub(/[ \t]+$/, '').rstrip
    File.write(dir.join("#{name}.html"), html.empty? ? '' : "#{html}\n")
    File.write(dir.join("#{name}.json"),
               "#{Oj.dump(capture.except('html'), mode: :strict, float_precision: 0, indent: 2).rstrip}\n")
  end

  def instance_capture(name, user, section = name)
    captured = capture(name, user, "/admin/settings?section=#{section}")
    config = Geocoding::Config.resolved_config
    fields = InstanceSettings::Registry.keys.to_h do |key|
      setting = InstanceSettings::Resolver.get(key)
      secret_field = InstanceSettings::Registry.fetch(key).secret?
      [key.to_s, { 'source' => setting.source.to_s, 'pinned' => setting.pinned?,
                   'present' => setting.value.present?, 'value' => secret_field ? nil : setting.value,
                   'unreadable' => InstanceSetting.find_by(key: key.to_s)&.readable_value? == false }]
    end
    safe_env = InstanceSettings::Registry::DEFINITIONS.values.reject(&:secret?).to_h { |definition| [definition.env_var, ENV[definition.env_var]] }
    captured.merge('kind' => 'instance', 'fields' => fields, 'env' => safe_env,
                   'geocoding' => { 'provider' => config.provider&.to_s, 'enabled' => config.enabled?,
                                    'pinned' => config.pinned?, 'host' => config.host, 'use_https' => config.use_https,
                                    'rps' => config.rps },
                   'legacy' => ServiceSetting.service_geocoding.where(active: true).exists?,
                   'health' => { 'summary' => JobHealth.compute(nil).stringify_keys,
                                 'gauges' => JobHealth.gauges.stringify_keys })
  end

  def instance_cases
    allow(JobOwnership).to receive(:table?).and_return(false)
    user = actor(10_001)
    results = []
    provider = ActiveRecord::Encryption::DerivedSecretKeyProvider.new(secret)
    ActiveRecord::Encryption.with_encryption_context(key_provider: provider) do
      InstanceSetting.create!(id: 10_001, key: 'photon_api_host', value: 'photon.example.invalid')
      InstanceSetting.create!(id: 10_002, key: 'geoapify_api_key', value: secret)
      InstanceSetting.create!(id: 10_003, key: 'nominatim_api_key', value: secret)
      InstanceSetting.create!(id: 10_004, key: 'reverse_geocoding_rps', value: 5.0)
      %w[photon geoapify nominatim locationiq rate_limit points invalid default].each do |section|
        results << instance_capture(section, user, section == 'default' ? '' : section)
      end
      ENV['PHOTON_API_HOST'] = 'pinned.example.invalid'
      ENV['PHOTON_API_USE_HTTPS'] = 'false'
      ENV['PHOTON_API_KEY'] = secret
      results << instance_capture('pinned', user, 'photon')
      %w[PHOTON_API_HOST PHOTON_API_USE_HTTPS PHOTON_API_KEY].each { |key| ENV.delete(key) }
      InstanceSetting.find(10_001).update!(value: 'photon.komoot.io:443/path')
      results << instance_capture('tls', user, 'photon')
      sql("UPDATE instance_settings SET encrypted_value = 'not-valid-ciphertext' WHERE id = 10002")
      results << instance_capture('unreadable', user, 'geoapify')
      ServiceSetting.insert!({ id: 10_001, user_id: user.id, service: 0, provider: 'photon', active: true,
                              config: {}, created_at: now, updated_at: now })
      InstanceSetting.where(key: 'photon_api_host').delete_all
      results << instance_capture('legacy', user, 'photon')
      InstanceSetting.create!(id: 10_001, key: 'photon_api_host', value: 'photon.komoot.io:443/path')
      { 'absent' => [{ status: 'absent', alarm: false }, { tables: false }],
        'ok' => [{ status: 'ok', alarm: false },
                 { tables: true, outbox: {}, owners: [], nodes: [], oban: [], rails_commands: nil }],
        'alarm' => [{ status: 'stale', alarm: true },
                    { tables: true, outbox: {}, owners: [], nodes: [], oban: [], rails_commands: nil }],
        'unknown' => [{ status: 'unknown', alarm: false }, { tables: :unknown }] }.each do |name, (summary, gauges)|
        allow(JobHealth).to receive(:compute).and_return(summary)
        allow(JobHealth).to receive(:gauges).and_return(gauges)
        results << instance_capture("health_#{name}", user, 'photon')
      end
    end
    results
  end

  def background_cases
    queue_key = DataMigrations::RecalculateAnomaliesUserJob::QUEUED_SETTINGS_KEY
    done_key = DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY
    configs = { 'admin' => [true, {}], 'nonadmin' => [false, {}], 'default' => [false, {}],
                'string_true' => [false, { 'visits_suggestions_enabled' => 'true' }],
                'string_false' => [false, { 'visits_suggestions_enabled' => 'false' }],
                'bool_true' => [false, { 'visits_suggestions_enabled' => true }],
                'bool_false' => [false, { 'visits_suggestions_enabled' => false }],
                'nil' => [false, { 'visits_suggestions_enabled' => nil }],
                'queued' => [false, { queue_key => now.iso8601 }],
                'recalculated' => [false, { queue_key => now.iso8601, done_key => now.iso8601 }],
                'neither' => [false, {}] }
    user = actor(10_001, admin: false)
    results = configs.map do |name, (admin, settings)|
      user.update_columns(admin:,
                          settings: { 'timezone' => 'Europe/Berlin', 'onboarding_completed' => true }.merge(settings))
      user.reload
      capture("background_#{name}", user, '/settings/background_jobs')
        .merge('kind' => 'background', 'notice' => user.gps_noise_recheck_pending?,
               'visits' => user.safe_settings.visits_suggestions_enabled?)
    end
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    results << capture('background_cloud', user, '/settings/background_jobs')
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    results << capture('background_guest', nil, '/settings/background_jobs')
    results
  end

  def authorization_cases
    admin = actor(10_001)
    member = actor(10_002, admin: false)
    results = [capture('instance_guest', nil, '/admin/settings'),
               capture('instance_nonadmin', member, '/admin/settings'),
               capture('users_guest', nil, '/settings/users'), capture('users_nonadmin', member, '/settings/users'),
               capture('users_referer', member, '/settings/users',
                       headers: { 'Referer' => 'http://www.example.com/settings/general' })]
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    results.concat([capture('instance_cloud_guest', nil, '/admin/settings'),
                    capture('instance_cloud_admin', admin, '/admin/settings'),
                    capture('users_cloud_guest', nil, '/settings/users'),
                    capture('users_cloud_admin', admin, '/settings/users')])
    results
  end

  def sql(text, *values)
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([text, *values]))
  end

  def scalar(text, *values)
    ActiveRecord::Base.connection.select_value(ActiveRecord::Base.sanitize_sql_array([text, *values]))
  end

  def health_capture(name, node)
    summary = JobHealth.compute(node).stringify_keys
    gauges = normalized_gauges(JobHealth.gauges)
    { 'name' => name, 'kind' => 'health', 'node' => node, 'now' => now.iso8601,
      'summary' => summary.deep_dup, 'source_summary' => summary,
      'gauges' => gauges.deep_dup, 'source_gauges' => gauges,
      'pretty' => gauges['tables'] == true ? JSON.pretty_generate(gauges.except('tables')) : nil,
      'rows' => health_rows }
  end

  def normalized_gauges(gauges)
    unless gauges[:tables] == true
      return gauges.transform_keys(&:to_s).transform_values do |value|
        value == :unknown ? 'unknown' : value
      end
    end

    gauge = gauges.deep_dup
    offset = scalar("SELECT EXTRACT(EPOCH FROM now() - TIMESTAMP '2026-10-03 10:00:00')::integer")
    %i[outbox rails_commands].each do |key|
      next unless gauge[key] && gauge[key]['oldest_due_seconds']

      expect(gauge[key]['oldest_due_seconds']).to eq(offset + 600)
      gauge[key]['oldest_due_seconds'] = 600
    end
    gauge[:nodes].each do |node|
      expected_age = @beat_ages.fetch(node['node'])
      age = scalar('SELECT EXTRACT(EPOCH FROM now() - ?::timestamptz)::integer', node['beat_at'])
      expect(age).to eq(expected_age)
      node['started_at'] = normalized_time(node['started_at'], now - 1.hour)
      node['beat_at'] = normalized_time(node['beat_at'], now - expected_age.seconds)
    end
    JSON.parse(JSON.generate(gauge))
  end

  def normalized_time(original, normalized)
    value = original.utc? ? normalized : normalized.getlocal(original.utc_offset)
    expect(JSON.generate(value).last(7)).to eq(JSON.generate(original).last(7))
    value
  end

  def health_rows
    return {} unless JobOwnership.table?

    rows = { 'owners' => ActiveRecord::Base.connection.select_all(JobHealth::OWNERS_SQL).to_a.map do |row|
      row.slice('key', 'owner', 'pinned', 'updated_by')
    end,
      'nodes' => [{ 'node' => 'web-a', 'started_at' => (now - 1.hour).iso8601,
                   'beat_at' => (now - @beat_ages.fetch('web-a').seconds).iso8601 },
                  { 'node' => 'web-z', 'started_at' => (now - 1.hour).iso8601,
'beat_at' => (now - 120.seconds).iso8601 }] }
    outbox_sql = <<~SQL.squish
      SELECT event_id, command_type, command_version, payload, state, scheduled_at, created_at
      FROM job_outbox ORDER BY event_id
    SQL
    rows['outbox'] = ActiveRecord::Base.connection.select_all(outbox_sql).to_a.map do |row|
      if row['event_id'].end_with?('010002')
        expect(scalar('SELECT EXTRACT(EPOCH FROM ?::timestamptz - now())::integer', row['scheduled_at'])).to eq(3600)
        row['scheduled_at'] = now + 1.hour
      end
      JSON.parse(JSON.generate(row))
    end
    commands_sql = <<~SQL.squish
      SELECT id, kind, payload, attempts, available_at, leased_until, created_at
      FROM phoenix.rails_commands ORDER BY id
    SQL
    rows['rails_commands'] = ActiveRecord::Base.connection.select_all(commands_sql).to_a.map do |row|
      row['available_at'] = now + 1.hour if row['id'] == 10_004
      row['leased_until'] = now + 1.hour if row['id'] == 10_003
      JSON.parse(JSON.generate(row))
    end
    dead_sql = <<~SQL.squish
      SELECT id, kind, payload, attempts, last_error, created_at, died_at
      FROM phoenix.rails_commands_dead ORDER BY id
    SQL
    rows['rails_commands_dead'] = ActiveRecord::Base.connection.select_all(dead_sql).to_a
                                                    .map { |row| JSON.parse(JSON.generate(row)) }
    rows['oban'] = JobHealth.oban_counts
    rows
  end

  def health_cases
    @beat_ages = { 'web-a' => 5, 'web-z' => 120 }
    phoenix_tables!
    sql(<<~SQL.squish, now, now)
      INSERT INTO phoenix.job_owners VALUES
      ('command:z', 'sidekiq', false, ?, 'fixture'), ('command:a', 'oban', true, ?, 'fixture')
    SQL
    sql(<<~SQL.squish)
      INSERT INTO phoenix.runtime_nodes VALUES
      ('web-z', now() - interval '1 hour', now() - interval '120 seconds'),
      ('web-a', now() - interval '1 hour', now() - interval '5 seconds')
    SQL
    results = [health_capture('fresh', 'web-a'), health_capture('stale', 'web-z'), health_capture('absent', nil)]
    sql("UPDATE phoenix.runtime_nodes SET beat_at = now() - interval '120 seconds' WHERE node = 'web-a'")
    @beat_ages['web-a'] = 120
    results.concat([health_capture('owned_stale', 'web-a'), health_capture('owned_absent', nil)])
    sql("UPDATE phoenix.runtime_nodes SET beat_at = now() - interval '5 seconds' WHERE node = 'web-a'")
    @beat_ages['web-a'] = 5
    sql(<<~SQL.squish, now - 600.seconds, now, now, now, now)
      INSERT INTO job_outbox
      (event_id, command_type, command_version, payload, state, scheduled_at, created_at) VALUES
      ('00000000-0000-4000-8000-000000010001', 'trips.calculate', 1, '{}', 'pending', ?, ?),
      ('00000000-0000-4000-8000-000000010002', 'trips.calculate', 1, '{}', 'pending', now() + interval '1 hour', ?),
      ('00000000-0000-4000-8000-000000010003', 'trips.calculate', 1, '{}', 'quarantined', ?, ?)
    SQL
    results << health_capture('overdue', 'web-a')
    sql(<<~SQL.squish, now - 600.seconds, now, now, now, now, now, now)
      INSERT INTO phoenix.rails_commands (id, kind, payload, attempts, available_at, leased_until, created_at) VALUES
      (10001, 'visit_months_changed', '{}', 0, ?, NULL, ?),
      (10002, 'visit_months_changed', '{}', 3, ?, NULL, ?),
      (10003, 'visit_months_changed', '{}', 1, ?, now() + interval '1 hour', ?),
      (10004, 'visit_months_changed', '{}', 0, now() + interval '1 hour', NULL, ?)
    SQL
    sql(<<~SQL.squish, now, now)
      INSERT INTO phoenix.rails_commands_dead VALUES
      (10099, 'visit_months_changed', '{}', 25, 'synthetic fixture error', ?, ?)
    SQL
    sql('CREATE SCHEMA oban')
    sql('CREATE TABLE oban.oban_jobs (id bigint, worker text, state text)')
    sql(<<~SQL.squish)
      INSERT INTO oban.oban_jobs VALUES
      (10001, 'Dawarich.ZWorker', 'cancelled'), (10002, 'Dawarich.AWorker', 'executing'),
      (10003, 'Dawarich.AWorker', 'executing'), (10004, 'Dawarich.AWorker', 'available')
    SQL
    results << health_capture('gauges', 'web-a')
    allow(JobOwnership).to receive(:table?).and_return(false)
    results << health_capture('missing', nil)
    allow(JobOwnership).to receive(:table?).and_raise(ActiveRecord::ConnectionNotEstablished,
                                                      'synthetic unavailable read')
    summary = JobHealth.compute('web-a').stringify_keys
    gauges = normalized_gauges(JobHealth.gauges)
    results << { 'name' => 'unavailable', 'kind' => 'health',
                 'summary' => summary.deep_dup, 'source_summary' => summary,
                 'gauges' => gauges.deep_dup, 'source_gauges' => gauges, 'pretty' => nil, 'rows' => {} }
    results
  end

  it 'writes instance sections and redacted secret controls' do
    cases = instance_cases
    expect(cases.map { |capture| capture.fetch('name') })
      .to include(*%w[photon geoapify nominatim locationiq rate_limit points invalid default pinned tls
                      unreadable legacy
                      health_absent health_ok health_alarm health_unknown])
    cases.each do |capture|
      expect(capture.fetch('status')).to eq(200)
      expect(capture.fetch('html')).not_to include(secret)
      doc = Nokogiri::HTML5.fragment(capture.fetch('html'))
      unless doc.css('input[type="password"]').empty?
        expect(doc.css('input[type="password"]').map do |input|
          input['value']
        end.uniq).to eq([''])
      end
      save_capture(capture)
    end
    pinned = Nokogiri::HTML5.fragment(cases.find { |capture| capture['name'] == 'pinned' }.fetch('html'))
    expect(pinned.at_css('input[type="hidden"][name="instance_settings[photon_api_use_https]"]')).to be_nil
    expect(pinned.at_css('#instance_settings_photon_api_use_https').key?('checked')).to be(false)
    expect(pinned.at_css('#instance_settings_photon_api_use_https').key?('disabled')).to be(true)
    expect(pinned.at_css('[data-testid="instance-settings-pane-photon"] button[type="submit"]')).to be_nil
    corrupt = cases.find { |capture| capture['name'] == 'unreadable' }
    expect(corrupt.dig('fields', 'geoapify_api_key', 'unreadable')).to be(true)
    expect(corrupt.dig('fields', 'geoapify_api_key', 'present')).to be(false)
    unreadable = Nokogiri::HTML5.fragment(corrupt.fetch('html'))
    expect(unreadable.at_css('#instance_settings_geoapify_api_key_clear')).to be_present
    legacy = Nokogiri::HTML5.fragment(cases.find { |capture| capture['name'] == 'legacy' }.fetch('html'))
    expect(legacy.at_css('[data-testid="instance-settings-legacy-user-geocoding"]')).to be_present
  end

  it 'writes un-stubbed JobHealth data and serialization oracle' do
    cases = health_cases
    expect(cases.map do |capture|
      capture.fetch('name')
    end).to eq(%w[fresh stale absent owned_stale owned_absent overdue gauges missing unavailable])
    cases.each do |capture|
      expect(capture.fetch('summary')).to eq(capture.fetch('source_summary'))
      expect(capture.fetch('gauges')).to eq(capture.fetch('source_gauges'))
      if capture.fetch('gauges')['tables'] == true
        expect(capture.fetch('pretty')).to eq(JSON.pretty_generate(capture.fetch('source_gauges').except('tables')))
      end
      save_capture(capture.except('source_summary', 'source_gauges'))
    end
    expect(cases.find { |capture| capture['name'] == 'gauges' }.dig('gauges', 'rails_commands', 'due')).to eq(2)
    expect(cases.map do |capture|
      capture.dig('summary', 'status')
    end).to eq(%w[ok stale absent stale absent ok ok absent unknown])
    expect(cases.map do |capture|
      capture.dig('summary', 'alarm')
    end).to eq([false, false, false, true, true, true, true, false, false])
    gauges = cases.find { |capture| capture['name'] == 'gauges' }.fetch('gauges')
    expect(gauges.fetch('owners').map { |row| row.fetch('key') }).to eq(%w[command:a command:z])
    expect(gauges.fetch('rails_commands')).to eq('due' => 2, 'leased' => 1, 'retrying' => 1, 'dead' => 1,
                                                 'oldest_due_seconds' => 600)
    expect(gauges.fetch('oban')).to eq([{ 'worker' => 'Dawarich.AWorker', 'state' => 'available', 'count' => 1 },
                                        { 'worker' => 'Dawarich.AWorker', 'state' => 'executing', 'count' => 2 },
                                        { 'worker' => 'Dawarich.ZWorker', 'state' => 'cancelled', 'count' => 1 }])
  end

  it 'writes background role toggle and queued notice cases' do
    cases = background_cases
    expect(cases.map { |capture| capture.fetch('name') })
      .to include(*%w[background_admin background_nonadmin background_default background_string_true
                      background_string_false background_bool_true background_bool_false background_nil
                      background_queued background_recalculated
                      background_neither background_cloud background_guest])
    cases.each do |capture|
      if capture.fetch('status') == 200
        doc = Nokogiri::HTML5.fragment(capture.fetch('html'))
        expect(doc.at_css('[data-testid="gps-noise-recheck-pending"]').present?).to eq(capture.fetch('notice'))
        expect(doc.at_css('a[href="/sidekiq"]').present?).to eq(capture.dig('user', 'admin'))
        toggle = doc.at_css('a[data-turbo-method="patch"]')
        expected = capture.fetch('visits') ? 'false' : 'true'
        expect(CGI.unescape(toggle['href'])).to include("settings[visits_suggestions_enabled]=#{expected}")
      end
      save_capture(capture)
    end
  end

  it 'writes admin authorization responses' do
    cases = authorization_cases
    expect(cases.map { |capture| capture.fetch('name') })
      .to eq(%w[instance_guest instance_nonadmin users_guest users_nonadmin users_referer instance_cloud_guest
                instance_cloud_admin users_cloud_guest users_cloud_admin])
    cases.each do |capture|
      expected = if capture['name'] == 'instance_nonadmin' then 404
                 elsif %w[instance_guest instance_cloud_guest users_guest].include?(capture['name']) then 302
                 else 303
                 end
      expect(capture.fetch('status')).to eq(expected)
      save_capture(capture)
    end
  end

  def api_health_capture(name, path: '/api/v1/health', key: nil, bearer: nil,
                         summary: { status: 'unknown', alarm: false }, limit_count: 0, query: nil)
    reset!
    Rack::Attack.reset!
    Rails.cache.clear
    JobHealth.reset!
    allow(JobHealth).to receive(:compute).and_return(summary)
    JobHealth.refresh! unless summary[:status] == 'unknown'
    headers = { 'Host' => 'staging.dawarich.app', 'X-Forwarded-Proto' => 'https' }
    headers['Authorization'] = "Bearer #{bearer}" if bearer
    target = key.nil? ? path : "#{path}?api_key=#{CGI.escape(key)}"
    status = wire_headers = raw = nil
    (limit_count + 1).times do
      env = Rack::MockRequest.env_for("http://staging.dawarich.app#{target}")
                             .merge(Rails.application.env_config)
      env['QUERY_STRING'] = query if query
      headers.each { |name, value| env["HTTP_#{name.upcase.tr('-', '_')}"] = value }
      status, wire_headers, wire_body = Rails.application.call(env)
      raw = +''
      wire_body.each { |part| raw << part }
      wire_body.close if wire_body.respond_to?(:close)
    end
    body = JSON.parse(raw) if raw.start_with?('{')
    if body && body['resume_url']
      body['resume_url'] = body['resume_url'].sub(/token=.*/, 'token=SUBSCRIPTION_TOKEN')
      raw = JSON.generate(body)
    end
    { 'name' => name, 'path' => path, 'query_key' => key, 'bearer' => bearer,
      'summary' => summary.stringify_keys, 'self_hosted' => DawarichSettings.self_hosted?,
      'limit_count' => limit_count, 'status' => status, 'body' => body, 'raw_body' => raw,
      'headers' => wire_headers.to_a.group_by { |name, _| name.downcase }
                               .transform_values { |pairs| pairs.map(&:last) }
                               .except('x-request-id', 'x-runtime', 'etag', 'set-cookie') }
  end

  it 'writes the health and readiness HTTP corpus' do
    user = actor(10_101)
    user.update_columns(plan: User.plans.fetch('lite'))
    pending = actor(10_102)
    pending.update_columns(status: User.statuses.fetch('pending_payment'))
    saved_enabled = Rack::Attack.enabled
    saved_env = ENV.slice('JWT_SECRET_KEY')
    ENV['JWT_SECRET_KEY'] = 'a12f-synthetic-checkout-secret'
    Rack::Attack.enabled = true
    cases = %w[unknown absent stale ok].map do |status|
      api_health_capture(status, summary: { status:, alarm: false })
    end
    cases << api_health_capture('alarm', summary: { status: 'stale', alarm: true })
    cases << api_health_capture('query_valid', key: user.api_key)
    cases << api_health_capture('query_invalid', key: 'a12f-invalid')
    cases << api_health_capture('bearer_valid', bearer: user.api_key)
    cases << api_health_capture('bearer_invalid', bearer: 'a12f-invalid')
    cases << api_health_capture('query_precedence', key: 'a12f-invalid', bearer: user.api_key)
    cases << api_health_capture('query_empty', key: '', bearer: user.api_key)
    cases << api_health_capture('pending', key: pending.api_key)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    cases << api_health_capture('cloud_anonymous')
    cases << api_health_capture('cloud_ok', key: user.api_key)
    cases << api_health_capture('cloud_invalid', key: 'a12f-invalid')
    cases << api_health_capture('cloud_throttled', key: user.api_key, limit_count: 200)
    cases << api_health_capture('cloud_pending', key: pending.api_key)
    allow(ActiveRecord::Base.connection).to receive(:select_value).with('SELECT 1').and_return(1)
    allow(Sidekiq).to receive(:redis).and_yield(double(call: 'PONG'))
    cases << api_health_capture('ready_ok', path: '/api/v1/ready')
    cases << api_health_capture('ready_pending', path: '/api/v1/ready', key: pending.api_key)
    cases << api_health_capture('ready_cloud_key', path: '/api/v1/ready', key: user.api_key)
    cases << api_health_capture('ready_cloud_throttled', path: '/api/v1/ready', key: user.api_key, limit_count: 200)
    allow(ActiveRecord::Base.connection).to receive(:select_value).with('SELECT 1').and_raise(PG::ConnectionBad)
    cases << api_health_capture('ready_database_error', path: '/api/v1/ready', key: user.api_key)
    allow(ActiveRecord::Base.connection).to receive(:select_value).with('SELECT 1').and_return(1)
    allow(Sidekiq).to receive(:redis).and_raise(RedisClient::CannotConnectError)
    cases << api_health_capture('ready_redis_error', path: '/api/v1/ready')
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    cases << api_health_capture('ready_self_hosted_error', path: '/api/v1/ready')
    expect(cases.take(5).map { |reply| reply.fetch('body').fetch('phoenix').keys.sort }).to all(eq(%w[alarm status]))
    expect(cases.find { |reply| reply['name'] == 'cloud_throttled' }.fetch('status')).to eq(429)
    corpus = { 'version' => APP_VERSION, 'now' => now.iso8601, 'cases' => cases }
    File.write(dir.join('api_health.json'), "#{JSON.pretty_generate(corpus)}\n")
    config = Rails.application.env_config.merge('action_dispatch.show_exceptions' => :all,
                                                'action_dispatch.show_detailed_exceptions' => false)
    allow(Rails.application).to receive(:env_config).and_return(config)
    allow(Sidekiq).to receive(:redis).and_yield(double(call: 'PONG'))
    queries = %w[x=%GG %GG=x x=% x=%2 x=%FF x[y]=1 x=1&x[y]=2 x =1 x=1&x=2 x=%25GG format=xml]
    query_cases = %w[/api/v1/health /api/v1/ready].flat_map do |path|
      queries.map do |query|
        api_health_capture(query, path:, query:).merge('query' => query)
      end
    end
    expect(query_cases.select { |reply| reply['query'] == 'x=%GG' }.pluck('status')).to eq([400, 400])
    File.write(dir.join('api_health_queries.json'), "#{JSON.pretty_generate(query_cases)}\n")
  ensure
    Rack::Attack.enabled = saved_enabled
    Rack::Attack.reset!
    JobHealth.reset!
    ENV['JWT_SECRET_KEY'] = saved_env['JWT_SECRET_KEY']
  end
end
