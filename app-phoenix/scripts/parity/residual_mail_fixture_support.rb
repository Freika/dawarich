# frozen_string_literal: true

module ResidualMailFixtureSupport
  SENDER = 'Dawarich <residual@dawarich.test>'
  EMAIL = 'residual&safe@dawarich.test'
  OLD_EMAIL = 'old&safe@dawarich.test'
  REQUESTER = %q(requester<>&"'@dawarich.test)
  TOKEN = 'a12c-synthetic-token-not-issued'
  LOCALES = { 'en' => [{ 'locale' => 'en' }, :en], 'de' => [{ 'locale' => ' DE ' }, :en],
              'fallback_fr' => [{ 'locale' => 'invalid' }, :fr] }.freeze

  def with_mail_defaults
    defaults = ApplicationMailer.default_params
    urls = ActionMailer::Base.default_url_options.dup
    ApplicationMailer.default(from: SENDER)
    ActionMailer::Base.default_url_options = { host: 'www.example.com', protocol: 'http' }
    allow(Devise).to receive(:mailer_sender).and_return(SENDER)
    yield
  ensure
    ApplicationMailer.default_params = defaults
    ActionMailer::Base.default_url_options = urls
  end

  def content_user(settings)
    User.new(id: 460_001, email: EMAIL, settings: { 'timezone' => 'UTC' }.merge(settings))
  end

  def part_tree(message)
    tree = { 'type' => message.mime_type, 'charset' => message.charset,
             'transfer' => message.content_transfer_encoding }
    if message.multipart?
      tree['parts'] = message.parts.map { |part| part_tree(part) }
    else
      tree['body'] = message.body.decoded.force_encoding(message.charset || 'UTF-8').gsub("\r\n", "\n")
    end
    tree
  end

  def message_content(message)
    wire = Mail.read_from_string(message.encoded)
    { 'subject' => message.subject, 'from' => message.from, 'from_header' => message[:from].value,
      'to' => message.to, 'reply_to' => message.reply_to,
      'tree' => part_tree(message), 'wire_tree' => part_tree(wire) }
  end

  def part_shape(tree)
    tree.except('body', 'parts').merge('parts' => tree.fetch('parts', []).map { |part| part_shape(part) })
  end

  def content_case(kind, name, settings, ambient)
    user = content_user(settings)
    request = Family::LocationRequest.new(id: 460_002, requester: User.new(id: 460_003, email: REQUESTER),
                                          target_user: user, expires_at: 24.hours.from_now)
    message = I18n.with_locale(ambient) do
      case kind
      when 'location_request' then FamilyMailer.location_request(request).message
      when 'reset_password_instructions', 'unlock_instructions'
        DeviseMailer.public_send(kind, user, TOKEN).message
      when 'email_changed_current' then DeviseMailer.email_changed(user, to: OLD_EMAIL).message
      when 'password_change' then DeviseMailer.password_change(user).message
      else UsersMailer.with(user:).public_send(kind).message
      end
    end
    { 'id' => "#{kind}_#{name}", 'kind' => kind, 'email' => EMAIL, 'settings' => user.settings,
      'ambient_locale' => ambient.to_s, 'locale' => (user.preferred_locale || ambient).to_s,
      'now' => Time.current.utc.iso8601, 'request_id' => request.id, 'requester' => REQUESTER,
      'token' => %w[reset_password_instructions unlock_instructions].include?(kind) ? TOKEN : nil,
      'base_url' => 'http://www.example.com' }.merge(message_content(message))
  end

  def residual_content
    deliveries = ActionMailer::Base.deliveries.length
    queued = enqueued_jobs.length
    with_mail_defaults do
      cases = %w[otp_account_locked test_email location_request reset_password_instructions
                 unlock_instructions email_changed_current password_change].flat_map do |kind|
        rows = LOCALES.map { |name, (settings, ambient)| content_case(kind, name, settings, ambient) }
        if kind == 'test_email'
          rows << content_case(kind, 'berlin', { 'locale' => 'en', 'timezone' => 'Europe/Berlin' }, :en)
          rows << content_case(kind, 'invalid_zone', { 'locale' => 'en', 'timezone' => 'invalid' }, :en)
        end
        rows
      end
      expect(ActionMailer::Base.deliveries.length).to eq(deliveries)
      expect(enqueued_jobs.length).to eq(queued)
      { 'cases' => cases, 'confirmation' => confirmation_absence }
    end
  end

  def confirmation_absence
    fields = %w[confirmation_token confirmed_at confirmation_sent_at unconfirmed_email]
    routes = Rails.application.routes.routes.filter_map do |route|
      route.defaults[:controller]
    end.grep(%r{(?:^|/)confirmations$})
    { 'module' => User.devise_modules.include?(:confirmable), 'fields' => User.column_names & fields,
      'controllers' => routes, 'producer' => User.new.respond_to?(:send_confirmation_instructions),
      'dormant_template' => Rails.root.join('app/views/devise/mailer/confirmation_instructions.html.erb').file?,
      'reconfirmable_config' => Devise.reconfirmable }
  end

  def assert_content(fixture)
    expect(fixture.fetch('confirmation')).to eq(
      'module' => false, 'fields' => [], 'controllers' => [], 'producer' => false,
      'dormant_template' => true, 'reconfirmable_config' => true
    )
    fixture.fetch('cases').each do |row|
      kind = row.fetch('kind')
      expected_to = kind == 'email_changed_current' ? OLD_EMAIL : EMAIL
      expect(row.fetch('to')).to eq([expected_to])
      expect(row.fetch('from')).to eq(['residual@dawarich.test'])
      expect(row.fetch('from_header')).to eq(SENDER)
      auth_kind = kind.match?(/instructions|email_changed|password_change/)
      expect(row.fetch('reply_to')).to eq(auth_kind ? ['residual@dawarich.test'] : nil)
      expect(part_shape(row.fetch('tree'))).to eq(part_shape(row.fetch('wire_tree')))
      expect(row.fetch('tree') == row.fetch('wire_tree')).to be(true), "wire parts differ: #{row.fetch('id')}"
      locale = row.fetch('locale')
      subject_key = case kind
                    when 'otp_account_locked', 'test_email' then "mailers.users.#{kind}.subject"
                    when 'location_request' then 'mailers.family.location_request.subject'
                    else "devise.mailer.#{kind.sub('_current', '')}.subject"
                    end
      expected_subject = I18n.t(subject_key, locale:, requester: REQUESTER)
      expect(row.fetch('subject') == expected_subject).to be(true), "subject differs: #{row.fetch('id')}"
      tree = row.fetch('tree')
      if %w[otp_account_locked location_request].include?(kind)
        expect(tree.fetch('type')).to eq('multipart/alternative')
        expect(tree.fetch('parts').pluck('type')).to eq(%w[text/plain text/html])
        html = tree.fetch('parts').last.fetch('body')
        address = kind == 'location_request' ? REQUESTER : EMAIL
        expect(html.include?(ERB::Util.html_escape(address))).to be(true), 'HTML must escape the address'
      else
        expect(tree.fetch('type')).to eq('text/html')
        expect(tree.fetch('charset')).to eq('UTF-8')
      end
      if kind == 'email_changed_current'
        expect(tree.fetch('body').include?(ERB::Util.html_escape(EMAIL))).to be(true), 'new email body missing'
        expect(tree.fetch('body').include?(ERB::Util.html_escape(OLD_EMAIL))).to be(true), 'old email greeting missing'
      end
      next unless kind.end_with?('instructions')

      action = kind == 'reset_password_instructions' ? 'password/edit?reset_password_token=' : 'unlock?unlock_token='
      expect(tree.fetch('body').include?("http://www.example.com/users/#{action}#{TOKEN}")).to be(true),
                                                                                               'recovery URL differs'
    end
  end

  def fresh_intent_user(name, settings = {})
    user = User.new(email: "old-#{name}&safe@dawarich.test", password: 'a12c-safe-password',
                    status: :active, active_until: Time.utc(2099), settings:)
    user.skip_auto_trial = true
    user.skip_family_sync = true
    user.save!
    user
  end

  def notification_intent(name, kind, preference: ' DE ', ambient: :fr, changed: true, flag: true, skip: false,
                          failure: false)
    user = fresh_intent_user(name, { 'locale' => preference })
    old_email = user.email
    new_email = "new-#{name}&safe@dawarich.test"
    notifications = []
    callbacks = []
    allow(DeviseMailer).to receive(kind).and_wrap_original do |original, record, *args|
      callbacks << { 'kind' => kind.to_s, 'opts' => args.last.is_a?(Hash) ? args.last.stringify_keys : {} }
      original.call(record, *args)
    end
    allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_now) do |delivery|
      message = delivery.message
      expected_body_email = kind == :email_changed ? new_email : old_email
      body_has_address = message.body.decoded.include?(ERB::Util.html_escape(expected_body_email))
      expect(body_has_address).to be(true), 'callback body address differs'
      notifications << { 'kind' => kind.to_s, 'to' => message.to, 'body_email' => expected_body_email,
                         'subject' => message.subject, 'locale' => (user.preferred_locale || ambient).to_s,
                         'delivery' => 'deliver_now', 'owner' => 'rails' }
      raise IOError, 'synthetic callback delivery failure' if failure
    end
    User.send_email_changed_notification = kind == :email_changed && flag
    User.send_password_change_notification = kind == :password_change && flag
    user.public_send("skip_#{kind == :email_changed ? 'email_changed' : 'password_change'}_notification!") if skip
    attrs = if kind == :email_changed
              { email: changed ? new_email : old_email }
            else
              changed ? { password: 'a12c-changed-password' } : {}
            end
    error = nil
    I18n.with_locale(ambient) do
      user.update!(attrs)
    rescue IOError => e
      error = e.class.name
    end
    { 'id' => name, 'changed' => changed, 'flag' => flag, 'skip' => skip,
      'old_email' => old_email, 'new_email' => kind == :email_changed && changed ? new_email : old_email,
      'persisted_email' => user.reload.email,
      'preference' => preference, 'ambient' => ambient.to_s, 'callbacks' => callbacks,
      'notifications' => notifications, 'error' => error }
  end

  def otp_intents
    user = fresh_intent_user('otp', { 'locale' => 'de' })
    key = "otp_lockout_email_throttle/user/#{user.id}"
    Rails.cache.delete(key)
    cases = []
    [
      ['otp_below_threshold', 9, false], ['otp_at_threshold', 1, false],
      ['otp_already_locked', 1, false], ['otp_throttled', 10, true], ['otp_throttle_cleared', 10, true]
    ].each do |name, attempts, unlock|
      user.update_columns(failed_otp_attempts: 0, otp_locked_at: 31.minutes.ago) if unlock
      Rails.cache.delete(key) if name == 'otp_throttle_cleared'
      clear_enqueued_jobs
      I18n.with_locale(:fr) { attempts.times { user.register_failed_otp_attempt! } }
      jobs = enqueued_jobs.select { |job| job[:job] == ActionMailer::MailDeliveryJob }
      cases << { 'id' => name, 'failed_attempts' => user.reload.failed_otp_attempts,
                 'locked' => user.otp_locked?, 'throttle' => Rails.cache.read(key) == true,
                 'notifications' => jobs.map do |job|
                   { 'mailer' => job[:args][0], 'action' => job[:args][1], 'delivery' => job[:args][2],
                     'locale' => job['locale'], 'owner' => 'rails', 'recipient' => user.email,
                     'params_user' => job[:args].last.dig('params', 'user', '_aj_globalid') == user.to_global_id.to_s }
                 end }
    end
    user.update_columns(failed_otp_attempts: 9, otp_locked_at: nil)
    Rails.cache.delete(key)
    clear_enqueued_jobs
    adapter = ActiveJob::Base.queue_adapter
    allow(adapter).to receive(:enqueue).and_raise(IOError, 'synthetic OTP enqueue failure')
    expect { user.register_failed_otp_attempt! }.to raise_error(IOError, 'synthetic OTP enqueue failure')
    cases << { 'id' => 'otp_enqueue_failure', 'failed_attempts' => user.reload.failed_otp_attempts,
               'locked' => user.otp_locked?, 'throttle' => Rails.cache.read(key) == true,
               'notifications' => [], 'error' => 'IOError' }
    allow(adapter).to receive(:enqueue).and_call_original
    cases
  ensure
    Rails.cache.delete(key) if key
    clear_enqueued_jobs
  end

  def recovery_dependencies
    %w[mail lifecycle token effects].map do |name|
      fixture = name == 'token' ? 'tokens' : name
      oracle = "app-phoenix/test/support/auth/recovery/#{name}_oracle.rb"
      corpus = "app-phoenix/test/fixtures/auth/recovery/#{fixture}.json"
      expect(Rails.root.join(oracle).file?).to be(true)
      expect(Rails.root.join(corpus).file?).to be(true)
      { 'oracle' => oracle, 'fixture' => corpus }
    end
  end

  def residual_auth_intents
    flags = [User.send_email_changed_notification, User.send_password_change_notification]
    rails_logger = Rails.logger
    mail_logger = ActionMailer::Base.logger
    output = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(output)
    ActionMailer::Base.logger = Rails.logger
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    with_mail_defaults do
      cases = [
        notification_intent('email_changed_preferred', :email_changed),
        notification_intent('email_changed_ambient', :email_changed, preference: 'invalid'),
        notification_intent('email_unchanged', :email_changed, changed: false),
        notification_intent('email_flag_off', :email_changed, flag: false),
        notification_intent('email_skipped', :email_changed, skip: true),
        notification_intent('password_changed_preferred', :password_change),
        notification_intent('password_changed_ambient', :password_change, preference: ''),
        notification_intent('password_unchanged', :password_change, changed: false),
        notification_intent('password_flag_off', :password_change, flag: false),
        notification_intent('password_skipped', :password_change, skip: true),
        notification_intent('email_delivery_failure', :email_changed, failure: true)
      ]
      cases.concat(otp_intents)
      markers = [TOKEN, EMAIL, REQUESTER, 'http://www.example.com/users/password', '<p>']
      expect(markers.none? { |marker| output.string.include?(marker) }).to be(true), 'mail marker leaked to logs'
      { 'cases' => cases, 'confirmation' => confirmation_absence, 'dependencies' => recovery_dependencies,
        'ownership' => { 'reset_password_instructions' => 'native_supported_recovery',
                         'unlock_instructions' => 'native_supported_recovery', 'otp_account_locked' => 'rails',
                         'email_changed' => 'rails_cloud', 'password_change' => 'rails_cloud',
                         'confirmation' => 'absent' },
        'logs_contain_mail_markers' => false }
    end
  ensure
    User.send_email_changed_notification, User.send_password_change_notification = flags
    Rails.logger = rails_logger
    ActionMailer::Base.logger = mail_logger
  end

  def assert_auth_intents(fixture)
    fixture.fetch('cases').first(11).each do |row|
      suppressed = !row.fetch('changed') || !row.fetch('flag') || row.fetch('skip')
      expect(row.fetch('notifications').length).to eq(suppressed ? 0 : 1)
      expect(row.fetch('callbacks').length).to eq(suppressed ? 0 : 1)
      next if suppressed

      notification = row.fetch('notifications').sole
      email_change = notification.fetch('kind') == 'email_changed'
      expect(notification.fetch('to')).to eq([row.fetch('old_email')])
      expect(notification.fetch('body_email')).to eq(row.fetch('new_email'))
      expect(row.fetch('callbacks').sole.fetch('opts')).to eq(email_change ? { 'to' => row.fetch('old_email') } : {})
      expect(notification.fetch('locale')).to eq(row.fetch('id').end_with?('ambient') ? 'fr' : 'de')
      expect(row.fetch('error')).to eq(row.fetch('id') == 'email_delivery_failure' ? 'IOError' : nil)
      expect(row.fetch('persisted_email')).to eq(row.fetch('error') ? row.fetch('old_email') : row.fetch('new_email'))
    end
    otp = fixture.fetch('cases').drop(11)
    expect(otp.pluck('failed_attempts')).to eq([9, 10, 10, 10, 10, 10])
    expect(otp.pluck('locked')).to eq([false, true, true, true, true, true])
    expect(otp.pluck('throttle')).to eq([false, true, true, true, true, true])
    expect(otp.map { |row| row.fetch('notifications').length }).to eq([0, 1, 0, 0, 1, 0])
    otp.flat_map { |row| row.fetch('notifications') }.each do |mail|
      expect(mail.slice('mailer', 'action', 'delivery', 'locale', 'owner', 'params_user')).to eq(
        'mailer' => 'UsersMailer', 'action' => 'otp_account_locked', 'delivery' => 'deliver_now',
        'locale' => 'fr', 'owner' => 'rails', 'params_user' => true
      )
    end
  end

  def digest_attributes(period)
    { id: 460_020, year: 2024, month: period == 'monthly' ? 2 : nil, period_type: period,
      distance: 12_500, flight_distance: 1500, monthly_distances: { '1' => 500, '2' => 1500, '29' => 2500 },
      time_spent_by_location: {
        'countries' => [{ 'name' => 'Sixty', 'minutes' => 60 }, { 'name' => 'SixtyOne', 'minutes' => 61 },
                        { 'name' => '日本<&>', 'minutes' => 120 }, { 'name' => 'Åland', 'minutes' => 120 }],
        'cities' => [{ 'name' => '東京<&>', 'minutes' => 61 }, { 'name' => 'Berlin', 'minutes' => 120 }]
      }, first_time_visits: { 'countries' => ['日本<&>', 'Åland', 'Third'], 'cities' => ['東京<&>', 'Berlin'] },
      year_over_year: { 'distance_change_percent' => -100 },
      all_time_stats: { 'total_countries' => 3, 'total_cities' => 4 },
      sharing_uuid: nil, sharing_settings: { 'enabled' => false } }
  end

  def digest_case_options
    basic = %w[km mi default de ambient_fr].flat_map do |suffix|
      %w[monthly yearly].map do |period|
        settings = { 'maps' => { 'distance_unit' => suffix == 'mi' ? 'mi' : 'km' }, 'locale' => 'en' }
        settings.delete('maps') if suffix == 'default'
        settings['locale'] = suffix == 'de' ? ' DE ' : 'invalid' if %w[de ambient_fr].include?(suffix)
        ["#{period}_#{suffix}", period, {}, settings, suffix == 'ambient_fr' ? :fr : :en]
      end
    end
    nil_json = { monthly_distances: nil, time_spent_by_location: nil, first_time_visits: nil,
                 year_over_year: nil, all_time_stats: nil }
    empty = { distance: 0, flight_distance: 0, monthly_distances: {}, time_spent_by_location: {},
              first_time_visits: {}, year_over_year: {}, all_time_stats: {} }
    monthly = {
      'empty' => empty, 'equal' => { monthly_distances: { '1' => 1500, '2' => 1500 } },
      'leap_invalid_days' => { monthly_distances: { '1' => 500, '29' => 1500, '30' => 9000, '99' => 8000 } },
      'threshold' => {}, 'nil_json' => nil_json,
      'negative' => { distance: -1500, flight_distance: -500, monthly_distances: { '1' => -500, '2' => 1500 } },
      'malformed_distances' => { monthly_distances: 'bad-shape' },
      'malformed_locations' => { time_spent_by_location: { 'countries' => [1] } },
      'malformed_visits' => { first_time_visits: { 'countries' => 'bad-shape' } },
      'invalid_month' => { month: 13 }
    }
    yearly = {
      'empty' => empty, 'shared' => { sharing_uuid: '46000000-0000-4000-8000-000000000001',
                                    sharing_settings: { 'enabled' => true } },
      'sharing_disabled' => { sharing_uuid: '46000000-0000-4000-8000-000000000001' },
      'sparse_stats' => {}, 'nil_json' => nil_json,
      'negative' => { distance: -1500, monthly_distances: { '1' => -500, '2' => 1500 } },
      'malformed_stats' => {}
    }
    basic + [monthly, yearly].zip(%w[monthly yearly]).flat_map do |entries, period|
      entries.map { |suffix, attrs| ["#{period}_#{suffix}", period, attrs, { 'locale' => 'en' }, :en] }
    end
  end

  def digest_stats(user, foreign, name)
    user.stats.delete_all
    return [] if name.end_with?('_empty', '_nil_json') || name.start_with?('monthly')

    values = name.end_with?('_malformed_stats') ? 'bad-shape' : { '1' => 500, '2' => 1500, '32' => 9000 }
    rows = [
      [460_030, user, 2024, 1, values],
      [460_031, user, 2024, 2, { '29' => 2500, '30' => 9999 }],
      [460_032, user, 2024, 12, { '31' => 5000 }],
      [460_033, user, 2023, 1, { '1' => 990_000 }],
      [460_034, foreign, 2024, 1, { '1' => 880_000 }],
      [460_035, user, 2024, 3, nil]
    ]
    rows.map do |id, owner, year, month, daily|
      stat = Stat.find_or_initialize_by(id:)
      stat.assign_attributes(user: owner, year:, month:, distance: 0, daily_distance: daily,
                             toponyms: [], sharing_uuid: format('46000000-0000-4000-8000-%012d', id))
      stat.save!
      stat.attributes.slice('id', 'user_id', 'year', 'month', 'daily_distance')
    end
  end

  def capture_digest_case(user, foreign, name, period, attrs, settings, ambient)
    user.update_columns(settings:)
    stats = digest_stats(user, foreign, name)
    digest = Users::Digest.new(digest_attributes(period).merge(attrs).merge(user:))
    input = { 'id' => name, 'period' => period, 'email' => user.email, 'user_id' => user.id,
              'settings' => settings, 'ambient_locale' => ambient.to_s,
              'locale' => (user.preferred_locale || ambient).to_s, 'stats' => stats,
              'digest' => digest.attributes.except('created_at', 'updated_at', 'sent_at', 'toponyms',
                                                   'travel_patterns'),
              'base_url' => 'http://www.example.com' }
    I18n.with_locale(ambient) do
      action = period == 'monthly' ? :monthly_digest : :year_end_digest
      delivery = Users::DigestsMailer.with(user:, digest:).public_send(action)
      message = delivery.message
      mailer = delivery.send(:processed_mailer)
      projection = %w[distance_unit daily_distances weekday_totals active_days top_countries top_cities
                      first_countries first_cities daily_values monthly_distances].to_h do |key|
        value = mailer.instance_variable_get("@#{key}")
        value = value.transform_keys(&:iso8601) if key == 'daily_values' && value
        [key, value]
      end
      input.merge('projection' => projection, 'error' => nil).merge(message_content(message))
    rescue StandardError => e
      input.merge('error' => { 'class' => e.class.name, 'cause' => e.cause&.class&.name })
    end
  end

  def digest_helper_case(name, method, args, kwargs = {})
    helper = Object.new.extend(Users::DigestsMailerHelper)
    input = { 'id' => name, 'method' => method.to_s, 'args' => args, 'kwargs' => kwargs }
    input.merge('output' => helper.public_send(method, *args, **kwargs), 'error' => nil)
  rescue StandardError => e
    input.merge('error' => e.class.name)
  end

  def digest_chart_cases
    items = [{ 'name' => '日本', 'minutes' => 61 }, { 'name' => 'Åland', 'minutes' => 61 },
             { 'name' => '東京<&>', 'minutes' => 120.5 }]
    [
      digest_helper_case('hbar_empty', :ascii_hbar, [[]], { labels: [] }),
      digest_helper_case('hbar_zero', :ascii_hbar, [[0, 0]], { labels: %w[A 東京], width: 4, suffix: ' km' }),
      digest_helper_case('hbar_half', :ascii_hbar, [[0.5, 1]], { labels: %w[日本 Åland], width: 3 }),
      digest_helper_case('hbar_negative', :ascii_hbar, [[-0.5, 1]], { labels: %w[A B], width: 3 }),
      digest_helper_case('hbar_all_negative', :ascii_hbar, [[-0.5, -1]], { labels: %w[A B], width: 3 }),
      digest_helper_case('spark_empty', :ascii_sparkline, [[]]),
      digest_helper_case('spark_equal', :ascii_sparkline, [[0.5, 0.5, 0.5]]),
      digest_helper_case('spark_negative_half', :ascii_sparkline, [[-1, -0.5, 0, 0.5, 1]]),
      digest_helper_case('heatmap_empty', :ascii_year_heatmap, [{}], { start_date: Date.new(2024, 1, 1) }),
      digest_helper_case('heatmap_quartiles', :ascii_year_heatmap,
                         [{ Date.new(2024, 1, 1) => 1, Date.new(2024, 1, 2) => 2,
                            Date.new(2024, 1, 3) => 3, Date.new(2024, 1, 4) => 4 }],
                         { start_date: Date.new(2024, 1, 1) }),
      digest_helper_case('heatmap_sparse_negative', :ascii_year_heatmap,
                         [{ Date.new(2024, 1, 1) => -1, Date.new(2024, 1, 14) => 4 }],
                         { start_date: Date.new(2024, 1, 3) }),
      digest_helper_case('ranked_empty', :ascii_ranked_list, [[]], { value_key: 'minutes', label_key: 'name' }),
      digest_helper_case('ranked_unicode_ties', :ascii_ranked_list, [items],
                         { value_key: 'minutes', label_key: 'name', width: 4 }),
      digest_helper_case('ranked_negative', :ascii_ranked_list, [[{ 'name' => 'A', 'minutes' => -1 },
                                                                  { 'name' => 'B', 'minutes' => 1 }]],
                         { value_key: 'minutes', label_key: 'name', width: 4 }),
      digest_helper_case('trend_equal', :ascii_trend, [0, 0]),
      digest_helper_case('trend_prior_zero', :ascii_trend, [1, 0]),
      digest_helper_case('trend_negative_half', :ascii_trend, [199, 200]),
      digest_helper_case('trend_positive_half', :ascii_trend, [201, 200]),
      digest_helper_case('trend_pct_nil', :ascii_trend_from_pct, [10, nil]),
      digest_helper_case('trend_pct_minus100_zero', :ascii_trend_from_pct, [0, -100]),
      digest_helper_case('trend_pct_minus100_positive', :ascii_trend_from_pct, [1, -100])
    ]
  end

  def residual_digest_content
    user = fresh_intent_user('digest')
    foreign = fresh_intent_user('foreign-digest')
    user.update_column(:id, 460_010)
    foreign.update_column(:id, 460_011)
    deliveries = ActionMailer::Base.deliveries.length
    queued = enqueued_jobs.length
    with_mail_defaults do
      options = digest_case_options.sort_by { |name, *| [name.start_with?('monthly') ? 0 : 1, digest_case_order(name)] }
      cases = options.map { |args| capture_digest_case(user, foreign, *args) }
      helpers = I18n.with_locale(:en) { digest_chart_cases }
      expect(ActionMailer::Base.deliveries.length).to eq(deliveries)
      expect(enqueued_jobs.length).to eq(queued)
      { 'cases' => cases, 'helpers' => helpers }
    end
  end

  def digest_case_order(name)
    %w[km mi default de ambient_fr empty equal leap_invalid_days threshold shared sharing_disabled sparse_stats
       nil_json negative malformed_distances malformed_locations malformed_visits invalid_month malformed_stats]
      .index(name.sub(/^(monthly|yearly)_/, ''))
  end

  def assert_digest_content(fixture)
    errors = %w[monthly_negative monthly_malformed_distances monthly_malformed_locations
                monthly_malformed_visits monthly_invalid_month yearly_negative yearly_malformed_stats]
    fixture.fetch('cases').each do |row|
      if errors.include?(row.fetch('id'))
        expect(row.fetch('error').present?).to be(true), "source error missing: #{row.fetch('id')}"
        next
      end
      expect(row.fetch('error')).to be_nil
      expect(row.fetch('from')).to eq(['residual@dawarich.test'])
      expect(row.fetch('to')).to eq([row.fetch('email')])
      expect(row.fetch('reply_to')).to be_nil
      expect(row.fetch('tree') == row.fetch('wire_tree')).to be(true), "wire parts differ: #{row.fetch('id')}"
      expect(row.fetch('tree').fetch('parts').pluck('type')).to eq(%w[text/plain text/html])
      period = row.fetch('period')
      locale = row.fetch('locale')
      subject_key = period == 'monthly' ? 'monthly' : 'year_end'
      month_name = I18n.l(Date.new(2024, 2), format: :month_name, locale:)
      expect(row.fetch('subject')).to eq(I18n.t("mailers.users.digests.#{subject_key}.subject",
                                                year: 2024, month: month_name, locale:))
      text = row.fetch('tree').fetch('parts').first.fetch('body')
      footer = 'http://www.example.com/settings/general'
      if period == 'monthly'
        footer += '?utm_campaign=monthly_digest&utm_content=manage_preferences&utm_medium=email&utm_source=email'
      end
      expect(text.include?("#{footer}#email-digests")).to be(true), "footer URL differs: #{row.fetch('id')}"
      uuid = row.fetch('digest').fetch('sharing_uuid')
      expect(text.include?("http://www.example.com/shared/digest/#{uuid}")).to be(true) if uuid
      projection = row.fetch('projection')
      expect(projection.fetch('distance_unit')).to eq(row.fetch('id').end_with?('_mi') ? 'mi' : 'km')
      next if row.fetch('id').end_with?('_empty', '_nil_json')

      expect(projection.fetch('top_countries').pluck('name')).to eq(['SixtyOne', '日本<&>', 'Åland'])
      if row.fetch('period') == 'yearly'
        expect(projection.fetch('daily_values').keys).to eq(%w[2024-01-01 2024-01-02 2024-02-29 2024-12-31])
      end
    end
    threshold = fixture.fetch('cases').find { |row| row.fetch('id') == 'monthly_threshold' }
    expect(threshold.fetch('projection').fetch('top_countries').pluck('minutes')).to eq([61, 120, 120])
    leap = fixture.fetch('cases').find { |row| row.fetch('id') == 'monthly_leap_invalid_days' }
    expect(leap.fetch('projection').fetch('weekday_totals')).to eq([0, 0, 0, 2, 0, 0, 0])
    fixture.fetch('helpers').each do |row|
      expected_error = %w[hbar_negative ranked_negative].include?(row.fetch('id')) ? 'ArgumentError' : nil
      expect(row.fetch('error')).to eq(expected_error)
    end
    quartiles = fixture.fetch('helpers').find { |row| row.fetch('id') == 'heatmap_quartiles' }
    expect(quartiles.fetch('output')).to eq("░\n▒\n▓\n█\n \n \n ")
  end

  def fixture_bytes(path, fixture)
    bytes = "#{JSON.pretty_generate(fixture)}\n"
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(path.dirname)
      File.write(path, bytes)
    else
      expect(path.binread == bytes.b).to be(true), "fixture bytes differ: #{path.basename}"
    end
  end

  def residual_path(name)
    Rails.root.join("app-phoenix/test/fixtures/mail/residual/#{name}.json")
  end
end
