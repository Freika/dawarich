# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'Phoenix fixtures: settings, account and insights as Rails renders them', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:root) { Rails.root.join('app-phoenix') }
  let(:fixtures) { root.join('test/fixtures') }
  let(:helper) { ApplicationController.helpers }
  let(:zones) { JSON.parse(root.join('priv/time_zones.json').read).fetch('options') }

  context 'A11e account link' do
    let(:now) { Time.utc(2026, 10, 5, 12) }
    let(:link_password) { 'safepassword12' }
    let(:link_hash) { JSON.parse(fixtures.join('auth/requests.json').read).dig('login', 'user', 'encrypted_password') }

    before(:context) do
      @link_transactional = self.class.use_transactional_tests
      self.class.use_transactional_tests = false
      Rails.application.routes.append do
        devise_scope :user do
          get 'users/auth/openid_connect/callback', to: 'users/omniauth_callbacks#openid_connect'
        end
      end
      Rails.application.reload_routes!
    end

    after(:context) do
      self.class.use_transactional_tests = @link_transactional
    end

    before do
      @link_auth = Rails.application.env_config['omniauth.auth']
      @link_mock = OmniAuth.config.mock_auth[:openid_connect]
      @link_test_mode = OmniAuth.config.test_mode
      OmniAuth.config.test_mode = true
      Rails.application.env_config['devise.mapping'] = Devise.mappings[:user]
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      allow(BCrypt::Engine).to receive(:generate_salt).and_return(link_hash.byteslice(0, 29))
      expect(User.pepper).to be_blank
      @link_actors = []
      @link_next_id = 911_451_000
    end

    after do
      @link_actors.each { |id, email| User.unscoped.where(id: id, email: email).delete_all }
      Rails.application.env_config['omniauth.auth'] = @link_auth
      OmniAuth.config.mock_auth[:openid_connect] = @link_mock
      OmniAuth.config.test_mode = @link_test_mode
    end

    def link_fixture(name, value, json: true)
      path = fixtures.join('auth/account_link', name)
      content = json ? "#{Oj.dump(value, mode: :strict, float_precision: 0, indent: 2).chomp}\n" : value
      if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
        FileUtils.mkdir_p(path.dirname)
        File.write(path, content)
      else
        expect(path.exist?).to be(true), name
        expect(path.read == content).to be(true), name if path.exist?
      end
    end

    def link_actor
      id = (@link_next_id += 1)
      email = "a11e-#{id}@example.invalid"
      expect(User.unscoped.where('id = ? OR email = ?', id, email).exists?).to be(false)
      @link_actors << [id, email]
      actor = create(:user, id: id, email: email, password: link_password, skip_auto_trial: true,
skip_family_sync: true)
      actor.update_columns(encrypted_password: link_hash, settings: {}, api_key: "A11E_SYNTHETIC_#{id}",
                           created_at: now - 86_400, updated_at: now - 86_400, sign_in_count: 0,
                           current_sign_in_at: nil, last_sign_in_at: nil, current_sign_in_ip: nil,
                           last_sign_in_ip: nil, failed_attempts: 2, failed_otp_attempts: 3,
                           consumed_timestep: 42, remember_created_at: now - 86_400)
      actor.reload
    end

    def link_data(client)
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

    def link_browser(actor, locale: 'en', uid: nil)
      uid ||= "a11e-sub-#{actor.id}-A"
      auth = OmniAuth::AuthHash.new(provider: 'openid_connect', uid: uid,
                                    info: { email: actor.email, name: 'Synthetic' },
                                    extra: { raw_info: { email_verified: true } })
      OmniAuth.config.mock_auth[:openid_connect] = auth
      Rails.application.env_config['omniauth.auth'] = auth
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.get('/users/auth/openid_connect/callback')
      expect(client.response.location).to end_with('/auth/account_link/challenge')
      link_seed(client, link_data(client).merge('pending_oauth_link_attempts' => 3,
                                                'user_return_to' => '/trips', 'devise.synthetic' => 'expire'))
      client.get('/auth/account_link/challenge', params: { locale: locale })
      expect(client.response.status).to eq(200)
      client
    end

    def link_token(client)
      Nokogiri::HTML5(client.response.body)
              .at_css("form[action='/auth/account_link/challenge'] input[name='authenticity_token']")['value']
    end

    def link_pair(client)
      [client.cookies['_dawarich_session'], link_token(client)]
    end

    def link_copy(pair)
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.cookies['_dawarich_session'] = pair.first
      client
    end

    def link_actor_state(actor)
      User.unscoped.find(actor.id).attributes.slice(
        'id', 'email', 'encrypted_password', 'provider', 'uid', 'status', 'settings',
        'sign_in_count', 'current_sign_in_at', 'last_sign_in_at', 'current_sign_in_ip', 'last_sign_in_ip',
        'failed_attempts', 'locked_at', 'unlock_token', 'remember_created_at', 'otp_required_for_login',
        'consumed_timestep', 'failed_otp_attempts', 'otp_locked_at', 'otp_backup_codes', 'updated_at', 'deleted_at'
      ).transform_values { |value| value.respond_to?(:utc) ? iso(value) : value }
    end

    def link_projection(client, actor, before, session_before, writes, jobs)
      data = link_data(client)
      normalized = data.merge('session_id' => 'SESSION_ID')
      normalized['_csrf_token'] = 'CSRF' if data.key?('_csrf_token')
      normalized['warden.user.user.key'] = [[actor.id], 'SYNTHETIC_BCRYPT_SALT'] if data.key?('warden.user.user.key')
      after = link_actor_state(actor)
      {
        'status' => client.response.status, 'location' => client.response.location&.sub(%r{\Ahttps?://[^/]+}, ''),
        'headers' => client.response.headers.slice('cache-control', 'pragma', 'content-type'),
        'session' => normalized, 'before' => before, 'after' => after,
        'changed' => after.keys.reject { |key| after[key] == before[key] },
        'retained' => %w[session_id _csrf_token user_return_to devise.synthetic].index_with do |key|
          data[key] == session_before[key]
        end,
        'writes' => writes, 'jobs_delta' => enqueued_jobs.size - jobs,
        'remember_cookie' => client.cookies['remember_user_token'].present?
      }
    end

    def link_post(client, actor, password: link_password, token: link_token(client), headers: {})
      before = link_actor_state(actor)
      session_before = link_data(client)
      jobs = enqueued_jobs.size
      writes = []
      request_thread = Thread.current
      subscriber = lambda do |*args|
        sql = args.last[:sql]
        next unless Thread.current == request_thread
        next unless sql.start_with?('UPDATE "users"')

        writes << case sql
                  when /"provider"/ then 'identity'
                  when /"sign_in_count"/ then 'trackable'
                  when /"failed_attempts"/ then 'reset_password'
                  else 'other'
                  end
      end
      params = { authenticity_token: token }
      params[:password] = password unless password == :missing
      ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
        client.post('/auth/account_link/challenge', params: params, headers: headers)
      end
      if client.response.status == 422
        field = Nokogiri::HTML5(client.response.body).at_css('input[name="password"]')
        expect(field['value'].to_s).to eq('') if field
      end
      link_projection(client, actor, before, session_before, writes, jobs)
    end

    def link_overlap(actor, pair)
      observer = ActiveRecord::Base.connection_pool.checkout
      ready = Queue.new
      gates = [Queue.new, Queue.new]
      allow_any_instance_of(User).to receive(:valid_password?).and_wrap_original do |original, password|
        result = original.call(password)
        index = Thread.current[:a11e_fixture_worker]
        unless index.nil?
          connection = ActiveRecord::Base.connection
          ready << [index, connection.select_value('SELECT pg_backend_pid()'), result,
                    User.where(id: actor.id).exists?]
          gates[index].pop
        end
        result
      end
      workers = 2.times.map do |index|
        Thread.new do
          Thread.current[:a11e_fixture_worker] = index
          ActiveRecord::Base.connection_pool.with_connection do
            link_post(link_copy(pair), actor, token: pair.last)
          end
        end
      end
      prepared = Timeout.timeout(5) { [ready.pop, ready.pop] }
      expect(prepared.map { |row| row[1] }.uniq.size).to eq(2)
      expect(prepared.all? { |row| row[2] && row[3] }).to be(true)
      outcomes = workers.each_index.map do |index|
        gates[index] << true
        workers[index].value
      end
      expect(prepared.map { |row| row[1] }).not_to include(observer.select_value('SELECT pg_backend_pid()'))
      query = User.sanitize_sql_array(['SELECT provider, uid, sign_in_count FROM users WHERE id=?', actor.id])
      persisted = observer.select_one(query)
      expect(outcomes.map { |row| row['status'] }).to eq([302, 302])
      expect(persisted).to eq('provider' => 'openid_connect', 'uid' => "a11e-sub-#{actor.id}-A", 'sign_in_count' => 1)
      { 'prepared_connections_distinct' => true, 'visible_committed_actor' => true,
        'responses' => outcomes, 'persisted' => persisted }
    ensure
      gates&.each { |gate| gate << true }
      workers&.each(&:join)
      ActiveRecord::Base.connection_pool.checkin(observer) if observer
    end

    it 'A11e account link writes deterministic pending confirmation and fallback fixtures' do
      travel_to(now) do
        rows = { 'at' => now.to_i }
        pages = {}
        %w[en de fr es pl ca zh].each do |locale|
          actor = link_actor
          before = link_actor_state(actor)
          client = link_browser(actor, locale: locale)
          expect(link_actor_state(actor)).to eq(before)
          rows["challenge_#{locale}"] =
            link_projection(client, actor, before, link_data(client), [], enqueued_jobs.size)
          doc = Nokogiri::HTML5(client.response.body)
          expect(doc.css('form').map { |form| form['action'] })
            .to include('/auth/account_link/challenge', '/auth/account_link/email')
          expect(doc.at_css('input[name="password"]')['value'].to_s).to eq('')
          doc.css('input[name="authenticity_token"]').each { |node| node['value'] = 'CSRF' }
          doc.css('meta[name="csrf-token"]').each { |node| node['content'] = 'CSRF' }
          doc.css('[nonce]').each { |node| node['nonce'] = 'NONCE' }
          pages["challenge_#{locale}.html"] = doc.to_html
          alert = 'A11e <script>synthetic</script> & retry'
          incoming = link_data(client).merge('flash' => { 'discard' => [], 'flashes' => { 'alert' => alert } })
          link_seed(client, incoming)
          client.get('/auth/account_link/challenge')
          rows["challenge_alert_#{locale}"] =
            link_projection(client, actor, before, incoming, [], enqueued_jobs.size).merge(
              'incoming_flash' => incoming.fetch('flash')
            )
          doc = Nokogiri::HTML5(client.response.body)
          expect(doc.at_css('.card-body .alert-error').text.strip).to eq(alert)
          expect(doc.at_css('.card-body .alert-error').css('script')).to be_empty
          doc.css('input[name="authenticity_token"]').each { |node| node['value'] = 'CSRF' }
          doc.css('meta[name="csrf-token"]').each { |node| node['content'] = 'CSRF' }
          doc.css('[nonce]').each { |node| node['nonce'] = 'NONCE' }
          pages["challenge_alert_#{locale}.html"] = doc.to_html
          rows["success_#{locale}"] = link_post(client, actor)
          expect(rows["success_#{locale}"]['writes']).to eq(%w[identity reset_password trackable])
        end
        actor = link_actor
        actor.update_columns(otp_required_for_login: true)
        client = link_browser(actor)
        rows['otp'] = link_post(client, actor)
        expect(rows['otp']['after']['sign_in_count']).to eq(0)
        expect(rows['otp']['session'].keys).not_to include('warden.user.user.key')
        expect(rows['otp']['writes']).to eq(['identity'])

        actor = link_actor
        client = link_browser(actor)
        rows['wrong'] = link_post(client, actor, password: 'a11e-wrong')
        rows['fifth'] = link_post(client, actor, password: '')
        expect(rows['wrong']['status']).to eq(422)
        expect(rows['fifth']['status']).to eq(302)
        expect(rows['wrong']['changed']).to be_empty
        actor = link_actor
        client = link_browser(actor)
        token = Nokogiri::HTML5(client.response.body)
                        .at_css("form[action='/auth/account_link/email'] input[name='authenticity_token']")['value']
        before = link_actor_state(actor)
        data = link_data(client)
        jobs = enqueued_jobs.size
        rate_key = "#{Auth::FindOrCreateOauthUser::LINK_EMAIL_RATE_LIMIT_KEY_PREFIX}#{actor.id}"
        expect(Rails.cache.read(rate_key)).to be_nil
        begin
          client.post('/auth/account_link/email', params: { authenticity_token: token })
          rows['email'] = link_projection(client, actor, before, data, [], jobs)
          expect(rows['email']['jobs_delta']).to eq(1)
          expect(rows['email']['changed']).to be_empty
        ensure
          Rails.cache.delete(rate_key)
        end

        exclusions = {}
        %w[equal future expired missing_user deleted linked locked payment dirty_settings extra_field
           missing_time string_time other_provider pending_otp warden].each do |name|
          actor = link_actor
          client = link_browser(actor)
          data = link_data(client)
          pending = data['pending_oauth_link']
          case name
          when 'equal' then pending['expires_at'] = now.to_i
          when 'future' then pending['expires_at'] = now.to_i + 86_400
          when 'expired' then pending['expires_at'] = now.to_i - 1
          when 'missing_user' then pending['user_id'] = 999_999_999
          when 'deleted' then actor.update_columns(deleted_at: now - 60)
          when 'linked' then actor.update_columns(provider: 'google', uid: 'a11e-existing')
          when 'locked' then actor.update_columns(locked_at: now - 60, failed_attempts: 5)
          when 'payment' then actor.update_columns(status: User.statuses[:pending_payment])
          when 'dirty_settings' then actor.update_columns(settings: { 'immich_url' => 'https://example.invalid/' })
          when 'extra_field' then pending['unexpected'] = 'a11e-extra'
          when 'missing_time' then pending.delete('expires_at')
          when 'string_time' then pending['expires_at'] = now.to_i.to_s
          when 'other_provider' then pending['provider'] = 'google'
          when 'pending_otp' then data['otp_user_id'] = actor.id
          when 'warden' then data['warden.user.user.key'] = [[actor.id], actor.authenticatable_salt]
          end
          token = link_token(client)
          link_seed(client, data)
          before = link_actor_state(actor)
          client.get('/auth/account_link/challenge')
          challenge = link_projection(client, actor, before, data, [], enqueued_jobs.size)
          confirmation = link_post(client, actor, token: token)
          exclusions[name] = { 'pending' => pending, 'challenge' => challenge, 'confirmation' => confirmation,
                               'native' => %w[equal future].include?(name) }
        end

        actor = link_actor
        client = link_browser(actor)
        pair = link_pair(client)
        foreign = link_browser(actor)
        controller = Auth::AccountLinksController.new
        controller.set_request!(client.request)
        wrong_action = controller.send(:form_authenticity_token,
                                       form_options: { action: '/auth/account_link/email', method: 'post' })
        rows['csrf'] = {}
        negatives = { 'missing' => [nil, {}], 'foreign_session' => [link_token(foreign), {}],
                      'wrong_action' => [wrong_action, {}],
                      'foreign_origin' => [pair.last, { 'HTTP_ORIGIN' => 'https://foreign.example.invalid' }] }
        negatives.each do |name, (token, headers)|
          rows['csrf'][name] = link_post(link_copy(pair), actor, token: token, headers: headers)
          expect(rows['csrf'][name]['status']).to eq(422)
          expect(rows['csrf'][name]['changed']).to be_empty
        end
        rows['csrf']['valid'] = link_post(link_copy(pair), actor, token: pair.last)
        expect(rows['csrf']['valid']['status']).to eq(302)

        actor = link_actor
        pair = link_pair(link_browser(actor))
        rows['sequential_replay'] = 2.times.map { link_post(link_copy(pair), actor, token: pair.last) }
        expect(rows['sequential_replay'].map { |row| row['status'] }).to eq([302, 302])
        actor = link_actor
        first = link_pair(link_browser(actor))
        second = link_pair(link_browser(actor, uid: 'a11e-sub-B'))
        rows['superseded_collision'] = [first, second].map do |saved|
          link_post(link_copy(saved), actor, token: saved.last)
        end
        expect(rows['superseded_collision'].map { |row| row['after']['uid'] })
          .to eq(["a11e-sub-#{actor.id}-A", 'a11e-sub-B'])
        actor = link_actor
        pair = link_pair(link_browser(actor))
        transplant = ActionDispatch::Integration::Session.new(Rails.application)
        transplant.get('/users/sign_in')
        transplant.cookies['_dawarich_session'] = pair.first
        rows['transplant'] = link_post(transplant, actor, token: pair.last)
        expect(rows['transplant']['status']).to eq(302)
        actor = link_actor
        rows['overlap'] = link_overlap(actor, link_pair(link_browser(actor)))

        actor = link_actor
        client = link_browser(actor)
        other = link_actor
        other.update_columns(provider: 'openid_connect', uid: "a11e-sub-#{actor.id}-A")
        before = link_actor_state(actor)
        begin
          link_post(client, actor)
          raise 'a11e unique conflict unexpectedly accepted'
        rescue ActiveRecord::RecordNotUnique => e
          expect(link_actor_state(actor)).to eq(before)
          rows['unique_conflict'] = { 'error' => e.class.name, 'before' => before,
                                      'after' => link_actor_state(actor), 'pending_retained' => true }
          expect(link_data(client)).to have_key('pending_oauth_link')
        end
        actor = link_actor
        client = link_browser(actor)
        before = link_actor_state(actor)
        observer = ActiveRecord::Base.connection_pool.checkout
        begin
          callback_pid = nil
          allow_any_instance_of(User).to receive(:update_tracked_fields!) do
            callback_pid = ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')
            raise 'a11e-fixture-later-callback'
          end
          expect { link_post(client, actor) }.to raise_error(RuntimeError, 'a11e-fixture-later-callback')
          expect(observer.select_value('SELECT pg_backend_pid()')).not_to eq(callback_pid)
          expect(observer.transaction_open?).to be(false)
          sql = 'SELECT provider, uid, failed_attempts, sign_in_count FROM users WHERE id=?'
          durable = observer.select_one(User.sanitize_sql_array([sql, actor.id]))
          expect(durable).to eq('provider' => 'openid_connect', 'uid' => "a11e-sub-#{actor.id}-A",
                                'failed_attempts' => 0, 'sign_in_count' => 0)
          rows['later_callback_failure'] = { 'error' => 'RuntimeError', 'before' => before,
                                             'after' => link_actor_state(actor), 'durable' => durable,
                                             'independent_connection' => true }
        ensure
          allow_any_instance_of(User).to receive(:update_tracked_fields!).and_call_original
          ActiveRecord::Base.connection_pool.checkin(observer)
        end

        previous_enabled = Rack::Attack.enabled
        previous_store = Rack::Attack.cache.store
        counter_keys = []
        begin
          Rack::Attack.enabled = true
          Rack::Attack.cache.store = RackAttack::PhoenixCounterStore.new
          actor = link_actor
          client = link_browser(actor)
          pair = link_pair(client)
          epoch = now.to_i / 900
          session_key = "rack::attack:#{epoch}:auth/account_link_challenge_session:#{actor.id}"
          ip_key = "rack::attack:#{epoch}:auth/account_link_challenge_ip:198.51.100.234"
          connection = ActiveRecord::Base.connection
          [session_key, ip_key].each do |key|
            query = "SELECT count(*) FROM phoenix.counters WHERE key=#{connection.quote(key)}"
            expect(connection.select_value(query)).to eq(0)
            counter_keys << key
          end
          rate = 6.times.map do
            link_post(link_copy(pair), actor, password: 'a11e-wrong', token: pair.last,
                                            headers: { 'REMOTE_ADDR' => '198.51.100.234' })
          end
          expect(rate.map { |row| row['status'] }).to eq([422, 422, 422, 422, 422, 429])
          counters = [session_key, ip_key].index_with do |key|
            connection.select_value("SELECT value FROM phoenix.counters WHERE key=#{connection.quote(key)}")
          end
          expect(counters.values).to eq([6, 5])
          rows['shared_rate'] = { 'store' => Rack::Attack.cache.store.class.name, 'enabled' => Rack::Attack.enabled,
                                  'session_limit' => 5, 'ip_limit' => 20, 'period' => 900,
                                  'counts' => counters, 'responses' => rate }
        ensure
          Rack::Attack.enabled = previous_enabled
          Rack::Attack.cache.store = previous_store
          counter_keys.each do |key|
            ActiveRecord::Base.connection.execute("DELETE FROM phoenix.counters WHERE key=#{ActiveRecord::Base.connection.quote(key)}")
          end
        end

        vectors = [
          ['normal', link_password, link_password], ['missing', link_password, :missing],
          ['empty', link_password, ''], ['whitespace', ' ' * 12, ' ' * 12],
          ['72 bytes', "#{'a' * 71}b", "#{'a' * 71}b"],
          ['73 bytes', "#{'a' * 71}bc", "#{'a' * 71}bd"],
          ['prefix mismatch', "#{'a' * 71}b", "#{'a' * 71}c"],
          ['multibyte crossing', "#{'a' * 71}é", "#{'a' * 71}ê"],
          ['NUL', link_password, "#{link_password}\0ignored"],
          ['blank hash', '', link_password], ['malformed hash', 'invalid-bcrypt', link_password]
        ]
        rows['password_vectors'] = vectors.map do |name, original, submitted|
          actor = link_actor
          hash = name.end_with?('hash') ? original : Devise::Encryptor.digest(User, original)
          actor.update_columns(encrypted_password: hash)
          value = submitted == :missing ? '' : submitted
          before = link_actor_state(actor)
          result = begin
            actor.reload.valid_password?(value)
          rescue StandardError => e
            e.class.name
          end
          expect(link_actor_state(actor)).to eq(before)
          client = link_browser(actor)
          confirmation = begin
            link_post(client, actor, password: submitted)
          rescue ArgumentError, BCrypt::Errors::InvalidHash => e
            expect(link_actor_state(actor)).to eq(before)
            { 'error' => e.class.name, 'before' => before, 'after' => link_actor_state(actor), 'changed' => [] }
          end
          { 'name' => name, 'password' => submitted == :missing ? nil : submitted,
            'missing' => submitted == :missing, 'bytes' => value.bytesize, 'hash' => hash,
            'valid_password' => result, 'confirmation' => confirmation,
            'native' => !result.is_a?(String) && !name.end_with?('hash') && name != 'NUL' }
        end
        rows['normalization'] = { 'session_id' => 'SESSION_ID', 'csrf' => 'CSRF',
                                  'warden_salt' => 'SYNTHETIC_BCRYPT_SALT', 'nonce' => 'NONCE',
                                  'wire_cookies' => 'not emitted' }
        pages.each { |name, page| link_fixture(name, page, json: false) }
        link_fixture('requests.json', rows)
        link_fixture('exclusions.json', exclusions)
      end
    end
  end

  context 'A11d web OTP' do
    let(:now) { Time.utc(2026, 10, 4, 12) }
    let(:web_otp_secret) { 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ' }
    let(:web_otp_password) { 'safepassword12' }
    let(:web_otp_hash) do
      JSON.parse(fixtures.join('auth/requests.json').read).dig('login', 'user', 'encrypted_password')
    end

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
      allow(UsersMailer).to receive(:default_params)
        .and_return(UsersMailer.default_params.merge(from: 'a11d-synthetic@dawarich.test'))
    end

    def web_otp_fixture(name, value, json: true)
      path = fixtures.join('auth/otp', name)
      content = json ? "#{Oj.dump(value, mode: :strict, float_precision: 0, indent: 2).chomp}\n" : value
      if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
        FileUtils.mkdir_p(path.dirname)
        File.write(path, content)
      else
        expect(path.exist?).to be(true), name
        expect(path.read == content).to be(true), name if path.exist?
      end
    end

    def web_otp_actor(id)
      actor = create(:user, id: id, email: "a11d-#{id}@dawarich.test", password: web_otp_password)
      actor.update_columns(encrypted_password: web_otp_hash, api_key: "A11D_SYNTHETIC_#{id}",
                           settings: {}, created_at: now - 1.day, updated_at: now - 1.day,
                           sign_in_count: 0, current_sign_in_at: nil, last_sign_in_at: nil,
                           current_sign_in_ip: nil, last_sign_in_ip: nil,
                           failed_attempts: 2, failed_otp_attempts: 3)
      actor.update!(otp_secret: web_otp_secret, otp_required_for_login: true, otp_backup_codes: [web_otp_hash])
      actor.reload
    end

    def web_otp_browser(locale: 'en', extra: {})
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.get('/users/sign_in', params: { locale: locale })
      web_otp_seed(client, web_otp_session(client).merge(extra))
      client
    end

    def web_otp_session(client)
      jar = ActionDispatch::Cookies::CookieJar.build(
        ActionDispatch::Request.new(Rails.application.env_config.dup),
        '_dawarich_session' => client.cookies['_dawarich_session']
      )
      jar.encrypted['_dawarich_session']
    end

    def web_otp_seed(client, data)
      jar = ActionDispatch::Request.new(Rails.application.env_config.dup).cookie_jar
      jar.encrypted['_dawarich_session'] = { value: data }
      client.cookies['_dawarich_session'] = jar['_dawarich_session']
    end

    def web_otp_csrf(client)
      Nokogiri::HTML5(client.response.body).at_css('meta[name="csrf-token"]')['content']
    end

    def web_otp_start(client, actor, remember: nil)
      client.post('/users/sign_in', params: { authenticity_token: web_otp_csrf(client),
                                             user: { email: actor.email, password: web_otp_password,
                                                     remember_me: remember } })
      expect(client.response.status).to eq(422)
    end

    def web_otp_state(actor)
      actor.reload
      actor.attributes.slice('id', 'consumed_timestep', 'failed_attempts', 'failed_otp_attempts', 'sign_in_count',
                             'current_sign_in_ip', 'last_sign_in_ip').merge(
                               'otp_locked_at' => iso(actor.otp_locked_at), 'locked_at' => iso(actor.locked_at),
                               'unlock_token' => actor.unlock_token,
                               'backup_count' => actor.otp_backup_codes.length,
                               'remember_created_at' => iso(actor.remember_created_at),
                               'updated_at' => iso(actor.updated_at),
                               'current_sign_in_at' => iso(actor.current_sign_in_at),
                               'last_sign_in_at' => iso(actor.last_sign_in_at)
                             )
    end

    def web_otp_projection(client, actor, before, writes, jobs, mails)
      data = web_otp_session(client)
      normalized = data.merge('session_id' => 'SESSION_ID')
      normalized['_csrf_token'] = 'CSRF' if data.key?('_csrf_token')
      normalized['warden.user.user.key'] = [[actor.id], 'SYNTHETIC_BCRYPT_SALT'] if data.key?('warden.user.user.key')
      {
        'status' => client.response.status, 'location' => client.response.location&.sub(%r{\Ahttps?://[^/]+}, ''),
        'headers' => client.response.headers.slice('cache-control', 'content-type', 'x-frame-options',
                                                   'x-xss-protection', 'x-content-type-options',
                                                   'x-permitted-cross-domain-policies', 'referrer-policy'),
        'session' => normalized, 'state' => web_otp_state(actor),
        'retained' => %w[session_id _csrf_token locale user_return_to devise.synthetic].index_with do |key|
          data[key] == before[key]
        end,
        'remember_cookie' => client.cookies['remember_user_token'].present?,
        'writes' => writes, 'jobs_delta' => enqueued_jobs.size - jobs,
        'mail_delta' => ActionMailer::Base.deliveries.size - mails
      }
    end

    def web_otp_post(client, actor, code)
      before = web_otp_session(client)
      jobs = enqueued_jobs.size
      mails = ActionMailer::Base.deliveries.size
      writes = []
      subscriber = lambda do |_name, _start, _finish, _id, payload|
        sql = payload[:sql]
        next unless sql.start_with?('UPDATE "users"')

        writes << case sql
                  when /consumed_timestep/ then 'consume_totp'
                  when /otp_backup_codes/ then 'consume_backup'
                  when /otp_locked_at/ then sql.include?('failed_otp_attempts') ? 'reset_otp' : 'lock_otp'
                  when /failed_otp_attempts/ then 'increment_otp'
                  when /sign_in_count/ then 'trackable'
                  when /remember_created_at/ then 'remember'
                  when /failed_attempts/ then 'reset_devise'
                  else 'other'
                  end
      end
      ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
        client.post('/users/otp_challenge', params: { authenticity_token: web_otp_csrf(client), otp_attempt: code })
      end
      if client.response.status == 422
        field = Nokogiri::HTML5(client.response.body).at_css('input[name="otp_attempt"]')
        expect(field['value'].to_s).to eq('')
      end
      web_otp_projection(client, actor, before, writes, jobs, mails)
    end

    it 'A11d web OTP writes deterministic challenge and transition fixtures' do
      travel_to(now) do
        rows = {}
        %w[en de fr es pl ca zh].each_with_index do |locale, index|
          actor = web_otp_actor(75_400 + index)
          client = web_otp_browser(locale: locale, extra: { 'otp_failed_attempts' => 3 })
          before = web_otp_session(client)
          state = actor.attributes
          web_otp_start(client, actor, remember: '1')
          expect(actor.reload.attributes == state).to be(true)
          rows["start_#{locale}"] = web_otp_projection(client, actor, before, [], enqueued_jobs.size,
                                                       ActionMailer::Base.deliveries.size)
          initial = Nokogiri::HTML5(client.response.body)
          expect(initial.at_css('h1').text).to eq(I18n.t('devise.sessions.otp_challenge.two_factor_authentication',
                                                         locale: :en))
          rows["start_#{locale}"]['form_locale'] = 'en'
          rows["start_#{locale}"]['document_title'] = initial.at_css('title').text
          rows["form_#{locale}"] = web_otp_post(client, actor, 'not-a-code')
          doc = Nokogiri::HTML5(client.response.body)
          expect(doc.at_css('h1').text).to eq(I18n.t('devise.sessions.otp_challenge.two_factor_authentication',
                                                     locale: locale))
          form = doc.at_css('form[action="/users/otp_challenge"]')
          expect(form['data-turbo']).to eq('false')
          expect(form.at_css('input[name="otp_attempt"]')['value'].to_s).to eq('')
          form.css('input[name="authenticity_token"]').each { |input| input['value'] = 'CSRF' }
          web_otp_fixture("challenge_#{locale}.html", doc.at_css('.hero').to_html, json: false)
        end

        %w[totp totp_remember backup backup_locked].each_with_index do |name, index|
          actor = web_otp_actor(75_410 + index)
          actor.update_columns(otp_locked_at: now - 60) if name == 'backup_locked'
          client = web_otp_browser(extra: { 'otp_failed_attempts' => 2, 'user_return_to' => '/trips',
                                           'devise.synthetic' => 'discarded' })
          web_otp_start(client, actor, remember: name == 'totp_remember' ? '1' : '0')
          code = name.start_with?('backup') ? web_otp_password : actor.current_otp
          rows[name] = web_otp_post(client, actor, code)
          expect(rows[name]['status']).to eq(302)
          expect(rows[name]['state']['failed_otp_attempts']).to eq(0)
          expect(rows[name]['state']['failed_attempts']).to eq(0)
        end

        { 'ttl_299' => now.to_i - 299, 'ttl_300' => now.to_i - 300,
          'future' => now.to_i + 60, 'missing_time' => nil, 'missing_actor' => now.to_i }
          .each_with_index do |(name, timestamp), index|
          actor = web_otp_actor(75_420 + index)
          client = web_otp_browser(extra: { 'otp_user_id' => name == 'missing_actor' ? 99_999_999 : actor.id,
                                           'otp_challenge_at' => timestamp, 'otp_remember_me' => false,
                                           'otp_failed_attempts' => 3 })
          rows[name] = web_otp_post(client, actor, actor.current_otp)
          expect(rows[name]['status']).to eq(302)
        end

        %w[invalid replay outside_drift locked_totp fifth tenth].each_with_index do |name, index|
          actor = web_otp_actor(75_430 + index)
          actor.update_columns(consumed_timestep: now.to_i / 30) if name == 'replay'
          actor.update_columns(otp_locked_at: now - 60) if name == 'locked_totp'
          actor.update_columns(failed_otp_attempts: 9) if name == 'tenth'
          key = "otp_lockout_email_throttle/user/#{actor.id}"
          Rails.cache.delete(key)
          begin
            client = web_otp_browser(extra: { 'otp_failed_attempts' => name == 'tenth' ? 4 : 0 })
            web_otp_start(client, actor)
            code = case name
                   when 'replay', 'locked_totp' then actor.current_otp
                   when 'outside_drift' then actor.otp.at(now - 60)
                   else 'not-a-code'
                   end
            if name == 'fifth'
              rows[name] = 5.times.map { web_otp_post(client, actor, code) }
              expect(rows[name].map { |row| row['status'] }).to eq([422, 422, 422, 422, 302])
            else
              rows[name] = web_otp_post(client, actor, code)
            end
            expect(rows[name]['jobs_delta']).to eq(1) if name == 'tenth'
          ensure
            Rails.cache.delete(key)
          end
        end

        rows['normalization'] = { 'session_id' => 'SESSION_ID', 'csrf' => 'CSRF',
                                  'warden_salt' => 'SYNTHETIC_BCRYPT_SALT',
                                  'ciphertext' => 'not emitted', 'backup_hashes' => 'cardinality only' }
        web_otp_fixture('requests.json', rows)
      end
    end
  end

  context 'A11c two factor management' do
    let(:now) { Time.utc(2026, 10, 4, 12, 0, 0) }
    let(:otp_secret) { 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ' }

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
    end

    def two_factor_fixture(name, value, json: true)
      directory = fixtures.join('auth/two_factor')
      content = json ? "#{Oj.dump(value, mode: :strict, float_precision: 0, indent: 2)}\n" : value
      path = directory.join(name)
      if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
        FileUtils.mkdir_p(path.dirname)
        File.write(path, content)
      else
        expect(path.exist?).to be(true), name
        expect(path.read == content).to be(true), name if path.exist?
      end
    end

    def two_factor_actor(id)
      actor = create(:user, id: id, email: "a11c-#{id}@dawarich.test", password: 'a11c-fixture-password-42')
      actor.update_columns(settings: { 'timezone' => 'Europe/Berlin', 'onboarding_completed' => true },
                           active_until: Time.utc(3026, 1, 1), api_key: "a11c-synthetic-key-#{id}",
                           theme: 'dark', created_at: now - 1.day)
      actor.reload
    end

    def two_factor_browser(actor)
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.get('/users/sign_in')
      client.post('/users/sign_in', params: {
                    authenticity_token: two_factor_csrf(client),
                    user: { email: actor.email, password: 'a11c-fixture-password-42', remember_me: '1' }
                  })
      expect(client.response.status).to eq(303)
      client.get('/settings/two_factor')
      expect(client.response.status).to eq(200)
      client
    end

    def two_factor_csrf(client)
      Nokogiri::HTML5(client.response.body).at_css('meta[name="csrf-token"]')['content']
    end

    def two_factor_session(client)
      jar = ActionDispatch::Cookies::CookieJar.build(
        ActionDispatch::Request.new(Rails.application.env_config.dup),
        '_dawarich_session' => client.cookies['_dawarich_session']
      )
      jar.encrypted['_dawarich_session']
    end

    def two_factor_seed_session(client, data)
      jar = ActionDispatch::Request.new(Rails.application.env_config.dup).cookie_jar
      jar.encrypted['_dawarich_session'] = { value: data }
      client.cookies['_dawarich_session'] = jar['_dawarich_session']
    end

    def two_factor_state(actor)
      actor.reload
      secret = if actor.otp_secret.nil?
                 nil
               elsif actor.otp_secret == otp_secret
                 'SOURCE_SYNTHETIC_SECRET'
               else
                 'SETUP_SYNTHETIC_SECRET'
               end
      {
        'secret' => secret, 'enabled' => actor.otp_required_for_login,
        'consumed_timestep' => actor.consumed_timestep,
        'backups' => actor.otp_backup_codes&.map { 'BCRYPT' },
        'updated_at' => iso(actor.updated_at), 'failed_attempts' => actor.failed_attempts,
        'failed_otp_attempts' => actor.failed_otp_attempts, 'otp_locked_at' => iso(actor.otp_locked_at)
      }
    end

    def two_factor_html(doc)
      doc.css('input[name="authenticity_token"]').each { |field| field['value'] = 'CSRF' }
      doc.css('[nonce]').each { |node| node['nonce'] = 'NONCE' }
      doc.at_css('body > div.container > div.w-full > div.flex')&.inner_html
    end

    def two_factor_case(name, id)
      actor = two_factor_actor(id)
      client = two_factor_browser(actor)
      suffix = name[/_(de|es|fr|pl|ca|zh)$/, 1]
      kind = suffix ? name.delete_suffix("_#{suffix}") : name
      locale = suffix || 'en'
      enabled = kind == 'enabled' || kind == 'setup_enabled' || kind.start_with?('disable_', 'wrong', 'missing',
                                                                                 'invalid')
      backups = [Devise::Encryptor.digest(User, 'a11c-unused-backup')]
      actor.update!(otp_secret: kind == 'disabled' ? nil : otp_secret,
                    otp_required_for_login: enabled, otp_backup_codes: backups)
      actor.update_columns(failed_attempts: 2, failed_otp_attempts: 3, otp_locked_at: now - 2.hours,
                           reset_password_token: "a11c-synthetic-reset-#{id}", reset_password_sent_at: now - 1.hour,
                           consumed_timestep: kind == 'verify_replay' ? now.to_i / 30 : nil,
                           updated_at: now - 1.day)
      actor.update_column(:otp_secret, nil) if kind == 'verify_missing_secret'
      actor.update_column(:email, '') if kind == 'verify_second_save_failure'
      actor.update_column(:otp_backup_codes, nil) if %w[nil_backups repeated_disable].include?(kind)
      actor.update_column(:otp_backup_codes, []) if kind == 'empty_backups'
      actor.update!(otp_secret: nil, otp_required_for_login: false) if kind == 'repeated_disable'
      next_secret = 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP'
      allow(User).to receive(:generate_otp_secret).and_return(next_secret)
      if kind == 'setup_twice'
        client.post('/settings/two_factor', params: { authenticity_token: two_factor_csrf(client) })
        allow(User).to receive(:generate_otp_secret).and_return(otp_secret)
        actor.update_column(:updated_at, now - 1.day)
      end
      data = two_factor_session(client).merge('user_return_to' => '/stats', 'locale' => locale, 'a11c' => 'retain')
      two_factor_seed_session(client, data)
      before = actor.reload.attributes
      before_state = two_factor_state(actor)
      remember = client.cookies['remember_user_token']
      jobs = enqueued_jobs.size
      mails = ActionMailer::Base.deliveries.size
      method, path, input = two_factor_input(kind, actor)
      params = input.merge(authenticity_token: two_factor_csrf(client))
      codes = Array.new(10) { |index| format('%024x', index + 1) }
      allow(SecureRandom).to receive(:hex).and_call_original
      allow(SecureRandom).to receive(:hex).with(12).and_return(*codes)
      allow(DawarichSettings).to receive(:two_factor_available?).and_return(kind != 'unavailable')
      client.public_send(method, path, params: params)
      allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
      after = actor.reload.attributes
      received = two_factor_session(client)
      doc = Nokogiri::HTML5(client.response.body)
      fields = %w[session_id _csrf_token user_return_to locale a11c warden.user.user.key]
      displayed = doc.css('code.font-mono').map(&:text)
      row = {
        'name' => name, 'email' => before['email'], 'locale' => locale,
        'method' => method.to_s.upcase, 'path' => path,
        'input' => input.transform_values { |value| value == 'a11c-fixture-password-42' ? 'VALID_PASSWORD' : value },
        'status' => client.response.status, 'location' => client.response.location,
        'headers' => client.response.headers.slice('Content-Type', 'Vary', 'Cache-Control', 'X-Frame-Options',
                                                   'Referrer-Policy', 'X-Content-Type-Options'),
        'flash' => client.request.flash.to_hash, 'cookie_flash' => received.dig('flash', 'flashes'),
        'session_retained' => fields.index_with { |field| data[field] == received[field] },
        'remember_retained' => client.cookies['remember_user_token'] == remember,
        'changed' => before.keys.reject { |field| before[field] == after[field] }.sort,
        'before' => before_state, 'after' => two_factor_state(actor),
        'code_input_empty' => doc.css('input[name="otp_attempt"]').all? { |field| field['value'].blank? },
        'password_fields_empty' => doc.css('input[type="password"]').all? { |field| field['value'].blank? },
        'backup_count' => displayed.size, 'backup_format' => displayed.all? { |code| code.match?(/\A[0-9a-f]{24}\z/) },
        'backups_hash_valid' => displayed.empty? || actor.otp_backup_codes.zip(displayed).all? do |hash, code|
          Devise::Encryptor.compare(User, hash, code)
        end,
        'jobs_delta' => enqueued_jobs.size - jobs, 'mail_delta' => ActionMailer::Base.deliveries.size - mails
      }
      [row, two_factor_html(doc)]
    end

    def two_factor_input(kind, actor)
      if %w[disabled enabled unavailable].include?(kind)
        [:get, '/settings/two_factor', {}]
      elsif kind.start_with?('setup')
        [:post, '/settings/two_factor', {}]
      elsif kind.start_with?('verify')
        code = %w[verify_bad verify_missing_secret].include?(kind) ? 'not-a-code' : actor.current_otp
        [:post, '/settings/two_factor/verify', { otp_attempt: code }]
      else
        input = { password: 'a11c-fixture-password-42',
                  otp_attempt: actor.otp_secret ? actor.current_otp : 'not-a-code' }
        input[:otp_attempt] = 'a11c-unused-backup' if kind == 'disable_backup'
        input[:password] = 'incorrect' if kind == 'wrong_password'
        input.delete(:password) if kind == 'missing_password'
        input[:otp_attempt] = 'not-a-code' if %w[invalid_code nil_backups empty_backups repeated_disable].include?(kind)
        input.delete(:otp_attempt) if kind == 'missing_code'
        input[:_method] = 'delete' if kind == 'disable_override'
        [kind == 'disable_override' ? :post : :delete, '/settings/two_factor', input]
      end
    end

    def two_factor_otp
      actor = two_factor_actor(74_300)
      actor.update!(otp_secret: otp_secret)
      zero_time = (0..200).map { |index| now + index * 30 }.find { |time| actor.otp.at(time).start_with?('0') }
      vectors = [
        ['past_outside', now, -60, nil, :plain], ['past_edge', now, -30, nil, :plain],
        ['current', now, 0, nil, :plain], ['future_edge', now, 30, nil, :plain],
        ['future_outside', now, 60, nil, :plain], ['whitespace', now, 0, nil, :whitespace],
        ['leading_zero', zero_time, 0, nil, :plain], ['short_zero', zero_time, 0, nil, :short],
        ['unicode_space', now, 0, nil, :unicode], ['consumed_current', now, 0, now.to_i / 30, :plain],
        ['consumed_future', now, 30, now.to_i / 30 + 1, :plain],
        ['old_after_future', now, 0, now.to_i / 30 + 1, :plain],
        ['boundary_29', now + 29, 30, nil, :plain], ['boundary_30', now + 30, -30, nil, :plain],
        ['boundary_59', now + 59, -30, nil, :plain]
      ].map do |name, at, offset, consumed, style|
        travel_to(at)
        actor.update_columns(consumed_timestep: consumed)
        code = actor.otp.at(at + offset)
        code = " \t#{code[0..2]}\n#{code[3..]}\r\f\v" if style == :whitespace
        code = code.delete_prefix('0') if style == :short
        code += 160.chr(Encoding::UTF_8) if style == :unicode
        valid = actor.validate_and_consume_otp!(code)
        { 'name' => name, 'at' => at.to_i, 'code' => code, 'consumed' => consumed,
          'valid' => valid, 'result_timestep' => actor.reload.consumed_timestep }
      end
      travel_to(now)
      labels = ['a11c@example.test', ' spaced + colon:name  ', 'üser:例@example.test'].map do |label|
        { 'label' => label, 'uri' => actor.otp_provisioning_uri(label, issuer: 'Dawarich') }
      end
      uri = actor.otp_provisioning_uri(actor.email, issuer: 'Dawarich')
      {
        'secret' => 'BASE32_OF_SYNTHETIC_ENTROPY', 'entropy_hex' => '3132333435363738393031323334353637383930',
        'vectors' => vectors, 'labels' => labels, 'qr' => qr_entry(uri),
        'web_drift_seconds' => User.otp_allowed_drift, 'backup_random_bytes' => User.otp_backup_code_length,
        'backup_count' => User.otp_number_of_backup_codes, 'bcrypt_cost' => User.stretches,
        'api_differences' => { 'confirm_drift_seconds' => 1, 'confirm_consumes_timestep' => false,
                               'destroy_backups' => [] },
        'normalization' => { 'csrf' => 'CSRF', 'nonce' => 'NONCE', 'backup_hash' => 'BCRYPT',
                             'session_cookie' => 'retention booleans',
                             'encryption' => 'SOURCE_SYNTHETIC_SECRET or SETUP_SYNTHETIC_SECRET; nil remains nil' }
      }
    end

    def two_factor_exclusions
      %w[provider cloud remember_only stale_actor dirty_settings query json missing_csrf duplicate_code corrupt_secret]
        .each_with_index.map do |name, index|
        actor = two_factor_actor(74_400 + index)
        client = two_factor_browser(actor)
        actor.update!(otp_secret: otp_secret)
        session = two_factor_session(client)
        actor.update_columns(provider: 'github', uid: 'a11c-synthetic-provider') if name == 'provider'
        allow(DawarichSettings).to receive(:self_hosted?).and_return(name != 'cloud')
        two_factor_seed_session(client, session.except('warden.user.user.key')) if name == 'remember_only'
        if name == 'stale_actor'
          two_factor_seed_session(client,
                                  session.merge('warden.user.user.key' => [[actor.id],
                                                                           'stale-salt']))
        end
        if name == 'dirty_settings'
          actor.update_column(:settings,
                              actor.settings.merge('immich_url' => 'https://a11c.example.test///'))
        end
        if name == 'corrupt_secret'
          User.connection.execute("UPDATE users SET otp_secret='corrupt-ciphertext' WHERE id=#{actor.id}")
        end
        params = { authenticity_token: two_factor_csrf(client), otp_attempt: 'not-a-code' }
        params.delete(:authenticity_token) if name == 'missing_csrf'
        path = name == 'query' ? '/settings/two_factor/verify?extra=1' : '/settings/two_factor/verify'
        headers = name == 'json' ? { 'Accept' => 'application/json' } : {}
        if name == 'duplicate_code'
          params = "#{URI.encode_www_form(params)}&otp_attempt=last-code"
          headers['CONTENT_TYPE'] = 'application/x-www-form-urlencoded'
        end
        status = nil
        error = nil
        begin
          client.post(path, params: params, headers: headers)
          status = client.response.status
        rescue ActiveRecord::Encryption::Errors::Decryption, ActionView::MissingTemplate => e
          error = e.class.name
        ensure
          allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
        end
        { 'name' => name, 'owner' => 'rails', 'status' => status, 'error' => error,
          'location' => error ? nil : client.response.location }
      end
    end

    def two_factor_corpus
      names = %w[
        disabled enabled unavailable setup setup_twice setup_enabled verify_good verify_bad verify_replay
        verify_missing_secret verify_second_save_failure disable_totp disable_backup disable_override
        wrong_password missing_password invalid_code missing_code nil_backups empty_backups repeated_disable
        disabled_de enabled_de setup_de verify_bad_de verify_good_de
      ] + %w[es fr pl ca zh].flat_map do |locale|
        %w[disabled enabled setup verify_bad verify_good].map { |name| "#{name}_#{locale}" }
      end
      requests = []
      html = {}
      names.each_with_index do |name, index|
        row, page = two_factor_case(name, 74_000 + index)
        requests << row
        html[name] = page if page
      end
      { requests: requests, otp: two_factor_otp, exclusions: two_factor_exclusions, html: html }
    end

    it 'records A11c review blank secret behavior' do
      travel_to now do
        rows = [nil, ''].each_with_index.map do |secret, index|
          actor = two_factor_actor(74_600 + index)
          client = two_factor_browser(actor)
          actor.update!(otp_secret: secret, otp_required_for_login: true,
                        otp_backup_codes: [Devise::Encryptor.digest(User, 'a11c-review-backup')])
          code = ROTP::TOTP.new('').at(now)
          before = actor.reload.attributes
          expect(actor.validate_and_consume_otp!(code)).to be(false)
          expect(actor.reload.attributes == before).to be(true)
          client.post('/settings/two_factor/verify', params: {
                        authenticity_token: two_factor_csrf(client), otp_attempt: code
                      })
          expect(client.response.status).to eq(422)
          expect(actor.reload.attributes == before).to be(true)
          verify_status = client.response.status
          client.delete('/settings/two_factor', params: {
                          authenticity_token: two_factor_csrf(client),
                          password: 'a11c-fixture-password-42', otp_attempt: code
                        })
          expect(client.response.status).to eq(302)
          expect(actor.reload.attributes == before).to be(true)
          alert = client.request.flash[:alert]
          client.get('/settings/two_factor')
          client.delete('/settings/two_factor', params: {
                          authenticity_token: two_factor_csrf(client),
                          password: 'a11c-fixture-password-42', otp_attempt: 'a11c-review-backup'
                        })
          expect(actor.reload.attributes.values_at('otp_secret', 'otp_required_for_login', 'otp_backup_codes'))
            .to eq([nil, false, nil])
          { 'secret' => secret, 'code' => code, 'at' => now.to_i, 'valid' => false,
            'verify_status' => verify_status, 'disable_alert' => alert,
            'unchanged' => true, 'backup_disable_status' => client.response.status }
        end
        two_factor_fixture('review_blank_secrets.json', rows)
      end
    end

    it 'records A11c review confirmation exclusions' do
      travel_to now do
        rows = %w[password otp_attempt].each_with_index.map do |field, index|
          actor = two_factor_actor(74_610 + index)
          client = two_factor_browser(actor)
          actor.update!(otp_secret: otp_secret, otp_required_for_login: true,
                        otp_backup_codes: [Devise::Encryptor.digest(User, 'a11c-review-backup')])
          input = { 'password' => 'a11c-fixture-password-42', 'otp_attempt' => 'a11c-review-backup' }
          input[field] += "#{0.chr}suffix"
          before = actor.reload.attributes
          error = nil
          begin
            client.delete('/settings/two_factor', params: input.merge('authenticity_token' => two_factor_csrf(client)))
          rescue ArgumentError => e
            error = e.class.name
          end
          expect(error).to eq('ArgumentError')
          expect(actor.reload.attributes == before).to be(true)
          { 'field' => field, 'input' => input, 'error' => error, 'unchanged' => true, 'owner' => 'rails' }
        end
        two_factor_fixture('review_confirmations.json', rows)
      end
    end

    it 'records A11c review legacy hash behavior' do
      travel_to now do
        password = 'a11c-fixture-password-42'
        backup = 'a11c-review-backup'
        rows = %w[password backup].each_with_index.map do |kind, index|
          actor = two_factor_actor(74_620 + index)
          client = two_factor_browser(actor)
          password_hash = BCrypt::Engine.hash_secret(password, '$2a$04$abcdefghijklmnopqrstuu')
          backup_hash = BCrypt::Engine.hash_secret(backup, '$2a$04$abcdefghijklmnopqrstuu')
          password_hash = password_hash.sub('$2a$', '$2y$') if kind == 'password'
          backup_hash = backup_hash.sub('$2a$', '$2y$') if kind == 'backup'
          expect(Devise::Encryptor.compare(User, password_hash, password)).to be(true)
          expect(Devise::Encryptor.compare(User, backup_hash, backup)).to be(true)
          actor.update!(encrypted_password: password_hash, otp_secret: otp_secret,
                        otp_required_for_login: true, otp_backup_codes: [backup_hash])
          data = two_factor_session(client).merge('warden.user.user.key' => [[actor.id], actor.authenticatable_salt])
          two_factor_seed_session(client, data)
          before = actor.reload.attributes
          client.delete('/settings/two_factor', params: {
                          authenticity_token: two_factor_csrf(client), password: password, otp_attempt: backup
                        })
          expect(client.response.status).to eq(302)
          expect(actor.reload.attributes.values_at('otp_secret', 'otp_required_for_login', 'otp_backup_codes'))
            .to eq([nil, false, nil])
          ignored = %w[otp_secret otp_required_for_login otp_backup_codes updated_at]
          expect(actor.attributes.except(*ignored) == before.except(*ignored)).to be(true)
          { 'kind' => kind, 'password_hash' => password_hash, 'backup_hash' => backup_hash,
            'input' => { 'password' => password, 'otp_attempt' => backup },
            'password_valid' => true, 'backup_valid' => true, 'status' => client.response.status,
            'disabled' => true, 'flash' => client.request.flash.to_hash }
        end
        two_factor_fixture('review_legacy_hashes.json', rows)
      end
    end

    it 'records A11c review inherited alert behavior' do
      travel_to now do
        actor = two_factor_actor(74_630)
        client = two_factor_browser(actor)
        actor.update!(otp_secret: otp_secret)
        incoming = { 'alert' => 'A11c previous alert', 'notice' => 'A11c retained notice',
                     'warning' => 'A11c retained warning' }
        data = two_factor_session(client).merge('flash' => { 'discard' => [], 'flashes' => incoming })
        two_factor_seed_session(client, data)
        before = actor.reload.attributes
        client.post('/settings/two_factor/verify', params: {
                      authenticity_token: two_factor_csrf(client), otp_attempt: 'not-a-code'
                    })
        expect(client.response.status).to eq(422)
        expect(actor.reload.attributes == before).to be(true)
        message = 'Invalid verification code. Please try again.'
        expect(client.response.body).not_to include(incoming.fetch('alert'))
        expect(client.response.body.scan(message).size).to eq(1)
        expect(client.request.flash.to_hash).to eq(incoming.merge('alert' => message))
        two_factor_fixture('review_inherited_alert.json', {
                             'status' => client.response.status, 'incoming' => incoming,
                             'flash_entries' => client.request.flash.to_a,
                             'cookie_flash' => two_factor_session(client).dig('flash', 'flashes')
                           })
        html = Nokogiri::HTML5(client.response.body).at_css('#flash-messages').to_html
        two_factor_fixture('review/inherited_alert.html', html, json: false)
      end
    end

    it 'writes or verifies A11c management contract fixtures' do
      travel_to now do
        corpus = two_factor_corpus
        expected_names = %w[
          disabled enabled unavailable setup setup_twice setup_enabled verify_good verify_bad verify_replay
          verify_missing_secret verify_second_save_failure disable_totp disable_backup disable_override
          wrong_password missing_password invalid_code missing_code nil_backups empty_backups repeated_disable
          disabled_de enabled_de setup_de verify_bad_de verify_good_de
        ]
        expected_names += %w[es fr pl ca zh].flat_map do |locale|
          %w[disabled enabled setup verify_bad verify_good].map { |name| "#{name}_#{locale}" }
        end
        expect(corpus.fetch(:requests).pluck('name')).to eq(expected_names)
        bad = corpus.fetch(:requests).find { |row| row['name'] == 'verify_bad' }
        expect(bad.slice('status', 'code_input_empty', 'flash')).to eq(
          'status' => 422, 'code_input_empty' => true,
          'flash' => { 'alert' => 'Invalid verification code. Please try again.' }
        )
        vector_names = %w[
          past_outside past_edge current future_edge future_outside whitespace leading_zero short_zero
          unicode_space consumed_current consumed_future old_after_future boundary_29 boundary_30 boundary_59
        ]
        expect(corpus.fetch(:otp).fetch('vectors').pluck('name')).to eq(vector_names)
        exclusion_names = %w[
          provider cloud remember_only stale_actor dirty_settings query json missing_csrf duplicate_code corrupt_secret
        ]
        expect(corpus.fetch(:exclusions).pluck('name')).to eq(exclusion_names)
        corpus.fetch(:requests).each do |row|
          expect(row['session_retained'].values.all?).to be(true), row['name']
          expect(row.values_at('remember_retained', 'password_fields_empty', 'backups_hash_valid')).to eq([true] * 3)
          expect(row.values_at('jobs_delta', 'mail_delta')).to eq([0, 0])
          expect(row['changed'] - %w[otp_secret otp_backup_codes otp_required_for_login consumed_timestep updated_at])
            .to eq([]), row['name']
          kind = row['name'].sub(/_(de|es|fr|pl|ca|zh)$/, '')
          status = if %w[unavailable repeated_disable].include?(kind) || kind.start_with?('disable_') ||
                      %w[wrong_password missing_password invalid_code missing_code nil_backups
                         empty_backups].include?(kind)
                     302
                   elsif %w[verify_bad verify_replay verify_missing_secret verify_second_save_failure].include?(kind)
                     422
                   else
                     200
                   end
          expect(row['status']).to eq(status), row['name']
          if kind == 'verify_good'
            expect(row.values_at('backup_count', 'backup_format')).to eq([10, true])
            expect(row.dig('after', 'enabled')).to be(true)
          elsif %w[disable_totp disable_backup disable_override].include?(kind)
            expect(row['after'].values_at('secret', 'enabled', 'backups')).to eq([nil, false, nil])
          elsif kind == 'verify_second_save_failure'
            expect(row['changed']).to eq(%w[consumed_timestep updated_at])
          end
        end
        expect(corpus.fetch(:otp).fetch('vectors').pluck('valid')).to eq(
          [false, true, true, true, false, true, true, false, false, false, false, false, true, true, true]
        )
        corpus.except(:html).each { |name, value| two_factor_fixture("#{name}.json", value) }
        corpus.fetch(:html).each { |name, html| two_factor_fixture("#{name}.html", html, json: false) }
      end
    end
  end

  context 'A11 account security' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

    def account_fixture(name, value, json: true)
      directory = fixtures.join('auth/account')
      content = json ? "#{Oj.dump(value, mode: :strict, float_precision: 0, indent: 2)}\n" : value
      path = directory.join(name)
      if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
        FileUtils.mkdir_p(directory)
        File.write(path, content)
      else
        aggregate_failures(name) do
          expect(path.exist?).to be(true)
          expect(path.read == content).to be(true) if path.exist?
        end
      end
    end

    def account_actor(id)
      user = create(:user, id:, email: "a11rest-#{id}@dawarich.test", password: 'a11rest-password-42')
      user.update_columns(settings: { 'timezone' => 'Europe/Berlin', 'onboarding_completed' => true },
                          api_key: 'API_KEY', created_at: now - 1.day, updated_at: now - 1.day,
                          reset_password_token: "a11rest-reset-digest-#{id}", reset_password_sent_at: now - 1.hour)
      user.reload
    end

    def account_browser(user)
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.get('/users/sign_in')
      client.post('/users/sign_in', params: {
                    authenticity_token: account_csrf(client),
                    user: { email: user.email, password: 'a11rest-password-42', remember_me: '1' }
                  })
      expect(client.response.status).to eq(303)
      client.get('/users/edit')
      expect(client.response.status).to eq(200)
      client
    end

    def account_csrf(client)
      Nokogiri::HTML5(client.response.body).at_css('meta[name="csrf-token"]')['content']
    end

    def decoded_account_session(client)
      request = ActionDispatch::Request.new(Rails.application.env_config.dup)
      jar = ActionDispatch::Cookies::CookieJar.build(request,
                                                     '_dawarich_session' => client.cookies['_dawarich_session'])
      jar.encrypted['_dawarich_session']
    end

    def seed_account_session(client, session)
      jar = ActionDispatch::Request.new(Rails.application.env_config.dup).cookie_jar
      jar.encrypted['_dawarich_session'] = { value: session }
      client.cookies['_dawarich_session'] = jar['_dawarich_session']
    end

    def account_cases
      [
        ['put', 'PUT', {}], ['patch', 'PATCH', {}],
        ['post_put', 'POST', { '_method' => 'put' }], ['post_patch', 'POST', { '_method' => 'patch' }],
        ['blank_current', 'PUT', { 'current_password' => 'empty' }],
        ['missing_current', 'PUT', { 'current_password' => 'omitted' }],
        ['no_op_blank_current', 'PUT', { 'email' => 'same', 'current_password' => 'empty' }],
        ['wrong_current', 'PUT', { 'current_password' => 'wrong' }],
        ['email_only', 'PUT', { 'email' => 'normalized' }],
        ['password_only', 'PUT', { 'email' => 'same', 'password' => 'new', 'password_confirmation' => 'new' }],
        ['both', 'PUT', { 'password' => 'new', 'password_confirmation' => 'new' }],
        ['no_op', 'PUT', { 'email' => 'same', 'password' => 'empty', 'password_confirmation' => 'empty' }],
        ['omitted_confirmation', 'PUT', { 'password' => 'new' }],
        ['empty_confirmation', 'PUT', { 'password' => 'new', 'password_confirmation' => 'empty' }],
        ['mismatch_confirmation', 'PUT', { 'password' => 'new', 'password_confirmation' => 'wrong' }],
        ['length_11', 'PUT', { 'password' => 'repeat_x_11' }],
        ['length_12', 'PUT', { 'password' => 'repeat_x_12' }],
        ['length_128', 'PUT', { 'password' => 'repeat_x_128' }],
        ['length_129', 'PUT', { 'password' => 'repeat_x_129' }],
        ['multibyte_11', 'PUT', { 'password' => 'repeat_ü_11' }],
        ['multibyte_12', 'PUT', { 'password' => 'repeat_ü_12' }],
        ['duplicate_email', 'PUT', { 'email' => 'taken' }],
        ['deleted_email', 'PUT', { 'email' => 'deleted' }],
        ['multiple_errors', 'PUT', { 'email' => 'invalid', 'password' => 'short',
                                   'password_confirmation' => 'empty', 'current_password' => 'empty' }],
        ['blank_email', 'PUT', { 'email' => 'empty' }],
        ['duplicate_scalar_email', 'PUT', { 'duplicate' => 'email' }],
        ['duplicate_scalar_current', 'PUT', { 'duplicate' => 'current_password' }],
        ['malformed_encoding', 'PUT', { 'malformed' => true }],
        ['type_conflict', 'PUT', { 'type_conflict' => true }],
        ['errors_de', 'PUT', { 'email' => 'invalid', 'password' => 'short', 'password_confirmation' => 'empty',
                             'current_password' => 'empty', 'locale' => 'de' }]
      ] + %w[es fr pl ca zh].map do |locale|
        ["errors_#{locale}", 'PUT', { 'email' => 'invalid', 'password' => 'short',
                                     'password_confirmation' => 'empty', 'current_password' => 'empty',
                                     'locale' => locale }]
      end
    end

    def account_input(input, user)
      input = { 'email' => 'changed', 'current_password' => 'valid' }.merge(input)
      input.slice('email', 'password', 'password_confirmation', 'current_password').filter_map do |field, marker|
        next if marker == 'omitted'

        value = if field == 'email'
                  { 'same' => user.email, 'changed' => "a11rest-changed-#{user.id}@dawarich.test",
                    'normalized' => " A11REST-NORMALIZED-#{user.id}@dawarich.test ",
                    'taken' => 'A11REST-TAKEN@dawarich.test', 'deleted' => 'a11rest-deleted@dawarich.test',
                    'invalid' => '<bad>', 'empty' => '' }.fetch(marker)
                elsif marker.start_with?('repeat_')
                  _, character, count = marker.split('_')
                  character * count.to_i
                else
                  { 'valid' => 'a11rest-password-42', 'new' => 'a11rest-new-password',
                    'empty' => '', 'wrong' => 'wrong-password', 'short' => 'short' }.fetch(marker)
                end
        [field, value]
      end.to_h
    end

    def account_body(client, input, params)
      body = URI.encode_www_form({ authenticity_token: account_csrf(client), _method: input['_method'],
                                  locale: input['locale'] }.compact)
      body += "&#{URI.encode_www_form(params.to_h { |field, value| ["user[#{field}]", value] })}"
      body += '&user%5Bemail%5D=a11rest-last%40dawarich.test' if input['duplicate'] == 'email'
      body = "user%5Bcurrent_password%5D=wrong&#{body}" if input['duplicate'] == 'current_password'
      body += '&user%5Bemail%5D=%FF' if input['malformed']
      body += '&user%5Bemail%5D%5Bnested%5D=value' if input['type_conflict']
      body
    end

    def account_projection(client, user, before, session, remember, jobs, mails)
      after = user.reload.attributes
      received = decoded_account_session(client)
      retained = %w[session_id _csrf_token user_return_to locale a11rest]
      {
        'status' => client.response.status, 'location' => client.response.location,
        'changed' => before.keys.reject { |key| before[key] == after[key] }.sort,
        'email' => user.email, 'reset_cleared' => user.reset_password_token.nil? && user.reset_password_sent_at.nil?,
        'hash_changed' => before['encrypted_password'] != after['encrypted_password'],
        'bcrypt_cost' => BCrypt::Password.new(user.encrypted_password).cost,
        'old_password_valid' => user.valid_password?('a11rest-password-42'),
        'jobs_delta' => enqueued_jobs.size - jobs, 'mail_delta' => ActionMailer::Base.deliveries.size - mails,
        'session' => {
          'retained' => retained.index_with { |key| session[key] == received[key] },
          'warden_salt_retained' => session.dig('warden.user.user.key', 1) == received.dig('warden.user.user.key', 1),
          'warden_matches_actor' => received.dig('warden.user.user.key', 1) == user.authenticatable_salt,
          'devise_data_removed' => !received.key?('devise.test'),
          'remember_cookie_retained' => client.cookies['remember_user_token'] == remember,
          'flash' => received.dig('flash', 'flashes')
        }
      }
    end

    def capture_account_case(name, method, input, id)
      user = account_actor(id)
      client = account_browser(user)
      user.update_columns(failed_attempts: 2, failed_otp_attempts: 3, otp_locked_at: now - 2.hours,
                          updated_at: now - 1.day)
      session = decoded_account_session(client).merge('devise.test' => 'expire', 'user_return_to' => '/stats',
                                                      'locale' => 'en', 'a11rest' => 'retain')
      seed_account_session(client, session)
      before = user.reload.attributes
      remember = client.cookies['remember_user_token']
      jobs = enqueued_jobs.size
      mails = ActionMailer::Base.deliveries.size
      params = account_input(input, user)
      client.public_send(method.downcase, '/users', params: account_body(client, input, params),
                         headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' })
      projection = account_projection(client, user, before, session, remember, jobs, mails)
      projection.merge!('name' => name, 'method' => method, 'input' => input, 'locale' => input['locale'] || 'en',
                        'password_valid' => params['password'].blank? || user.valid_password?(params['password']))
      doc = Nokogiri::HTML5(client.response.body)
      projection['errors'] = doc.css('#error_explanation li').map(&:text)
      projection['submitted_email'] = doc.at_css('#user_email')&.[]('value')
      projection['password_fields_empty'] = doc.css('input[type="password"]').all? { |field| field['value'].blank? }
      html = if client.response.status == 422
               doc.css('input[name="authenticity_token"]').each { |field| field['value'] = 'CSRF' }
               doc.css('[nonce]').each { |node| node['nonce'] = 'NONCE' }
               doc.at_css('body > div.container > div.w-full > div.flex').inner_html
             end
      [projection, html]
    end

    def account_contract_corpus
      taken = account_actor(73_301)
      taken.update_column(:email, 'a11rest-taken@dawarich.test')
      deleted = account_actor(73_302)
      deleted.update_columns(email: 'a11rest-deleted@dawarich.test', deleted_at: now)
      requests = []
      html = {}
      account_cases.each_with_index do |(name, method, input), index|
        row, page = capture_account_case(name, method, input, 73_400 + index)
        requests << row
        html["#{name}_#{row['locale']}"] = page if page
      end
      validation = requests.reject { |row| %w[malformed_encoding type_conflict].include?(row['name']) }.map do |row|
        row.slice('name', 'input', 'locale', 'status', 'errors', 'submitted_email', 'password_fields_empty')
      end
      { requests:, validation:, api_keys: account_key_corpus, html: }
    end

    def account_key_corpus
      names = %w[plain turbo referer invalid_resource legacy_invalid_email dirty_settings
                 legacy_uppercase_invalid_email legacy_padded_valid_email browser_navigation]
      names.each_with_index.map do |name, index|
        user = account_actor(73_500 + index)
        user.update_column(:api_key, "a11rest-key-#{user.id}")
        client = account_browser(user)
        user.update_column(:updated_at, now - 1.day)
        user.update_column(:email, '') if name == 'invalid_resource'
        user.update_column(:email, 'invalid') if name == 'legacy_invalid_email'
        user.update_column(:email, 'INVALID') if name == 'legacy_uppercase_invalid_email'
        user.update_column(:email, " A11REST-LEGACY-#{user.id}@DAWARICH.TEST ") if name == 'legacy_padded_valid_email'
        if name == 'dirty_settings'
          user.update_column(:settings, user.settings.merge('immich_url' => 'https://immich.a11rest.test///'))
        end
        before = user.reload.attributes
        session = decoded_account_session(client)
        remember = client.cookies['remember_user_token']
        jobs = enqueued_jobs.size
        mails = ActionMailer::Base.deliveries.size
        referer = { 'turbo' => 'http://www.example.com/users/edit', 'referer' => 'http://www.example.com/stats',
                    'browser_navigation' => 'http://www.example.com/users/edit' }[name]
        accept = name == 'turbo' ? 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml' : 'text/html'
        browser = name == 'browser_navigation'
        if browser
          accept = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,' \
                   '*/*;q=0.8,application/signed-exchange;v=b3;q=0.7'
        end
        body = browser ? URI.encode_www_form('_method' => 'post', 'authenticity_token' => account_csrf(client)) : ''
        client.post('/settings/generate_api_key', params: body, headers: {
          'CONTENT_TYPE' => 'application/x-www-form-urlencoded', 'X-CSRF-Token' => browser ? nil : account_csrf(client),
                      'Accept' => accept, 'Referer' => referer
        }.compact)
        projection = account_projection(client, user, before, session, remember, jobs, mails)
        probe = ActionDispatch::Integration::Session.new(Rails.application)
        lookups = [before['api_key'], user.api_key].map do |key|
          probe.get('/api/v1/users/me', params: { api_key: key })
          query = probe.response.status
          probe.get('/api/v1/users/me', headers: { 'Authorization' => "Bearer #{key}" })
          { 'query' => query, 'bearer' => probe.response.status }
        end
        projection.merge('name' => name, 'referer' => referer, 'accept' => accept,
                         'body' => browser ? '_method=post&authenticity_token=CSRF' : '',
                         'csrf_transport' => browser ? 'body' : 'header',
                         'key_changed' => user.api_key != before['api_key'],
                         'key_format' => user.api_key.match?(/\A[0-9a-f]{64}\z/), 'lookups' => lookups,
                         'settings_cleaned' => name == 'dirty_settings' &&
                           user.settings['immich_url'].end_with?('.test'))
      end
    end

    def account_exclusion_corpus
      %w[oauth otp cloud dirty_settings remember_only].each_with_index.map do |name, index|
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
        user = account_actor(73_600 + index)
        client = account_browser(user)
        user.update_columns(provider: 'github', uid: 'a11rest-uid') if name == 'oauth'
        user.update_column(:otp_required_for_login, true) if name == 'otp'
        allow(DawarichSettings).to receive(:self_hosted?).and_return(name != 'cloud')
        if name == 'dirty_settings'
          user.update_column(:settings, user.settings.merge('immich_url' => 'https://immich.a11rest.test///'))
        end
        if name == 'remember_only'
          seed_account_session(client,
                               decoded_account_session(client).except('warden.user.user.key'))
        end
        params = { email: "a11rest-excluded-#{index}@dawarich.test", current_password: 'a11rest-password-42' }
        params.delete(:current_password) if name == 'oauth'
        client.put('/users', params: { user: params, authenticity_token: account_csrf(client) })
        { 'name' => name, 'owner' => 'rails', 'status' => client.response.status,
          'location' => client.response.location, 'email_changed' => user.reload.email == params[:email] }
      end
    end

    it 'writes or verifies the complete A11 account contract corpus' do
      travel_to now do
        corpus = account_contract_corpus
        expected_requests = %w[
          put patch post_put post_patch blank_current missing_current no_op_blank_current wrong_current
          email_only password_only both no_op omitted_confirmation empty_confirmation mismatch_confirmation
          length_11 length_12 length_128 length_129 multibyte_11 multibyte_12 duplicate_email deleted_email
          multiple_errors blank_email duplicate_scalar_email duplicate_scalar_current malformed_encoding
          type_conflict errors_de
        ]
        expected_requests += %w[es fr pl ca zh].map { |locale| "errors_#{locale}" }
        expect(corpus.fetch(:requests).pluck('name')).to eq(expected_requests)
        expect(corpus.fetch(:api_keys).pluck('name')).to eq(
          %w[plain turbo referer invalid_resource legacy_invalid_email dirty_settings
             legacy_uppercase_invalid_email legacy_padded_valid_email browser_navigation]
        )
        turbo = corpus.fetch(:api_keys).find { |row| row['name'] == 'turbo' }
        expect(turbo.slice('status', 'location', 'changed')).to eq(
          'status' => 302, 'location' => 'http://www.example.com/users/edit', 'changed' => %w[api_key updated_at]
        )
        expect(corpus.fetch(:validation).find { |row| row['name'] == 'multiple_errors' }.fetch('errors')).to eq(
          ['Email is invalid', "Password confirmation doesn't match Password",
           'Password is too short (minimum is 12 characters)', "Current password can't be blank"]
        )
        corpus.fetch(:api_keys).each do |row|
          old_status = %w[invalid_resource legacy_uppercase_invalid_email].include?(row['name']) ? 200 : 401
          expect(row['lookups']).to eq(
            [{ 'query' => old_status, 'bearer' => old_status },
             { 'query' => 200, 'bearer' => 200 }]
          )
        end
        legacy_invalid = corpus.fetch(:api_keys).find { |row| row['name'] == 'legacy_uppercase_invalid_email' }
        expect(legacy_invalid.slice('status', 'email', 'changed', 'key_changed', 'reset_cleared')).to eq(
          'status' => 302, 'email' => 'INVALID', 'changed' => [], 'key_changed' => false, 'reset_cleared' => false
        )
        legacy_valid = corpus.fetch(:api_keys).find { |row| row['name'] == 'legacy_padded_valid_email' }
        expect(legacy_valid.slice('status', 'email', 'changed', 'key_changed', 'reset_cleared')).to eq(
          'status' => 302, 'email' => 'a11rest-legacy-73507@dawarich.test',
          'changed' => %w[api_key email reset_password_sent_at reset_password_token updated_at],
          'key_changed' => true, 'reset_cleared' => true
        )
        corpus.except(:html).each { |name, rows| account_fixture("#{name}.json", rows) }
        corpus.fetch(:html).each { |name, html| account_fixture("#{name}.html", html, json: false) }
      end
    end

    it 'preserves source-only account rejection cases' do
      travel_to now do
        rows = account_exclusion_corpus
        expect(rows.pluck('name')).to eq(%w[oauth otp cloud dirty_settings remember_only])
        expect(rows.pluck('owner').uniq).to eq(['rails'])
        expect(rows.pluck('status')).to eq([303, 303, 303, 303, 302])
        expect(rows.pluck('email_changed')).to eq([true, true, true, true, false])
        account_fixture('exclusions.json', rows)
      end
    end
  end

  def write_json(path, data) = File.write(path, "#{JSON.pretty_generate(data)}\n")

  def qr_entry(payload)
    code = RQRCode::QRCode.new(payload).qrcode
    { payload:, version: code.version, modules: code.modules.map { |row| row.map { _1 ? '1' : '0' }.join },
      svg: ResponsiveQrSvg.call(payload) }
  end

  context 'A8 visit settings' do
    let(:now) { Time.utc(2026, 10, 3, 10, 0, 0) }

    def a8_settings_json(path, data)
      File.write(path, "#{Oj.dump(data.deep_stringify_keys, mode: :strict, float_precision: 0, indent: 2)}\n")
    end

    def a8_settings_user(id, plan: :pro, settings: {})
      user = member(id, plan:, consent: :declined, settings:)
      user.update_columns(visits_redetected_at: nil, theme: 'dark')
      user.reload
    end

    def a8_settings_graph(user, others = [])
      ids = [user, *others].map(&:id)
      { users: [user, *others].map { user_json(_1).merge(visits_redetected_at: iso(_1.visits_redetected_at)) },
        families: Family.where(creator_id: ids).order(:id).map do
          _1.attributes.transform_values do |v|
            v.respond_to?(:utc) ? iso(v) : v
          end
        end,
        family_memberships: Family::Membership.where(user_id: ids).order(:id).map { _1.attributes.transform_values { |v| v.respond_to?(:utc) ? iso(v) : v } } }
    end

    def a8_settings_capture(name, user, method, path, params: {}, status: 200, others: [])
      reset!
      Rails.cache.clear
      sign_in user if user
      token = nil
      if method != :get
        get '/settings/visits'
        token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
      end
      before = user ? a8_settings_graph(user, others) : {}
      clear_enqueued_jobs
      public_send(method, path, params:, headers: token ? { 'X-CSRF-Token' => token } : {})
      expect(response.status).to eq(status), name
      yield if block_given?
      doc = Nokogiri::HTML5(response.body)
      doc.css('input[name="authenticity_token"]').each { _1['value'] = 'CSRF' }
      doc.css('meta[name="csrf-token"]').each { _1['content'] = 'CSRF' }
      content = doc.at_css('body > div.container > div.w-full > div.flex')
      body = content ? content.inner_html : response.body
      target = fixtures.join('a8vv/settings')
      FileUtils.mkdir_p(target)
      File.write(target.join("#{name}.html"), body)
      data = { method: method.to_s.upcase, path:, params:, now: now.iso8601,
               self_hosted: DawarichSettings.self_hosted?,
               before:, after: user ? a8_settings_graph(user.reload, others) : {},
               status: response.status, content_type: response.media_type, location: response.location,
               flash: flash.to_hash,
               headers: response.headers.slice('Content-Type', 'Location', 'Vary', 'Cache-Control',
                                               'X-Frame-Options', 'Referrer-Policy', 'X-Content-Type-Options'),
               jobs: enqueued_jobs.map { { job: _1[:job].name, args: _1[:args] } } }
      a8_settings_json(target.join("#{name}.json"), data)
    end

    it 'writes A8 visit settings and redirects' do
      travel_to now do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user = a8_settings_user(8801, settings: { 'visit_min_points' => 3, 'unrelated' => 'survives' })
        a8_settings_capture('partial_save', user, :patch, '/settings/visits',
                            params: { settings: { visit_radius_meters: '75' } }, status: 302) do
          expect(response).to redirect_to('/settings/visits')
          expect(user.reload.settings).to include('visit_radius_meters' => 75, 'visit_min_points' => 3,
                                                  'unrelated' => 'survives')
        end
        defaults = a8_settings_user(8802)
        a8_settings_capture('defaults', defaults, :get, '/settings/visits') do
          doc = Nokogiri::HTML5(response.body)
          expect(doc.at_css('#settings_visit_radius_meters')['value']).to eq('100')
          expect(doc.at_css('#settings_visit_min_points')['value']).to eq('3')
          expect(doc.at_css('#settings_visit_min_duration_minutes')['value']).to eq('5')
        end
        [['raw_zero', 'visit_radius_meters', '0', 0, 5],
         ['raw_negative', 'visit_min_points', '-2', -2, 2],
         ['raw_nonnumeric', 'visit_radius_meters', 'nonsense', 0,
          5]].each_with_index do |(name, key, raw, stored, shown), i|
          raw_user = a8_settings_user(8810 + i)
          a8_settings_capture(name, raw_user, :patch, '/settings/visits',
                              params: { settings: { key => raw } }, status: 302) do
            expect(response).to redirect_to('/settings/visits')
            expect(raw_user.reload.settings.fetch(key)).to eq(stored)
            expect(raw_user.safe_settings.public_send(key)).to eq(shown)
          end
        end
        [['cooldown_nil', nil, false], ['cooldown_recent', now - 3599, true],
         ['cooldown_exact_hour', now - 3600, false]].each_with_index do |(name, stamp, disabled), i|
          cooldown_user = a8_settings_user(8820 + i)
          cooldown_user.update_columns(visits_redetected_at: stamp)
          a8_settings_capture(name, cooldown_user.reload, :get, '/settings/visits') do
            button = Nokogiri::HTML5(response.body).at_css('form[action="/visits/redetections"] button')
            expect(button.key?('disabled')).to eq(disabled)
          end
        end
        lite = a8_settings_user(8830, plan: :lite)
        a8_settings_capture('lite_hint', lite, :get, '/settings/visits') do
          hint = I18n.t('settings.visits.redetect_panel.on_the_lite_plan_re_detection_covers_your_visible_12')
          expect(response.body).to include(hint)
        end
        a8_settings_capture('signed_out', nil, :get, '/settings/visits', status: 302) do
          expect(response).to redirect_to('/users/sign_in')
        end
        [['navigation_default', nil, 'confirmed'], ['navigation_suggested', 'suggested', 'suggested'],
         ['navigation_declined', 'declined', 'declined'], ['navigation_empty', '', '']].each do |name, value, wanted|
          path = value.nil? ? '/visits' : "/visits?status=#{value}"
          a8_settings_capture(name, nil, :get, path, status: 302) do
            expect(response).to redirect_to("/map/v2?panel=timeline&date=today&status=#{wanted}")
          end
        end
        allowed = a8_settings_user(8840)
        a8_settings_capture('redetect_allowed', allowed, :post, '/visits/redetections', status: 302) do
          expect(response).to redirect_to('/settings/visits')
          expect(enqueued_jobs.select { _1[:job] == Visits::FullHistoryRedetectJob }.map { _1[:args] }).to eq([[8840]])
          expect(allowed.reload.visits_redetected_at).to be_nil
        end
        recent = a8_settings_user(8841)
        recent.update_columns(visits_redetected_at: now - 10)
        a8_settings_capture('redetect_recent', recent.reload, :post, '/visits/redetections', status: 429) do
          expect(response.location).to eq('http://www.example.com/settings/visits')
          expect(enqueued_jobs).to be_empty
          message = I18n.t('controllers.visits.redetections.re_detect_ran_recently_try_again_in_an_hour')
          expect(flash[:alert]).to eq(message)
        end
      end
    end

    it 'writes A8 inherited family detection access' do
      travel_to now do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        owner = a8_settings_user(8850, plan: :family)
        user = a8_settings_user(8851, plan: :lite)
        family = Family.create!(id: 8850, name: 'Synthetic A8 family', creator: owner, access_until: now + 1.day)
        Family::Membership.create!(id: 8850, family:, user: owner, role: :owner)
        Family::Membership.create!(id: 8851, family:, user:, role: :member)
        expect(user.reload.inherited_family_access?).to be(true)
        expect(user.full_access?).to be(true)
        a8_settings_capture('family_access', user, :get, '/settings/visits', others: [owner]) do
          hint = I18n.t('settings.visits.redetect_panel.on_the_lite_plan_re_detection_covers_your_visible_12')
          expect(response.body).not_to include(hint)
          expect(response.body).to include('action="/visits/redetections"')
        end
      end
    end
  end

  def heatmap_entry(year, today, months)
    stats = months.map { |month, daily| Stat.new(year:, month:, daily_distance: daily) }
    travel_to(Time.find_zone('Europe/Berlin').local(today.year, today.month, today.day, 12)) do
      Time.use_zone('Europe/Berlin') do
        result = Insights::ActivityHeatmapCalculator.new(stats, year).call
        weeks = helper.heatmap_week_columns(year)
        { year:, today: today.iso8601, stats: months.map { |month, daily| { month:, daily_distance: daily } },
          daily_data: result.daily_data, activity_levels: result.activity_levels, active_days: result.active_days,
          current_streak: result.current_streak, longest_streak: result.longest_streak,
          longest_streak_start: result.longest_streak_start&.iso8601,
          longest_streak_end: result.longest_streak_end&.iso8601,
          weeks: [weeks.first.iso8601, weeks.last.iso8601, weeks.size],
          month_labels: helper.heatmap_month_labels(weeks, year),
          most_recent: helper.most_recent_active_date(result.daily_data),
          levels: result.daily_data.transform_values { helper.calculate_activity_level(_1, result.activity_levels) } }
      end
    end
  end

  it 'writes the corpus and the QR tables and checks phoenix:time_zones' do
    long_key = "a5s3-k-#{'0' * 57}"
    long_host = 'https://a-really-long-self-hosted-instance-name.home.example.org:8443/'
    payloads = [
      { 'server_url' => 'http://www.example.com/', 'api_key' => long_key },
      { 'server_url' => long_host, 'api_key' => long_key },
      { 'server_url' => 'http://localhost:3000/', 'api_key' => 'a5s3-k-1' },
      { 'server_url' => 'http://a.test/?a=1&b=2', 'api_key' => 'k' }
    ].map(&:to_json) + ['otpauth://totp/Dawarich:e2e@dawarich.test?secret=AAAAAAAAAAAAAAAA&issuer=Dawarich',
                        'x', 'hello world', 'a5s3-k-14', 'Grüße aus Köln', 'y' * 300]
    times = [['2026-09-25T10:15:00+00:00', 'Europe/Berlin'], ['2026-01-05T23:30:00Z', 'Europe/Berlin'],
             ['2026-03-08T07:30:00+00:00', 'America/Havana'], ['2026-09-25 10:15:00', 'UTC'],
             ['2026-09-25', 'Asia/Tokyo'], ['not a time', 'UTC'], ['2026-13-45', 'UTC']]
    table = RQRCodeCore::QRRSBlock::RS_BLOCK_TABLE

    write_json(
      root.join('priv/qr_tables.json'),
      max_bits_h: RQRCodeCore::QRMAXBITS[:h],
      rs_blocks_h: (0...40).map { table[(_1 * 4) + 3] },
      positions: RQRCodeCore::QRUtil::PATTERN_POSITION_TABLE
    )

    write_json(
      fixtures.join('settings_corpus.json'),
      time_zone_options: zones,
      qr: payloads.map { qr_entry(_1) },
      times: times.map do |value, zone|
        parsed = Time.use_zone(zone) do
          Time.zone.parse(value)
        rescue ArgumentError
          nil
        end
        { value:, zone:, output: parsed && I18n.l(parsed, format: :long) }
      end,
      heatmap: [
        heatmap_entry(2024, Date.new(2026, 9, 26),
                      [[3, [[5, 10_000], [6, 5_400], [7, 14_000], [20, 9_000]]], [4, { '10' => 12_000 }]]),
        heatmap_entry(2026, Date.new(2026, 9, 26),
                      [[9, { '24' => 1_000, '25' => 2_000, '26' => 3_000, '-1' => 700 }],
                       [8, [[31, 500], [30, 0], [29, 400]]]]),
        heatmap_entry(2025, Date.new(2026, 9, 26), [[12, [[31, 900]]], [1, [[1, 800], [1, 1_600], [2, '300']]]]),
        heatmap_entry(2023, Date.new(2026, 9, 26), [])
      ]
    )

    Rails.application.load_tasks unless Rake::Task.task_defined?('phoenix:time_zones')
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'time_zones.json')
      Rake::Task['phoenix:time_zones'].reenable
      Rake::Task['phoenix:time_zones'].invoke(path)
      expect(JSON.parse(File.read(path))['options']).to eq(helper.settings_time_zone_options)
    ensure
      Rake::Task['phoenix:time_zones'].reenable
    end
  end

  let(:now) { Time.utc(2026, 9, 26, 12, 0, 0) }

  around do |example|
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  def iso(time) = time&.utc&.iso8601(6)

  def member(id, plan: :pro, status: :active, admin: false, provider: nil, consent: nil, settings: {},
             active_until: Time.utc(3026, 1, 1), source: :none)
    user = create(:user, id:, email: "a5s3-#{id}@dawarich.test", admin:)
    user.update_columns(
      settings: { 'timezone' => 'Europe/Berlin', 'onboarding_completed' => true }.merge(settings),
      plan: User.plans[plan], status: User.statuses[status], active_until:, provider:,
      uid: provider && "a5s3-uid-#{id}", changelog_consent: consent && User.changelog_consents[consent],
      subscription_source: User.subscription_sources[source], points_count: 1_234_567, api_key: "a5s3-k-#{id}"
    )
    user.reload
  end

  def toponym(country, *cities) = { 'country' => country, 'cities' => cities.map { { 'city' => _1 } } }

  def daily(year, month, distances)
    (1..Date.new(year, month, -1).day).map { |day| [day, distances.fetch(day, 0)] }
  end

  def stat(id, user, year, month, distance, **attrs)
    Stat.create!({ id:, user:, year:, month:, distance:, daily_distance: daily(year, month, {}), toponyms: [],
                   sharing_settings: {}, sharing_uuid: format('00000000-0000-4000-8000-%012d', id),
                   created_at: now - 3.days, updated_at: now - 2.days }.merge(attrs))
  end

  def source(id, user, base_url, status: :active, importing: false, last_synced_at: nil, last_error: nil,
             created_at: now - 3.days)
    TripSource.insert_all([{ id:, user_id: user.id, provider: 'trek', base_url:, status: TripSource.statuses[status],
                             importing:, last_synced_at:, last_error:, created_at:, updated_at: created_at }])
  end

  def user_json(user)
    { id: user.id, email: user.email, settings: user.settings, plan: User.plans[user.plan],
      status: User.statuses[user.status], active_until: iso(user.active_until), api_key: user.api_key,
      points_count: user.points_count, theme: user.theme, admin: user.admin, provider: user.provider,
      changelog_consent: user.changelog_consent && User.changelog_consents[user.changelog_consent],
      subscription_source: User.subscription_sources[user.subscription_source] }
  end

  def capture(name, user, path, self_hosted: true, smtp: true, two_factor: false, supporter: { supporter: false })
    Rails.cache.clear
    allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
    allow(DawarichSettings).to receive(:email_configured?).and_return(smtp)
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(two_factor)
    allow_any_instance_of(Supporter::VerifyEmail).to receive(:call).and_return(supporter)
    allow_any_instance_of(Supporter::VerifyGithubUsername).to receive(:call).and_return(supporter)
    allow_any_instance_of(UserHelper).to receive(:settings_time_zone_options).and_return(zones)
    sign_in user
    get path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML5(response.body)
    doc.css('input[name="authenticity_token"]').each { |node| node['value'] = 'CSRF' }
    body = doc.at_css('body > div.container > div.w-full > div.flex').inner_html
              .gsub(/token=[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/, 'token=UPGRADE_TOKEN')
    File.write(fixtures.join("settings/#{name}.html"), body)
    write_json(fixtures.join("settings/#{name}.json"), {
                 path:, title: doc.at_css('title').text, now: now.iso8601, self_hosted:, smtp:, two_factor:,
      supporter: supporter.transform_keys(&:to_s), user: user_json(user),
      stats: user.stats.order(:id).map do |s|
        { id: s.id, year: s.year, month: s.month, distance: s.distance,
          daily_distance: s.read_attribute(:daily_distance), toponyms: s.read_attribute(:toponyms),
          created_at: iso(s.created_at), updated_at: iso(s.updated_at) }
      end,
      trip_sources: TripSource.where(user_id: user.id).order(:id).map do |t|
        { id: t.id, provider: t.provider, base_url: t.base_url, importing: t.importing,
          last_synced_at: iso(t.last_synced_at), last_error: t.last_error, status: TripSource.statuses[t.status],
          created_at: iso(t.created_at), updated_at: iso(t.updated_at) }
      end
               })
    sign_out user
  end

  it 'writes the settings, account and insights pages' do
    FileUtils.mkdir_p(fixtures.join('settings'))
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('JWT_SECRET_KEY').and_return('phoenix-a5-jwt-fixture-secret-not-for-production')

    travel_to now do
      capture('general_en', member(5321), '/settings/general')
      capture('general_supporter_en',
              member(5322, consent: :granted, settings: { 'supporter_email' => 'a5s3-fan@dawarich.test' }),
              '/settings/general', supporter: { supporter: true, platform: 'patreon' })
      capture('general_unverified_en',
              member(5323, consent: :declined,
                           settings: { 'timezone' => 'Berlin', 'supporter_github_username' => 'a5s3-octo',
                                       'digest_emails_enabled' => false, 'news_emails_enabled' => false }),
              '/settings/general')
      capture('general_nosmtp_en', member(5324), '/settings/general', smtp: false)
      capture('general_cloud_en', member(5325), '/settings/general', self_hosted: false)
      capture('general_admin_en', member(5326, admin: true, settings: { 'monthly_digest_emails_enabled' => false }),
              '/settings/general', two_factor: true)

      connected = member(5311, settings: {
                           'immich_url' => 'https://immich.a5s3.test', 'immich_api_key' => 'a5s3-k-immich',
                           'immich_skip_ssl_verification' => true, 'immich_connection_status' => 'ok',
                           'photoprism_url' => 'https://photoprism.a5s3.test', 'photoprism_api_key' => 'a5s3-k-photo',
                           'photoprism_connection_status' => 'failed',
                           'airtrail_url' => 'https://airtrail.a5s3.test', 'airtrail_api_key' => 'a5s3-k-air',
                           'airtrail_last_synced_at' => '2026-09-25T10:15:00+00:00',
                           'teslamate_url' => 'https://tesla.a5s3.test', 'teslamate_username' => 'a5s3-driver',
                           'teslamate_password' => 'a5s3-k-pw', 'teslamate_api_token' => 'a5s3-k-tok',
                           'teslamate_last_synced_at' => '2026-09-24T08:00:00Z', 'teslamate_connection_status' => 'ok'
                         })
      source(53_111, connected, 'https://trek-one.a5s3.test', last_synced_at: now - 1.day)
      source(53_112, connected, 'https://trek-two.a5s3.test', status: :disabled, last_error: 'TREK answered 401',
                                                              created_at: now - 2.days)
      source(53_113, connected, 'https://trek-three.a5s3.test', importing: true, created_at: now - 1.day)
      %w[immich photoprism airtrail teslamate trek].each do |service|
        capture("integrations_#{service}_en", connected, "/settings/integrations?service=#{service}")
      end
      capture('integrations_default_en', connected, '/settings/integrations')
      capture('integrations_unknown_en', connected, '/settings/integrations?service=geocoding')
      admin = member(5312, admin: true, settings: { 'airtrail_url' => 'https://airtrail.a5s3.test',
                                                    'airtrail_last_synced_at' => 'not a time' })
      capture('integrations_admin_en', admin, '/settings/integrations')
      capture('integrations_airtrail_raw_en', admin, '/settings/integrations?service=airtrail')
      capture('integrations_lite_en', member(5313, plan: :lite), '/settings/integrations', self_hosted: false)
      capture('integrations_cloud_oauth_en', member(5314, provider: 'github'), '/settings/integrations',
              self_hosted: false)

      capture('account_en', member(5331), '/users/edit')
      capture('account_oidc_en', member(5332, provider: 'openid_connect'), '/users/edit')
      capture('account_cloud_en', member(5333), '/users/edit', self_hosted: false)
      capture('account_trial_en', member(5334, status: :trial, active_until: now + 5.days), '/users/edit',
              self_hosted: false)
      capture('account_trial_auto_en', member(5335, status: :trial, active_until: now + 5.days, source: :paddle),
              '/users/edit', self_hosted: false)
      capture('account_pending_en', member(5336, status: :pending_payment), '/users/edit', self_hosted: false)
      capture('account_expired_en', member(5337, active_until: now - 2.days), '/users/edit', self_hosted: false)
      capture('account_cloud_oauth_en', member(5338, provider: 'google_oauth2'), '/users/edit', self_hosted: false)

      reader = member(5301)
      stat(53_011, reader, 2024, 3, 38_400, daily_distance: daily(2024, 3, { 5 => 10_000, 6 => 5_400, 7 => 14_000,
                                                                             20 => 9_000 }),
                                           toponyms: [toponym('Germany', 'Berlin'), toponym('Czechia', 'Prague')])
      stat(53_012, reader, 2024, 4, 12_000, daily_distance: daily(2024, 4, { 10 => 12_000 }),
                                           toponyms: [toponym('Germany', 'Berlin')])
      stat(53_013, reader, 2023, 7, 20_000, daily_distance: daily(2023, 7, { 14 => 20_000 }),
                                           toponyms: [toponym('Germany', 'Berlin'), toponym(nil, 'Nowhere'),
                                                      { 'country' => 'Austria', 'cities' => [] }])
      capture('insights_en', reader, '/insights')
      capture('insights_year_en', reader, '/insights?year=2023')
      capture('insights_all_en', reader, '/insights?year=all')
      capture('insights_month_en', reader, '/insights?year=2024&month=3')

      current = member(5302)
      stat(53_021, current, 2026, 9, 6_700,
           daily_distance: { '24' => 1_000, '25' => 2_000, '26' => 3_000, '-1' => 700 },
           toponyms: [toponym('Germany', 'Leipzig')])
      stat(53_022, current, 2026, 8, 900, daily_distance: [[31, 500], [30, 0], [29, 400]])
      capture('insights_current_en', current, '/insights')

      capture('insights_empty_en', member(5303), '/insights?year=2020')

      lite = member(5304, plan: :lite)
      stat(53_041, lite, 2024, 6, 30_000, daily_distance: daily(2024, 6, { 2 => 30_000 }),
                                         toponyms: [toponym('Germany', 'Berlin')])
      stat(53_042, lite, 2025, 10, 8_000, daily_distance: daily(2025, 10, { 3 => 8_000 }),
                                         toponyms: [toponym('Germany', 'Berlin')])
      stat(53_043, lite, 2026, 2, 4_000, daily_distance: daily(2026, 2, { 4 => 4_000 }),
                                        toponyms: [toponym('Czechia', 'Prague')])
      capture('insights_lite_locked_en', lite, '/insights?year=2024', self_hosted: false)
      capture('insights_lite_en', lite, '/insights', self_hosted: false)

      miles = member(5305, settings: { 'maps' => { 'distance_unit' => 'mi' } })
      stat(53_051, miles, 2024, 5, 16_093, daily_distance: daily(2024, 5, { 9 => 16_093 }))
      capture('insights_mi_en', miles, '/insights?year=2024')

      legacy = member(5306)
      stat(53_061, legacy, 2024, 12, 100_000, daily_distance: daily(2024, 12, { 24 => 100_000 }))
      stat(53_062, legacy, 2024, 11, 5_000, daily_distance: daily(2024, 11, { 1 => 5_000 }))
      Stat.where(id: 53_061).update_all(month: 13)
      capture('insights_legacy_en', legacy, '/insights?year=2024')
    end
  end
end
