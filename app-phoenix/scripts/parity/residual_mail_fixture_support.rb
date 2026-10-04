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
