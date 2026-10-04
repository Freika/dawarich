# frozen_string_literal: true

require 'rails_helper'
require 'open3'

RSpec.describe 'Phoenix fixtures: admin mutations', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/admin_mutations') }
  let(:now) { Time.utc(2026, 10, 4, 10) }
  let(:password) { 'a10b-synthetic-password' }

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
    travel_to(now) { example.run }
  ensure
    Rails.cache.delete('dawarich/registration_enabled')
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    allow(Devise).to receive(:mailer_sender).and_return('synthetic@example.invalid')
    FileUtils.mkdir_p(dir)
  end

  def credential_cases
    actor = synthetic_user(11_001, admin: true)
    target = synthetic_user(11_002)
    results = create_cases(actor)
    results.concat(update_cases(actor, target))
    results.concat(role_cases(actor, target))
    login(actor)
    %w[create update].each do |action|
      before = User.order(:id).pluck(:id, :settings, :updated_at)
      clear_enqueued_jobs
      body = 'commit=Save%20changes&utf8=%E2%9C%93'
      path = action == 'create' ? settings_users_path : settings_user_path(target)
      public_send(action == 'create' ? :post : :patch, path, params: body,
                  headers: { 'Content-Type' => 'application/x-www-form-urlencoded' })
      expect(response.status).to eq(400)
      expect(User.order(:id).pluck(:id, :settings, :updated_at)).to eq(before)
      expect(enqueued_jobs).to be_empty
      results << { 'name' => "missing_user_#{action}", 'status' => response.status,
                   'body' => body, 'error' => 'ActionController::ParameterMissing', 'unchanged' => true }
    end
    results
  end

  def retained_cases
    actor = synthetic_user(11_001, admin: true)
    owner = synthetic_user(11_002)
    member = synthetic_user(11_003)
    family = create(:family, id: 11_001, creator: owner, name: 'Synthetic A10b family')
    create(:family_membership, user: owner, family: family, role: :owner)
    create(:family_membership, user: member, family: family, role: :member)
    results = [deletion_case('family_refused', actor, owner, status: 303, deleted: false)]
    results << deletion_case('member_deleted', actor, member)
    results << deletion_case('sole_owner_deleted', actor, owner)
    creator = synthetic_user(11_004)
    create(:family, id: 11_002, creator: creator, name: 'Synthetic creator only')
    results << deletion_case('creator_only_deleted', actor, creator)
    winner = synthetic_user(11_005)
    unchanged = winner.updated_at
    first = winner.mark_as_deleted_atomically!
    second = User.unscoped.find(winner.id).mark_as_deleted_atomically!
    expect([first, second, winner.reload.updated_at == unchanged]).to eq([true, false, true])
    results << { 'name' => 'conditional_winner', 'first' => first, 'second' => second,
                 'updated_at_unchanged' => winner.updated_at == unchanged }
    results << missing_case('repeated_delete', actor, member.id)
    results << missing_case('missing_delete', actor, 11_999)
    results << missing_case('deleted_delete', actor, winner.id)
    failure = synthetic_user(11_006)
    login(actor)
    timestamp = failure.updated_at
    allow(Users::DestroyJob).to receive(:perform_later).and_raise(RuntimeError, 'synthetic enqueue failure')
    expect { delete settings_user_path(failure) }.to raise_error(RuntimeError, 'synthetic enqueue failure')
    expect(failure.reload.deleted?).to be(true)
    results << { 'name' => 'enqueue_failure', 'error' => 'RuntimeError', 'deleted' => failure.deleted?,
                 'updated_at_unchanged' => failure.updated_at == timestamp }
    allow(Users::DestroyJob).to receive(:perform_later).and_call_original
    results.concat(security_cases(actor))
    results.concat(refusal_cases(actor))
    login(actor)
    clear_enqueued_jobs
    get export_settings_users_path
    results << response_row('export').merge('jobs' => safe_jobs)
    expect(response).to redirect_to(exports_path)
    post import_settings_users_path
    results << response_row('import_missing')
    expect(response).to redirect_to(edit_user_registration_path)
    results << deletion_case('last_admin_deleted', actor, actor)
    order = %w[family_refused member_deleted sole_owner_deleted creator_only_deleted last_admin_deleted
               conditional_winner repeated_delete missing_delete deleted_delete enqueue_failure rotate_key
               reset_password reset_mail_failure registration_on registration_off cloud_create cloud_guest
               nonadmin_create guest_create export import_missing]
    results.sort_by { |capture| order.index(capture.fetch('name')) }
  end

  def synthetic_user(id, **attributes)
    create(:user, id: id, email: "a10b-#{id}@example.invalid", password: password,
                  created_at: now - 1.day, updated_at: now - 1.day, changelog_consent: :declined,
                  settings: { 'locale' => 'en', 'onboarding_completed' => true }, **attributes)
  end

  def login(actor, locale: 'en')
    reset!
    actor.update_columns(settings: actor.settings.merge('locale' => locale))
    sign_in actor.reload
    get settings_users_path
    expect(response.status).to eq(200)
  end

  def response_row(name)
    { 'name' => name, 'status' => response.status,
      'location' => response.location && URI(response.location).path,
      'headers' => response.headers.slice('Content-Type', 'Cache-Control'),
      'flash' => flash.to_hash.stringify_keys }
  end

  def safe_row(user)
    user.reload
    { 'id' => user.id, 'email' => user.email, 'admin' => user.admin, 'status' => user.status,
      'plan' => user.plan, 'active_until' => user.active_until&.utc&.iso8601(6), 'settings' => user.settings,
      'theme' => user.theme, 'created_at' => user.created_at.utc.iso8601(6),
      'updated_at' => user.updated_at.utc.iso8601(6), 'reset_token_present' => user.reset_password_token.present?,
      'reset_sent_at' => user.reset_password_sent_at&.utc&.iso8601(6),
      'unlock_token_present' => user.unlock_token.present?, 'failed_attempts' => user.failed_attempts,
      'failed_otp_attempts' => user.failed_otp_attempts, 'otp_locked_at' => user.otp_locked_at&.utc&.iso8601(6) }
  end

  def safe_jobs
    enqueued_jobs.map do |job|
      { 'class' => job.fetch(:job).name,
        'arguments' => job.fetch(:job) == Users::DestroyJob ? job.fetch(:args) : [] }
    end
  end

  def create_cases(actor)
    allow(User).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap do |user|
        if user.email.to_s.strip.downcase.start_with?('a10b-new')
          @create_id = (@create_id || 11_100) + 1
          user.id = @create_id
        end
      end
    end
    specs = [
      ['create_en', ' A10B-NEW-EN@example.invalid ', password, 'en', 302],
      ['create_de', 'a10b-new-de@example.invalid', password, 'de', 302],
      ['duplicate_en', actor.email, password, 'en', 303],
      ['duplicate_de', actor.email, password, 'de', 303],
      ['invalid_email', 'invalid', password, 'en', 303],
      ['blank_email', '', password, 'en', 303],
      ['short_password', 'a10b-new-short@example.invalid', 'short', 'en', 303],
      ['blank_password', 'a10b-new-blank@example.invalid', '', 'en', 303],
      ['min_password', 'a10b-new-min@example.invalid', 'x' * 12, 'en', 302],
      ['max_password', 'a10b-new-max@example.invalid', 'x' * 128, 'en', 302],
      ['long_password', 'a10b-new-long@example.invalid', 'x' * 129, 'en', 303],
      ['unicode_password', 'a10b-new-unicode@example.invalid', 'é' * 12, 'en', 302],
      ['bcrypt_72_bytes', 'a10b-new-bcrypt@example.invalid', "#{'x' * 72}suffix", 'en', 302]
    ]
    specs.map do |name, email, value, locale, status|
      login(actor, locale: locale)
      before_count = User.count
      post settings_users_path, params: { user: { email: email, password: value, admin: '1', status: 'inactive' } }
      expect(response.status).to eq(status)
      capture = response_row(name).merge('locale' => locale, 'rows_added' => User.count - before_count)
      expect(capture['rows_added']).to eq(status == 302 ? 1 : 0)
      if status == 302
        user = User.find_by!(email: email.strip.downcase)
        expect(user.valid_password?(value)).to be(true)
        expect(user.api_key.match?(/\A[0-9a-f]{64}\z/)).to be(true)
        expect(user).to have_attributes(admin: false, status: 'active', plan: 'pro', active_until: now + 1000.years)
        capture.merge!('after' => safe_row(user), 'password_valid' => true, 'api_key_64_hex' => true)
        if name == 'bcrypt_72_bytes'
          expect(user.valid_password?("#{'x' * 72}other")).to be(true)
          capture['same_first_72_bytes_valid'] = true
        end
      end
      capture
    end
  end

  def update_case(name, actor, target, params, status: 302)
    login(actor)
    before = safe_row(target)
    hash = target.encrypted_password
    patch settings_user_path(target), params: { user: params }
    expect(response.status).to eq(status)
    response_row(name).merge('before' => before, 'after' => safe_row(target),
                             'password_unchanged' => target.encrypted_password == hash)
  end

  def update_cases(actor, target)
    target.update_columns(reset_password_token: 'synthetic-digest', reset_password_sent_at: now - 1.hour,
                          unlock_token: 'synthetic-unlock', failed_attempts: 3, failed_otp_attempts: 2,
                          otp_locked_at: now - 1.minute)
    changes = { email: ' UPDATED@example.invalid ', password: 'a10b-changed-password', status: 'inactive' }
    results = [update_case('update_credentials', actor, target, changes)]
    expect(target.valid_password?('a10b-changed-password')).to be(true)
    expect(target.email).to eq('updated@example.invalid')
    results << update_case('update_invalid', actor, target, { email: '' }, status: 303)
    [['update_blank', ''], ['update_spaces', " \t\n"], ['update_nil', nil]].each do |name, value|
      results << update_case(name, actor, target, { password: value })
    end
    target.update_columns(status: :active, updated_at: now - 1.day,
                          settings: { 'locale' => 'en', 'timezone' => 'UTC', 'onboarding_completed' => true })
    before = target.reload.attributes
    capture = update_case('noop_roles', actor, target, { admin: '0', status: 'active' })
    expect(target.reload.attributes).to eq(before)
    expect(target.updated_at).to eq(now - 1.day)
    results << capture
    results << update_case('target_password', actor, target, { password: 'a10b-target-password' })
    get settings_users_path
    expect(response.status).to eq(200)
    results.last['actor_identity_valid'] = true
    old_salt = actor.authenticatable_salt
    results << update_case('self_password', actor, actor, { password: 'a10b-actor-password' })
    salt = request.session['warden.user.user.key']&.last
    results.last['repaired_identity'] = salt != old_salt
    get settings_users_path
    expect(response).to redirect_to(new_user_session_path)
    results.last['old_identity_valid'] = false
    results
  end

  def role_cases(actor, target)
    User.where(admin: true).where.not(id: actor.id).update_all(admin: false)
    deleted_admin = synthetic_user(11_003, admin: true)
    deleted_admin.update_columns(deleted_at: now)
    results = []
    [['last_admin_role', { admin: '0' }], ['last_admin_status', { status: 'inactive' }],
     ['last_admin_both', { admin: '0', status: 'inactive' }],
     ['last_admin_integer_status', { status: 1 }]].each do |name, params|
      capture = update_case(name, actor, actor, params)
      expect(actor).to have_attributes(admin: true, status: 'active')
      expect(capture['flash']['alert']).to be_present
      results << capture
    end
    results << update_case('last_admin_false', actor, actor, { admin: 'false' })
    expect(actor.admin).to be(false)
    actor.update_columns(admin: true)
    target.update_columns(admin: true)
    results << update_case('second_admin_demote', actor, target, { admin: '0' })
    expect(target.admin).to be(false)
    target.update_columns(admin: true)
    results << update_case('second_admin_disable', actor, target, { status: 'inactive' })
    expect(target.status).to eq('inactive')
    login(actor)
    expect { patch settings_user_path(target), params: { user: { status: 'unknown' } } }
      .to raise_error(ArgumentError, "'unknown' is not a valid status")
    results << { 'name' => 'invalid_status', 'error' => 'ArgumentError', 'after' => safe_row(target) }
    target.update_columns(settings: { 'immich_url' => 'https://immich.example.invalid///',
                                     'photoprism_url' => 'https://photos.example.invalid/',
                                     'maps' => { 'url' => ' https://maps.example.invalid ' } })
    results << update_case('sanitize_update', actor, target, { email: target.email })
    expect(target.settings).to eq('immich_url' => 'https://immich.example.invalid',
                                  'photoprism_url' => 'https://photos.example.invalid',
                                  'maps' => { 'url' => 'https://maps.example.invalid' })
    order = %w[last_admin_role last_admin_status last_admin_both last_admin_false last_admin_integer_status
               second_admin_demote second_admin_disable invalid_status sanitize_update]
    results.sort_by { |capture| order.index(capture.fetch('name')) }
  end

  def deletion_case(name, actor, target, status: 302, deleted: true)
    login(actor)
    clear_enqueued_jobs
    timestamp = target.updated_at
    delete settings_user_path(target)
    expect(response.status).to eq(status)
    expect(target.reload.deleted?).to be(deleted)
    capture = response_row(name).merge('deleted' => target.deleted?, 'jobs' => safe_jobs,
                                       'updated_at_unchanged' => target.updated_at == timestamp)
    expect(capture['jobs']).to eq(deleted ? [{ 'class' => 'Users::DestroyJob', 'arguments' => [target.id] }] : [])
    capture
  end

  def missing_case(name, actor, id)
    login(actor)
    clear_enqueued_jobs
    delete settings_user_path(id)
    expect(response.status).to eq(404)
    { 'name' => name, 'status' => response.status, 'jobs' => safe_jobs }
  end

  def security_cases(actor)
    target = synthetic_user(11_007)
    login(actor)
    key = target.api_key
    actor_key = actor.api_key
    post regenerate_api_key_settings_user_path(target)
    expect(response.status).to eq(302)
    expect(target.reload.api_key != key && target.api_key.match?(/\A[0-9a-f]{64}\z/)).to be(true)
    expect(actor.reload.api_key == actor_key).to be(true)
    results = [response_row('rotate_key').merge('target_changed' => true, 'actor_unchanged' => true)]
    clear_enqueued_jobs
    ActionMailer::Base.deliveries.clear
    post send_password_reset_settings_user_path(target)
    expect(response.status).to eq(302)
    expect(target.reload.reset_password_token.present?).to be(true)
    expect(target.reset_password_sent_at).to eq(now)
    mail = ActionMailer::Base.deliveries.last
    expect(mail.present?).to be(true)
    html = mail.html_part ? mail.html_part.body.decoded : mail.body.decoded
    link = Nokogiri::HTML(html).css('a').find { |node| node['href'].include?('reset_password_token=') }
    raw = URI.decode_www_form(URI(link['href']).query).to_h.fetch('reset_password_token')
    digest = Devise.token_generator.digest(User, :reset_password_token, raw)
    expect(target.reset_password_token == digest).to be(true)
    results << response_row('reset_password').merge('token_digest_valid' => true, 'after' => safe_row(target),
                                                    'jobs' => safe_jobs, 'delivery' => 'synchronous')
    target.update_columns(reset_password_token: nil, reset_password_sent_at: nil)
    allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_now)
      .and_raise(RuntimeError, 'synthetic mail failure')
    expect do
      post send_password_reset_settings_user_path(target)
    end.to raise_error(RuntimeError, 'synthetic mail failure')
    expect(target.reload.reset_password_token.present?).to be(true)
    results << { 'name' => 'reset_mail_failure', 'error' => 'RuntimeError', 'after' => safe_row(target) }
    allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_now).and_call_original
    [['registration_on', '1', true], ['registration_off', '0', false]].each do |name, value, enabled|
      patch update_registration_settings_settings_users_path, params: { registration_enabled: value }
      expect(DawarichSettings.registration_enabled?).to be(enabled)
      results << response_row(name).merge('registration' => DawarichSettings.registration_enabled?)
    end
    results
  end

  def refusal_cases(actor)
    results = []
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    sign_in actor
    post settings_users_path, params: { user: { email: 'refused@example.invalid', password: password } }
    expect(response).to redirect_to(root_path)
    results << response_row('cloud_create')
    reset!
    post settings_users_path, params: { user: { email: 'refused@example.invalid', password: password } }
    expect(response).to redirect_to(root_path)
    results << response_row('cloud_guest')
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    sign_in synthetic_user(11_008)
    post settings_users_path, params: { user: { email: 'refused@example.invalid', password: password } }
    expect(response).to redirect_to(root_path)
    results << response_row('nonadmin_create')
    reset!
    post settings_users_path, params: { user: { email: 'refused@example.invalid', password: password } }
    expect(response).to redirect_to(new_user_session_path)
    results << response_row('guest_create')
    expect(User.exists?(email: 'refused@example.invalid')).to be(false)
    results
  end

  def save_cases(cases)
    cases.each do |capture|
      File.write(dir.join("#{capture.fetch('name')}.json"),
                 "#{Oj.dump(capture, mode: :strict, float_precision: 0, indent: 2).rstrip}\n")
    end
  end

  it 'captures create update role password and cookie outcomes' do
    cases = credential_cases
    expect(cases.map { |capture| capture.fetch('name') }).to eq(
      %w[create_en create_de duplicate_en duplicate_de invalid_email blank_email
         short_password blank_password min_password max_password long_password unicode_password bcrypt_72_bytes
         update_credentials update_invalid update_blank update_spaces update_nil noop_roles target_password
         self_password
         last_admin_role last_admin_status last_admin_both last_admin_false last_admin_integer_status
         second_admin_demote second_admin_disable invalid_status sanitize_update
         missing_user_create missing_user_update]
    )
    cases.select { |capture| %w[update_blank update_spaces update_nil].include?(capture['name']) }.each do |capture|
      expect(capture.fetch('password_unchanged')).to be(true)
    end
    created = cases.find { |capture| capture['name'] == 'create_en' }
    expect(created.fetch('after')).to include('id' => 11_101, 'admin' => false, 'status' => 'active', 'plan' => 'pro',
                                              'active_until' => '3026-10-04T10:00:00.000000Z')
    expect(cases.find { |capture| capture['name'] == 'self_password' })
      .to include('old_identity_valid' => false, 'repaired_identity' => false)
    save_cases(cases)
  end

  it 'captures deletion guards and retained producer actions' do
    cases = retained_cases
    expect(cases.map { |capture| capture.fetch('name') }).to eq(
      %w[family_refused member_deleted sole_owner_deleted creator_only_deleted last_admin_deleted
         conditional_winner repeated_delete missing_delete deleted_delete enqueue_failure
         rotate_key reset_password reset_mail_failure registration_on registration_off
         cloud_create cloud_guest nonadmin_create guest_create export import_missing]
    )
    refused = cases.find { |capture| capture['name'] == 'family_refused' }
    expect(refused).to include('status' => 303, 'deleted' => false, 'jobs' => [])
    expect(cases.find { |capture| capture['name'] == 'enqueue_failure' })
      .to include('deleted' => true, 'updated_at_unchanged' => true)
    save_cases(cases)
  end
  context 'native interoperability', :a10b_non_transactional do
    self.use_transactional_tests = false

    it 'Rails authenticates native created and admin updated credentials' do
      actor = synthetic_user(15_901, admin: true)
      target = synthetic_user(15_902)
      login(actor)
      line = Array(response.headers['Set-Cookie']).flat_map { |value| value.split("\n") }
                                                  .find { |value| value.start_with?('_dawarich_session=') }
      expect(line.nil?).to be(false)
      old_cookie = line.split(';', 2).first
      changed = 'synthetic-a10b-native-changed-password'
      result = phoenix(<<~ELIXIR, 'A10B_PASSWORD' => password, 'A10B_CHANGED' => changed)
        actor = Dawarich.Accounts.get(15901)
        context = %{self_hosted: true, oidc: false, locale: "en", env: %{"SELF_HOSTED" => "true"}}
        {:ok, created} = Dawarich.Admin.UserCreate.call(actor,
          %{"email" => "a10b-native-created@example.invalid", "password" => System.fetch_env!("A10B_PASSWORD")}, context)
        {:ok, 15902} = Dawarich.Admin.UserUpdate.call(actor, 15902,
          %{"email" => "a10b-native-target@example.invalid", "password" => System.fetch_env!("A10B_CHANGED")}, context)
        {:handoff, :target} = Dawarich.Admin.UserUpdate.call(actor, 15999, %{"email" => "unchanged@example.invalid"}, context)
        {:ok, 15901} = Dawarich.Admin.UserUpdate.call(actor, 15901,
          %{"password" => System.fetch_env!("A10B_CHANGED")}, context)
        IO.puts(Jason.encode!(%{created: created}))
      ELIXIR
      created = User.find(result.fetch('created'))
      expect(created.email).to eq('a10b-native-created@example.invalid')
      expect(created.valid_password?(password)).to be(true)
      expect(created).to have_attributes(admin: false, status: 'active', plan: 'pro')
      expect(target.reload.valid_password?(changed)).to be(true)
      expect(target.valid_password?(password)).to be(false)
      expect(actor.reload.valid_password?(changed)).to be(true)
      expect(User.exists?(15_999)).to be(false)
      browser = ActionDispatch::Integration::Session.new(Rails.application)
      browser.get('/', headers: { 'Cookie' => old_cookie })
      expect(browser.response.status).to eq(200)
    ensure
      User.unscoped.where(id: [15_901, 15_902]).delete_all
      User.unscoped.where(email: 'a10b-native-created@example.invalid').delete_all
    end
  end
end
