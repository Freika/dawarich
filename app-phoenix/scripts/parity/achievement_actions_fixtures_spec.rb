# frozen_string_literal: true

require 'rails_helper'
require 'open3'

RSpec.describe 'Phoenix fixtures: achievement sharing actions', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/achievement_actions') }
  let(:now) { Time.utc(2026, 10, 4, 10) }
  let(:uuid) { 'a10c0000-0000-4000-8000-000000000001' }

  around do |example|
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    travel_to(now) { example.run }
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    allow(SecureRandom).to receive(:uuid).and_return(uuid)
  end

  def synthetic_user(id, locale: 'en')
    create(:user, id:, email: "a10c-#{id}@example.invalid", password: 'a10c-synthetic-password',
                  created_at: now - 1.day, updated_at: now - 1.day,
                  settings: { 'locale' => locale, 'timezone' => 'Europe/Berlin', 'onboarding_completed' => true })
  end

  def login(actor, locale: 'en')
    reset!
    actor&.update_columns(settings: actor.settings.merge('locale' => locale))
    sign_in actor.reload if actor
    get actor ? achievements_path : new_user_session_path, params: { locale: }
    expect(response.status).to eq(200)
    Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
  end

  def safe_row(progress)
    return unless progress

    progress.reload
    { 'user_id' => progress.user_id, 'key' => progress.achievement_key, 'state' => progress.state,
      'enabled' => progress.sharing_enabled, 'uuid' => progress.sharing_uuid,
      'created_at' => progress.created_at.utc.iso8601(6), 'updated_at' => progress.updated_at.utc.iso8601(6) }
  end

  def request_case(name, actor, key: 'country_de', params: {}, json: true, method: :patch,
                   referer: nil, locale: 'en', token: nil)
    token ||= login(actor, locale:)
    path = toggle_sharing_achievement_path(key)
    headers = json ? { 'X-CSRF-Token' => token } : {}
    params = params.merge(authenticity_token: token) unless json
    headers['Content-Type'] = json ? 'application/json' : 'application/x-www-form-urlencoded'
    headers['Accept'] = json ? 'application/json' : 'text/html'
    headers['HTTP_REFERER'] = referer if referer
    raw = json ? ActiveSupport::JSON.encode(params) : URI.encode_www_form(params)
    before = safe_row(actor&.achievement_progresses&.find_by(achievement_key: key))
    error = nil
    begin
      public_send(method, path, params: raw, headers:)
    rescue ActiveRecord::NotNullViolation => e
      error = e.class.name
    end
    safe_params = json ? params : params.merge(authenticity_token: 'CSRF')
    raw = raw.gsub(URI.encode_www_form_component(token), 'CSRF').gsub(token, 'CSRF')
    record = { 'name' => name, 'method' => method.to_s.upcase, 'path' => path, 'params' => safe_params,
               'request_body' => raw, 'content_type' => headers['Content-Type'],
               'json_request' => json, 'locale' => locale, 'referer' => referer, 'before' => before,
               'after' => safe_row(actor&.achievement_progresses&.find_by(achievement_key: key)) }
    return record.merge('error' => error) if error

    record.merge('status' => response.status, 'location' => response.location,
                 'headers' => response.headers.slice('Content-Type', 'Cache-Control'),
                 'body' => response.media_type == 'application/json' ? response.body : '',
                 'json' => response.media_type == 'application/json' ? response.parsed_body : nil,
                 'flash' => flash.to_hash.stringify_keys)
  end

  def sharing_cases
    actor = synthetic_user(41_001)
    foreign = synthetic_user(41_002)
    foreign_progress = create(:achievement_progress, id: 41_002, user: foreign, achievement_key: 'country_de',
                                                    sharing_enabled: true,
                                                    sharing_uuid: 'a10c0000-0000-4000-8000-000000000002',
                                                    state: { 'earned' => { 'FR' => '2026-07-19' } },
                                                    created_at: now - 1.day, updated_at: now - 1.day)
    other_before = safe_row(foreign_progress)
    progress = create(:achievement_progress, id: 41_001, user: actor, achievement_key: 'country_de',
                                           state: { 'earned' => { 'DE' => '2026-07-19' } },
                                           created_at: now - 1.day, updated_at: now - 1.day)
    values = [['json_true', true, true], ['json_false', false, false], ['zero', 0, false], ['one', 1, true],
              ['negative', -1, true], ['false_string', 'false', false], ['false_upper', 'FALSE', false],
              ['false_letter', 'f', false], ['false_letter_upper', 'F', false], ['zero_string', '0', false],
              ['off', 'off', false], ['off_upper', 'OFF', false], ['true_string', 'true', true],
              ['arbitrary', 'not-a-boolean', true], ['empty', '', nil], ['null', nil, nil]]
    results = values.map do |name, input, expected|
      progress.update_columns(sharing_enabled: false, sharing_uuid: nil, updated_at: now - 1.day)
      row = request_case(name, actor, params: { enabled: input })
      if expected.nil?
        expect(row['error']).to eq('ActiveRecord::NotNullViolation')
        expect(row['after']).to eq(row['before'])
      else
        expect(row['status']).to eq(200)
        expect(row.dig('after', 'enabled')).to eq(expected)
        expect(row.dig('after', 'uuid')).to eq(uuid)
        expect(row.dig('json', 'url')).to eq(expected ? "http://www.example.com/shared/achievements/#{uuid}" : nil)
        expect(row.dig('after', 'state')).to eq(progress.state)
      end
      row
    end
    results.concat(toggle_cases(actor, progress))
    results.concat(html_cases(actor))
    %w[border_hopper country_fr].each_with_index do |key, index|
      allow(SecureRandom).to receive(:uuid).and_return(format('a10c0000-0000-4000-8000-%012d', index + 3))
      row = request_case(key == 'border_hopper' ? 'world' : 'flat', actor, key:, params: { enabled: true })
      expect(row['status']).to eq(200)
      expect(row.dig('after', 'state')).to eq({})
      results << row
    end
    unknown = request_case('unknown', actor, key: 'explorer_atlantis')
    expect(unknown['status']).to eq(404)
    expect(unknown['after']).to be_nil
    results << unknown
    results.concat(auth_cases(actor))
    expect(safe_row(foreign_progress)).to eq(other_before)
    results
  end

  def toggle_cases(actor, progress)
    progress.update_columns(sharing_enabled: false, sharing_uuid: uuid)
    %w[absent_enable absent_disable].zip([true, false]).map do |name, expected|
      row = request_case(name, actor)
      expect(row.dig('json', 'enabled')).to eq(expected)
      expect(row.dig('after', 'uuid')).to eq(uuid)
      row
    end
  end

  def html_cases(actor)
    scenarios = [['form_override', :post, { _method: 'patch', enabled: 'true' }, nil, 'en'],
                 ['direct_html', :patch, { enabled: 'false' }, nil, 'de'],
                 ['external_referer', :patch, {}, 'https://outside.example.invalid/collection', 'en'],
                 ['local_referer', :patch, {}, 'http://www.example.com/achievements/country_de?page=2', 'de']]
    scenarios.map do |name, method, params, referer, locale|
      row = request_case(name, actor, params:, json: false, method:, referer:, locale:)
      expect(row['status']).to eq(302)
      destination = name == 'external_referer' ? nil : referer
      expect(row['location']).to eq(destination || 'http://www.example.com/achievements/country_de')
      expect(row['flash']).to eq({})
      row
    end
  end

  def auth_cases(actor)
    rows = %w[en de es fr pl ca zh].map do |locale|
      row = request_case("guest_#{locale}", nil, locale:)
      expect(row['status']).to eq(401)
      expect(row.dig('json', 'error')).to eq(I18n.t('devise.failure.unauthenticated', locale:))
      row
    end
    token = login(actor)
    actor.update!(password: 'a10c-replaced-synthetic-password')
    row = request_case('stale_cookie', actor, token:)
    expect(row['status']).to eq(401)
    expect(row['after']).to eq(row['before'])
    rows << row
    reset!
    cookies[Rails.application.config.session_options.fetch(:key)] = 'a10c-invalid-synthetic-cookie'
    get new_user_session_path
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
    row = request_case('invalid_cookie', nil, token:)
    expect(row['status']).to eq(401)
    rows << row
    row = request_case('guest_html_de', nil, json: false, locale: 'de')
    expect(row['status']).to eq(302)
    expect(row['flash']['alert']).to eq(I18n.t('devise.failure.unauthenticated', locale: :de))
    rows << row
    rows
  end

  def collision_cases
    actor = synthetic_user(41_001)
    foreign = synthetic_user(41_002)
    other = create(:achievement_progress, id: 41_002, user: foreign, achievement_key: 'country_de',
                                         sharing_enabled: false, created_at: now - 1.day, updated_at: now - 1.day)
    other_before = safe_row(other)
    token = login(actor)
    collision = nil
    winner = nil
    allow_any_instance_of(ActiveRecord::Relation).to receive(:find_or_create_by!).and_wrap_original do |original, attrs|
      if attrs == { achievement_key: 'country_de' } && winner.nil?
        winner = create(:achievement_progress, id: 41_001, user: actor, achievement_key: 'country_de',
                                              state: { 'earned' => { 'DE' => '2026-07-19' } },
                                              sharing_uuid: uuid, created_at: now - 1.day, updated_at: now - 1.day)
        begin
          Achievements::Progress.transaction(requires_new: true) do
            Achievements::Progress.insert!({ id: 41_003, user_id: actor.id, achievement_key: 'country_de',
                                             created_at: now, updated_at: now })
          end
        rescue ActiveRecord::RecordNotUnique => e
          collision = e.class.name
          raise
        end
      else
        original.call(attrs)
      end
    end
    responses = [request_case('collision_enable', actor, params: { enabled: true }, token:)]
    responses << request_case('repeat_disable', actor, params: { enabled: false })
    responses << request_case('repeat_enable', actor, params: { enabled: true })
    expect(actor.achievement_progresses.where(achievement_key: 'country_de').count).to eq(1)
    { 'collision' => collision, 'responses' => responses, 'winner' => safe_row(winner),
      'foreign_unchanged' => safe_row(other) == other_before }
  end

  def save_cases(name, cases)
    bytes = "#{Oj.dump(cases, mode: :strict, float_precision: 0, indent: 2).rstrip}\n"
    path = dir.join("#{name}.json")
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(dir)
      File.write(path, bytes)
    else
      expect(path.read).to eq(bytes)
    end
  end

  it 'captures owner sharing HTML JSON and boolean outcomes' do
    cases = sharing_cases
    expect(cases.map { |row| row.fetch('name') }).to include('json_true', 'json_false', 'empty', 'null',
                                                             'form_override', 'world', 'flat', 'invalid_cookie')
    expect(cases.find { |row| row['name'] == 'json_true' }.dig('json', 'enabled')).to be(true)
    expect(cases.find { |row| row['name'] == 'json_false' }.dig('json', 'url')).to be_nil
    %w[empty null].each do |name|
      expect(cases.find { |row| row['name'] == name }.fetch('error')).to eq('ActiveRecord::NotNullViolation')
    end
    save_cases('responses', cases)
  end

  it 'captures first carrier collision and stable sharing uuid' do
    cases = collision_cases
    expect(cases.fetch('collision')).to eq('ActiveRecord::RecordNotUnique')
    expect(cases.fetch('responses').map { |row| row.dig('json', 'uuid') }.uniq).to eq([uuid])
    expect(cases.fetch('responses').map { |row| row.dig('json', 'enabled') }).to eq([true, false, true])
    expect(cases.fetch('winner').fetch('state')).to eq('earned' => { 'DE' => '2026-07-19' })
    expect(cases.fetch('winner').fetch('created_at')).to eq((now - 1.day).iso8601(6))
    expect(cases.fetch('foreign_unchanged')).to be(true)
    save_cases('collision', cases)
  end

  def phoenix(code, data)
    native_env = {
      'PATH' => "#{Dir.home}/.asdf/shims:#{ENV.fetch('PATH')}",
      'ASDF_ERLANG_VERSION' => '27.3.4.1', 'ASDF_ELIXIR_VERSION' => '1.18.3-otp-27',
      'MIX_ENV' => 'test', 'DATABASE_HOST' => '127.0.0.1',
      'PHOENIX_TEST_DATABASE' => ENV.fetch('DATABASE_NAME'),
      'PHOENIX_TEST_REDIS_URL' => ENV.fetch('PHOENIX_TEST_REDIS_URL'),
      'A10C_DATA' => JSON.generate(data)
    }
    bootstrap = <<~ELIXIR
      for app <- [:ecto_sql, :postgrex, :crypto], do: Application.ensure_all_started(app)
      {:ok, _} = Dawarich.Repo.start_link(database: System.fetch_env!("PHOENIX_TEST_DATABASE"),
        pool: DBConnection.ConnectionPool, pool_size: 1, prepare: :unnamed)
      data = Jason.decode!(System.fetch_env!("A10C_DATA"))
    ELIXIR
    output, status = Open3.capture2e(native_env, 'mix', 'run', '--no-start', '-e', bootstrap + code,
                                     chdir: Rails.root.join('app-phoenix').to_s)
    expect(status.success?).to be(true), 'native interoperability failed; output withheld'
    JSON.parse(output.lines.last)
  end

  def native_sharing(enabled)
    phoenix(<<~ELIXIR, enabled.nil? ? {} : { 'enabled' => enabled })
      {:ok, result} = Dawarich.Achievements.Sharing.call(Dawarich.Repo, 45101, "country_de",
        data, %{clock: fn -> ~U[2026-10-04 10:00:00Z] end})
      IO.puts(Jason.encode!(result))
    ELIXIR
  end

  context 'native interoperability' do
    self.use_transactional_tests = false

    before do
      Achievements::UnlockEvent.where(user_id: [45_101, 45_102]).delete_all
      Achievements::Progress.where(user_id: [45_101, 45_102]).delete_all
      User.unscoped.where(id: [45_101, 45_102]).delete_all
    end

    it 'Rails consumes native sharing carrier without state loss' do
      actor = synthetic_user(45_101)
      foreign = synthetic_user(45_102)
      state = { 'synthetic' => 'preserve' }
      carrier = create(:achievement_progress, user: actor, achievement_key: 'country_de', state:,
                                             sharing_uuid: 'a10c0000-0000-4000-8000-000000045101',
                                             created_at: now - 1.day, updated_at: now - 1.day)
      other = create(:achievement_progress, user: foreign, achievement_key: 'country_de', state:,
                                           sharing_uuid: 'a10c0000-0000-4000-8000-000000045102')
      original = carrier.attributes.slice('state', 'created_at', 'sharing_uuid')
      foreign_original = other.attributes
      result = native_sharing(true)
      expect(result).to eq('enabled' => true, 'uuid' => carrier.sharing_uuid)
      expect(carrier.reload.attributes.slice(*original.keys)).to eq(original)
      expect(carrier.updated_at).to eq(now)
      get shared_achievement_path(carrier.sharing_uuid)
      expect(response.status).to eq(200)
      row = request_case('native_interop', actor, params: { enabled: false })
      expect(row.fetch('json')).to include('enabled' => false, 'uuid' => carrier.sharing_uuid, 'url' => nil)
      expect(carrier.reload.state).to eq(state)
      expect(native_sharing(nil)).to eq('enabled' => true, 'uuid' => carrier.sharing_uuid)
      expect(carrier.reload.attributes.slice(*original.keys)).to eq(original)
      expect(other.reload.attributes).to eq(foreign_original)
    ensure
      Achievements::UnlockEvent.where(user_id: [45_101, 45_102]).delete_all
      Achievements::Progress.where(user_id: [45_101, 45_102]).delete_all
      User.unscoped.where(id: [45_101, 45_102]).delete_all
    end
  end
end
