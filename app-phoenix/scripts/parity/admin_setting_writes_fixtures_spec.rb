# frozen_string_literal: true

require 'rails_helper'
require 'open3'

RSpec.describe 'Phoenix fixtures: admin setting writes', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/admin_setting_writes') }
  let(:now) { Time.utc(2026, 10, 4, 10) }
  let(:secret) { 'synthetic-a10b-encryption-input' }

  def phoenix(code, extra = {})
    native_env = {
      'PATH' => "#{Dir.home}/.asdf/shims:#{ENV.fetch('PATH')}",
      'ASDF_ERLANG_VERSION' => '27.3.4.1', 'ASDF_ELIXIR_VERSION' => '1.18.3-otp-27',
      'MIX_ENV' => 'test', 'RAILS_ENV' => 'test', 'DATABASE_HOST' => '127.0.0.1',
      'DATABASE_NAME' => ENV.fetch('DATABASE_NAME'), 'PHOENIX_TEST_DATABASE' => ENV.fetch('DATABASE_NAME'),
      'PHOENIX_TEST_REDIS_URL' => ENV.fetch('PHOENIX_TEST_REDIS_URL'),
      'A10B_RAILS_SECRET' => Rails.application.secret_key_base
    }.merge(extra)
    bootstrap = <<~ELIXIR
      for app <- [:ecto_sql, :postgrex, :crypto, :redix, :bcrypt_elixir, :tzdata],
        do: Application.ensure_all_started(app)
      Application.put_env(:dawarich, :rails_secret, System.fetch_env!("A10B_RAILS_SECRET"))
      {:ok, _} = Dawarich.Repo.start_link(database: System.fetch_env!("DATABASE_NAME"),
        pool: DBConnection.ConnectionPool, pool_size: 1, prepare: :unnamed)
      for spec <- Dawarich.Redis.child_specs() ++ Dawarich.Redis.cache_child_specs(),
        do: Supervisor.start_link([spec], strategy: :one_for_one)
    ELIXIR
    output, status = Open3.capture2e(native_env, 'mix', 'run', '--no-start', '-e', bootstrap + code,
                                     chdir: Rails.root.join('app-phoenix').to_s)
    expect(status.success?).to be(true), 'native interoperability failed; output withheld'
    JSON.parse(output.lines.last)
  end

  around do |example|
    saved = InstanceSettings::Registry::DEFINITIONS.values.to_h { |definition| [definition.env_var, ENV[definition.env_var]] }
    saved.each_key { |key| ENV.delete(key) }
    protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    travel_to(now) do
      if example.metadata[:a10b_non_transactional]
        example.run
      else
        with_legacy_registration { example.run }
      end
    end
  ensure
    saved.each { |key, value| ENV[key] = value }
    ActionController::Base.allow_forgery_protection = protection
    InstanceSettings::Resolver.reset!
    Rails.cache.delete('dawarich/registration_enabled')
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    FileUtils.mkdir_p(dir)
  end

  def instance_cases
    actor = synthetic_user(12_001, admin: true)
    login(actor)
    @published = []
    allow(InstanceSettings::Notifier.redis).to receive(:publish) do |channel, payload|
      @published << { 'channel' => channel, 'payload' => JSON.parse(payload) }
      0
    end
    values = { photon_api_host: ' HTTPS://Photon.Example.invalid:2322/ ', photon_api_key: secret,
               photon_api_use_https: 'true', nominatim_api_host: 'https://Nominatim.Example.invalid/',
               nominatim_api_key: secret, nominatim_api_use_https: 'false', geoapify_api_key: secret,
               locationiq_api_key: secret, reverse_geocoding_rps: ' 2.5 ', store_geodata: 'false', unknown: 'ignored' }
    results = [instance_write('all_registry', values)]
    expect(InstanceSetting.count).to eq(10)
    expect(InstanceSetting.exists?(key: 'unknown')).to be(false)
    InstanceSettings::Registry.secret_keys.each do |key|
      expect(InstanceSetting.find_by!(key: key.to_s).value == secret).to be(true)
    end
    expect(results.first.dig('fields', 'photon_api_host', 'value')).to eq('photon.example.invalid:2322')
    expect(results.first.dig('fields', 'reverse_geocoding_rps', 'value')).to eq(2.5)
    results.concat(boolean_cases)
    results << instance_write('defaults', { photon_api_host: ' ', reverse_geocoding_rps: 'invalid',
                                            nominatim_api_use_https: '', store_geodata: '' })
    expect(InstanceSetting.find_by!(key: 'store_geodata').value).to be(true)
    expect(InstanceSetting.find_by!(key: 'nominatim_api_use_https').value).to be(true)
    expect(InstanceSetting.find_by!(key: 'reverse_geocoding_rps').value).to be_nil
    results << instance_write('secret_untouched', { geoapify_api_key: '  ' })
    expect(InstanceSetting.find_by!(key: 'geoapify_api_key').value == secret).to be(true)
    results << instance_write('secret_clear', { geoapify_api_key: '' },
                              extra: [['instance_settings_clear[geoapify_api_key]', '1']])
    expect(InstanceSetting.find_by!(key: 'geoapify_api_key').value).to be_nil
    results << instance_write('secret_replace', { geoapify_api_key: secret })
    corrupt_secret('geoapify_api_key')
    results << instance_write('secret_unreadable', { geoapify_api_key: secret })
    expect(InstanceSetting.find_by!(key: 'geoapify_api_key').value == secret).to be(true)
    results << instance_write('photon_normalized', { photon_api_host: ' https://PHOTON.Example.invalid:443/// ' })
    expect(InstanceSettings::Resolver.value(:photon_api_host)).to eq('photon.example.invalid:443')
    results << instance_write('komoot_cleared', { photon_api_host: 'photon.komoot.io', photon_api_key: '' })
    expect(InstanceSettings::Resolver.value(:photon_api_key)).to be_nil
    ENV['PHOTON_API_KEY'] = secret
    InstanceSettings::Resolver.reset!
    results << instance_write('komoot_pinned', { photon_api_host: 'photon.komoot.io' })
    expect(InstanceSettings::Resolver.value(:photon_api_key) == secret).to be(true)
    ENV.delete('PHOTON_API_KEY')
    InstanceSettings::Resolver.reset!
    before = safe_fields
    results << instance_write('chibigeo_missing', { photon_api_host: 'app.chibigeo.com/v1/photon', photon_api_key: '' })
    expect(safe_fields).to eq(before)
    expect(flash[:alert]).to be_present
    results << instance_write('chibigeo_valid', { photon_api_host: 'app.chibigeo.com/v1/photon',
                                                photon_api_key: secret, photon_api_use_https: 'false' })
    expect(Geocoding::Config.resolved_config.use_https).to be(true)
    before = safe_fields
    results << instance_write('invalid_no_writes', { store_geodata: 'false', nominatim_api_host: 'bad host' })
    expect(safe_fields).to eq(before)
    InstanceSetting.where(key: 'photon_api_host').delete_all
    ENV['PHOTON_API_HOST'] = 'pinned.example.invalid'
    InstanceSettings::Resolver.reset!
    results << instance_write('mixed_pinned', { photon_api_host: 'attempt.example.invalid', store_geodata: 'false' })
    expect(InstanceSetting.exists?(key: 'photon_api_host')).to be(false)
    expect(InstanceSetting.find_by!(key: 'store_geodata').value).to be(false)
    expect(flash[:alert]).to include('PHOTON_API_HOST')
    ENV.delete('PHOTON_API_HOST')
    InstanceSettings::Resolver.reset!
    results << partial_case
    allow(InstanceSettings::Notifier.redis).to receive(:publish).and_raise(IOError, 'synthetic publish failure')
    results << instance_write('publish_failure', { store_geodata: 'true' })
    expect(InstanceSetting.find_by!(key: 'store_geodata').value).to be(true)
    expect(flash[:notice]).to be_present
    results
  end

  def setting_cases
    actor = synthetic_user(12_001, admin: true)
    login(actor, page: settings_users_path)
    results = registration_cases
    Rails.cache.write('dawarich/registration_enabled', false)
    reset!
    get root_path
    results << home_policy('self_hosted_disabled', false)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    get root_path
    results << home_policy('cloud_disabled', true)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    user = synthetic_user(12_002, admin: false)
    user.update_columns(settings: { 'locale' => 'en', 'unrelated' => 'retained',
                                   'visits_suggestions_enabled' => 'false',
                                   'immich_url' => 'https://immich.example.invalid///',
                                   'photoprism_url' => 'https://photos.example.invalid/',
                                   'maps' => { 'url' => ' https://maps.example.invalid ' } })
    login(user, page: settings_background_jobs_path)
    [%w[background_query_true true], %w[background_query_false false]].each do |name, value|
      get settings_background_jobs_path
      link = Nokogiri::HTML(response.body).css('a[data-turbo-method="patch"]')
                     .find { |node| node['href'].include?('visits_suggestions_enabled') }
      query = URI(link['href']).query
      expect(URI.decode_www_form(query)).to eq([['settings[visits_suggestions_enabled]', value]])
      token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
      patch link['href'], params: '', headers: form_headers.merge('X-CSRF-Token' => token,
                                                                  'Accept' => 'text/vnd.turbo-stream.html, text/html')
      expect(response.status).to eq(302)
      expect(user.reload.settings['visits_suggestions_enabled']).to eq(value)
      results << response_row(name).merge('query' => query, 'body' => '', 'csrf_header' => true,
                                          'admin' => user.admin, 'after' => user.settings)
    end
    get settings_background_jobs_path
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
    path = '/settings/background_jobs?settings%5Bvisits_suggestions_enabled%5D=true'
    post path, params: '_method=patch', headers: form_headers.merge('X-CSRF-Token' => token)
    expect(response.status).to eq(302)
    results << response_row('background_override').merge('query' => URI(path).query, 'body' => '_method=patch',
                                                         'csrf_header' => true, 'after' => user.reload.settings)
    results << background_body('background_body', user, 'false')
    get settings_background_jobs_path
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
    before = user.reload.attributes
    clear_enqueued_jobs
    body = 'commit=Save%20changes&_method=patch'
    post settings_background_jobs_path, params: body, headers: form_headers.merge('X-CSRF-Token' => token)
    expect(response.status).to eq(400)
    expect(user.reload.attributes).to eq(before)
    expect(enqueued_jobs).to be_empty
    results << { 'name' => 'missing_background_settings', 'status' => response.status,
                 'body' => body, 'error' => 'ActionController::ParameterMissing', 'unchanged' => true }
    user.update_columns(settings: { 'locale' => 'en' })
    stat = create(:stat, user: user, year: 2026, month: 9, calculation_version: 7)
    clear_enqueued_jobs
    capture = background_body('background_timezone_callback', user, 'true')
    expect(stat.reload.calculation_version).to eq(0)
    expect(stat.repair_deferred_at).to eq(now)
    jobs = enqueued_jobs.select { |job| job[:job] == Stats::CalculatingJob }
    expect(jobs.length).to eq(1)
    expect(jobs.first[:args].first(3)).to eq([user.id, 2026, 9])
    capture.merge!('before_timezone' => nil, 'stat_version' => stat.calculation_version,
                   'repair_deferred_at' => stat.repair_deferred_at.utc.iso8601(6),
                   'job' => { 'class' => jobs.first[:job].name, 'arguments' => jobs.first[:args].first(3) })
    results << capture
    user.update_columns(settings: ['unsupported-container'])
    results << background_body('background_nonobject', user, 'true')
    expect(user.settings).to be_a(Hash)
    expect(user.settings['visits_suggestions_enabled']).to eq('true')
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    patch settings_background_jobs_path, params: { settings: { visits_suggestions_enabled: 'false' } },
                                         headers: { 'X-CSRF-Token' => token }
    expect(response).to redirect_to(root_path)
    results << response_row('background_cloud')
    reset!
    get root_path
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
    patch settings_background_jobs_path, params: { settings: { visits_suggestions_enabled: 'true' } },
                                         headers: { 'X-CSRF-Token' => token }
    expect(response).to redirect_to(new_user_session_path)
    results << response_row('background_guest')
    results
  end

  def synthetic_user(id, admin:)
    create(:user, id: id, email: "a10b-setting-#{id}@example.invalid", password: 'a10b-synthetic-password',
                  admin: admin, changelog_consent: :declined, created_at: now, updated_at: now,
                  settings: { 'locale' => 'en', 'onboarding_completed' => true })
  end

  def login(actor, page: admin_settings_path)
    reset!
    sign_in actor
    get page
    expect(response.status).to eq(200)
  end

  def form_headers
    { 'Content-Type' => 'application/x-www-form-urlencoded', 'Origin' => 'http://www.example.com' }
  end

  def response_row(name)
    { 'name' => name, 'status' => response.status,
      'location' => response.location && "#{URI(response.location).path}#{URI(response.location).query && '?'}" \
                                        "#{URI(response.location).query}",
      'headers' => response.headers.slice('Content-Type', 'Cache-Control'), 'flash' => flash.to_hash.stringify_keys }
  end

  def safe_fields
    InstanceSettings::Registry.keys.to_h do |key|
      setting = InstanceSettings::Resolver.get(key)
      row = InstanceSetting.find_by(key: key.to_s)
      definition = InstanceSettings::Registry.fetch(key)
      [key.to_s, { 'stored' => !row.nil?, 'pinned' => setting.pinned?, 'source' => setting.source.to_s,
                  'value' => definition.secret? ? nil : setting.value,
                  'present' => setting.value.present?, 'unreadable' => row&.readable_value? == false,
                  'plain_column_null' => row.nil? || row[:value].nil? }]
    end
  end

  def instance_write(name, values, extra: [])
    get admin_settings_path
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
    pairs = values.map { |key, value| ["instance_settings[#{key}]", value] } + extra
    raw = URI.encode_www_form(pairs)
    @published.clear
    patch admin_settings_path, params: raw, headers: form_headers.merge('X-CSRF-Token' => token)
    expect(response.status).to eq(303)
    @published.each do |notification|
      expect(notification['channel']).to eq('dawarich:instance_settings')
      expect(notification['payload'].keys).to eq(['key'])
    end
    response_row(name).merge('fields' => safe_fields, 'published' => @published.dup)
  end

  def boolean_cases
    [['checked_https', 'photon', 'photon_api_use_https', true],
     ['unchecked_https', 'photon', 'photon_api_use_https', false],
     ['checked_store', 'points', 'store_geodata', true],
     ['unchecked_store', 'points', 'store_geodata', false]].map do |name, section, key, checked|
      get admin_settings_path(section: section)
      form = Nokogiri::HTML(response.body).at_css('form[action="/admin/settings"]')
      inputs = form.css("input[name='instance_settings[#{key}]']")
      expect(inputs.map { |node| [node['type'], node['value']] }).to eq([%w[hidden false], %w[checkbox true]])
      pairs = form.css('input[type="hidden"]').map { |node| [node['name'], node['value']] }
      pairs << ["instance_settings[#{key}]", 'true'] if checked
      raw = URI.encode_www_form(pairs)
      post admin_settings_path, params: raw, headers: form_headers
      expect(response.status).to eq(303)
      expect(InstanceSetting.find_by!(key: key).value).to eq(checked)
      safe = pairs.map { |field, value| [field, field == 'authenticity_token' ? 'CSRF' : value] }
      response_row(name).merge('body' => URI.encode_www_form(safe), 'fields' => safe_fields)
    end
  end

  def corrupt_secret(key)
    InstanceSetting.connection.execute(
      InstanceSetting.sanitize_sql_array(
        ['UPDATE instance_settings SET encrypted_value = ? WHERE key = ?', 'not-valid-ciphertext', key]
      )
    )
    InstanceSettings::Resolver.reset!
    expect(InstanceSetting.find_by!(key: key).readable_value?).to be(false)
  end

  def partial_case
    allow_any_instance_of(InstanceSetting).to receive(:save!).and_wrap_original do |original, *args|
      raise IOError, 'synthetic persistence failure' if original.receiver.key == 'reverse_geocoding_rps'

      original.call(*args)
    end
    get admin_settings_path
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
    body = 'instance_settings%5Bstore_geodata%5D=false&instance_settings%5Breverse_geocoding_rps%5D=3.0'
    expect { patch admin_settings_path, params: body, headers: form_headers.merge('X-CSRF-Token' => token) }
      .to raise_error(IOError, 'synthetic persistence failure')
    expect(InstanceSetting.find_by!(key: 'store_geodata').value).to be(false)
    allow_any_instance_of(InstanceSetting).to receive(:save!).and_call_original
    { 'name' => 'partial_save', 'error' => 'IOError', 'fields' => safe_fields }
  end

  def registration_cases
    get settings_users_path
    form = Nokogiri::HTML(response.body)
                   .at_css('form[action="/settings/users/update_registration_settings"]')
    expect(form.css('input[name="registration_enabled"]').map { |node| [node['type'], node['value']] })
      .to eq([%w[hidden 0], %w[checkbox 1]])
    inputs = form.css('input[type="hidden"]').map { |node| [node['name'], node['value']] }
    checked = inputs + [%w[registration_enabled 1]]
    [['registration_checked', checked, true], ['registration_unchecked', inputs, false],
     ['registration_false', [%w[registration_enabled false]], false],
     ['registration_F', [%w[registration_enabled F]], false],
     ['registration_off', [%w[registration_enabled off]], false],
     ['registration_FALSE', [%w[registration_enabled FALSE]], false],
     ['registration_zero', [%w[registration_enabled 0]], false],
     ['registration_blank', [['registration_enabled', '']], nil],
     ['registration_nil', [], nil],
     ['registration_other', [%w[registration_enabled anything]], true]].map do |name, pairs, enabled|
      get settings_users_path
      token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
      if name.in?(%w[registration_checked registration_unchecked])
        post update_registration_settings_settings_users_path, params: URI.encode_www_form(pairs), headers: form_headers
      else
        patch update_registration_settings_settings_users_path, params: URI.encode_www_form(pairs),
                                                              headers: form_headers.merge('X-CSRF-Token' => token)
      end
      expect(response.status).to eq(302)
      expect(Rails.cache.read('dawarich/registration_enabled')).to eq(enabled)
      safe = pairs.map { |key, value| [key, key == 'authenticity_token' ? 'CSRF' : value] }
      response_row(name).merge('cache_value' => enabled, 'body' => URI.encode_www_form(safe))
    end
  end

  def home_policy(name, enabled)
    links = Nokogiri::HTML(response.body).css('a[href="/users/sign_up"]')
    expect(links.any?).to eq(enabled)
    { 'name' => name, 'status' => response.status, 'signup' => links.any? }
  end

  def background_body(name, user, value)
    if user.settings.is_a?(Hash)
      get settings_background_jobs_path
      @background_token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
    end
    body = URI.encode_www_form([['settings[visits_suggestions_enabled]', value]])
    patch settings_background_jobs_path, params: body, headers: form_headers.merge('X-CSRF-Token' => @background_token)
    expect(response.status).to eq(302)
    response_row(name).merge('body' => body, 'after' => user.reload.settings)
  end

  def save_cases(cases)
    cases.each do |capture|
      bytes = Oj.dump(capture, mode: :strict, float_precision: 0, indent: 2)
      expect(bytes.include?(secret)).to be(false)
      File.write(dir.join("#{capture.fetch('name')}.json"), "#{bytes.rstrip}\n")
    end
  end

  it 'captures instance normalization pinning encryption and partial saves' do
    cases = instance_cases
    expect(cases.map { |capture| capture.fetch('name') }).to eq(
      %w[all_registry checked_https unchecked_https checked_store unchecked_store defaults secret_untouched
         secret_clear secret_replace secret_unreadable photon_normalized komoot_cleared komoot_pinned
         chibigeo_missing chibigeo_valid invalid_no_writes mixed_pinned partial_save publish_failure]
    )
    expect(cases.find { |capture| capture['name'] == 'mixed_pinned' }.dig('fields', 'photon_api_host'))
      .to include('pinned' => true, 'stored' => false)
    expect(cases.find do |capture|
      capture['name'] == 'partial_save'
    end.dig('fields', 'store_geodata', 'value')).to be(false)
    save_cases(cases)
  end

  it 'captures registration casts and background merge callbacks' do
    cases = setting_cases
    expect(cases.map { |capture| capture.fetch('name') }).to eq(
      %w[registration_checked registration_unchecked registration_false registration_F registration_off
         registration_FALSE registration_zero registration_blank registration_nil registration_other
         self_hosted_disabled cloud_disabled background_query_true background_query_false
         background_override background_body missing_background_settings background_timezone_callback
         background_nonobject background_cloud background_guest]
    )
    background = cases.find { |capture| capture['name'] == 'background_query_true' }
    expect(background.fetch('after')).to include('unrelated' => 'retained',
                                                 'immich_url' => 'https://immich.example.invalid')
    expect(background.fetch('admin')).to be(false)
    save_cases(cases)
  end
  it 'legacy registration oracle preserves false and nil without the singleton table' do
    expect(PhoenixSchema.table?('registration_setting')).to be(false)
    [false, nil].each do |value|
      DawarichSettings.set_registration_enabled(value)
      expect(DawarichSettings.registration_enabled?).to eq(value)
      expect(Rails.cache.read('dawarich/registration_enabled')).to eq(value)
      key = Rails.cache.send(:normalize_key, 'dawarich/registration_enabled', {})
      bytes = Rails.cache.redis.with { |redis| redis.get(key) }
      expect(bytes).to be_present
      expect(Rails.cache.send(:deserialize_entry, bytes).value).to eq(value)
    end
  end

  context 'native interoperability', :a10b_non_transactional do
    self.use_transactional_tests = false

    before do
      @prior_cache = Rails.cache
      @native_cache = ActiveSupport::Cache::RedisCacheStore.new(url: "#{ENV.fetch('REDIS_URL')}/0", driver: :ruby)
      Rails.cache = @native_cache
    end

    after do
      Rails.cache = @prior_cache
      @native_cache.redis.with(&:close)
    end

    it 'Rails reads native cache booleans and decrypts native instance secrets' do
      synthetic_user(15_911, admin: true)
      key = 'dawarich/registration_enabled'
      expect(Rails.cache.redis.with do |redis|
        redis.connection.values_at(:port,
                                   :db) == [URI(ENV.fetch('REDIS_URL')).port, 0]
      end).to be(true), 'Rails cache must use allocated Redis DB0'
      owned_secret = !InstanceSetting.exists?(key: 'geoapify_api_key')
      expect(owned_secret).to be(true)
      [true, false, nil].each do |value|
        result = phoenix(<<~ELIXIR, 'A10B_CACHE_VALUE' => JSON.generate(value))
          value = Jason.decode!(System.fetch_env!("A10B_CACHE_VALUE"))
          :ok = Dawarich.Auth.RegistrationSetting.put(value)
          IO.puts(Jason.encode!(%{saved: true}))
        ELIXIR
        expect(result.fetch('saved')).to be(true)
        bytes = Rails.cache.redis.with { |redis| redis.get(key) }
        expect(bytes.nil?).to be(false), 'native cache entry absent in Rails Redis connection'
        expect(Rails.cache.send(:deserialize_entry, bytes).value).to eq(value)
        expect(Rails.cache.read(key)).to eq(value)
        Rails.cache.write(key, value)
        result = phoenix(<<~ELIXIR)
          {:ok, value} = Dawarich.Auth.RegistrationSetting.fetch()
          IO.puts(Jason.encode!(%{value: value}))
        ELIXIR
        expect(result.fetch('value')).to eq(value)
      end
      config = Rails.application.config.active_record.encryption
      encryption = { 'OTP_ENCRYPTION_PRIMARY_KEY' => config.primary_key,
                     'OTP_ENCRYPTION_DETERMINISTIC_KEY' => config.deterministic_key,
                     'OTP_ENCRYPTION_KEY_DERIVATION_SALT' => config.key_derivation_salt,
                     'A10B_SECRET' => secret }
      result = phoenix(<<~ELIXIR, encryption)
        actor = Dawarich.Accounts.get(15911)
        context = %{self_hosted: true, oidc: false, locale: "en", env: System.get_env()}
        {:ok, []} = Dawarich.Admin.InstanceWrites.call(actor,
          %{"instance_settings" => [{"geoapify_api_key", System.fetch_env!("A10B_SECRET")}]}, context)
        IO.puts(Jason.encode!(%{saved: true}))
      ELIXIR
      expect(result.fetch('saved')).to be(true)
      record = InstanceSetting.find_by!(key: 'geoapify_api_key')
      expect(record.value == secret).to be(true)
      expect(record[:value]).to be_nil
      record.value = secret
      record.save!
      InstanceSettings::Resolver.reset!
      result = phoenix(<<~ELIXIR, encryption)
        {:ok, key} = Dawarich.ActiveRecordEncryption.key()
        [[ciphertext]] = Dawarich.Repo.query!("SELECT encrypted_value FROM instance_settings WHERE key='geoapify_api_key'", [], log: false).rows
        {:ok, plaintext} = Dawarich.ActiveRecordEncryption.decrypt(ciphertext, key)
        IO.puts(Jason.encode!(%{matches: plaintext == System.fetch_env!("A10B_SECRET")}))
      ELIXIR
      expect(result.fetch('matches')).to be(true)
    ensure
      User.unscoped.where(id: 15_911).delete_all
      InstanceSetting.where(key: 'geoapify_api_key').delete_all if owned_secret
      Rails.cache.delete(key) if key
    end
  end
end
