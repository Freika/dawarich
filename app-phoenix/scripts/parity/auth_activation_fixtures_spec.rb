# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixture: the registration flag and Devise recovery mail as Rails writes them' do
  let(:path) { Rails.root.join('app-phoenix/test/fixtures/auth/activation.json') }
  let(:sender) { 'Dawarich <a11a@dawarich.test>' }
  let(:flag) { 'dawarich/registration_enabled' }
  let(:registration_values) { { 'true' => true, 'false' => false, 'nil' => nil } }

  around do |example|
    with_legacy_registration { example.run }
  end
  let(:controls) do
    {
      'ascii_none' => '<p>Hello</p>', 'ascii_one' => "<p>Hello</p>\n", 'ascii_two' => "<p>Hello</p>\n\n",
      'latin_none' => '<p>Grüße</p>', 'latin_one' => "<p>Grüße</p>\n", 'latin_two' => "<p>Grüße</p>\n\n",
      'qp_none' => '<p>Viele Grüße, wir sehen uns bald wieder im Sommer</p>',
      'qp_one' => "<p>Viele Grüße, wir sehen uns bald wieder im Sommer</p>\n",
      'tie' => '<p>abcü</p>',
      'dense_none' => "<p>#{'ü' * 40}</p>", 'dense_one' => "<p>#{'ü' * 40}</p>\n",
      'long_997' => "<p>#{'a' * 990}</p>\n", 'long_998' => "<p>#{'a' * 991}</p>\n",
      'long_tail' => "<p>#{'a' * 992}</p>",
      'dots' => "<p>a</p>\n.\n<p>b</p>\n"
    }
  end

  def wire(message)
    message.date = Time.utc(2026, 9, 26, 12)
    encoded = message.encoded
    encoded.end_with?("\r\n") ? encoded : "#{encoded}\r\n"
  end

  def flag_bytes(value)
    DawarichSettings.set_registration_enabled(value)
    Rails.cache.redis.with { |redis| redis.get(flag) }
  ensure
    Rails.cache.delete(flag)
  end

  def registration_coders
    serializer = ActiveSupport::Cache::SerializerWithFallback
    {
      'coder_7_1' => ActiveSupport::Cache::Coder.new(serializer['marshal_7_1'.to_sym], Zlib),
      'marshal_7_0_uncompressed' => serializer['marshal_7_0'.to_sym],
      'marshal_7_0_compressed' => serializer['marshal_7_0'.to_sym]
    }
  end

  def registration_bytes(format, value, version: nil, expires_at: nil)
    coder = registration_coders.fetch(format)
    entry = ActiveSupport::Cache::Entry.new(value, version: version, expires_at: expires_at)
    bytes = if format.end_with?('_compressed')
              coder.dump_compressed(entry, 1024)
            else
              coder.dump(entry)
            end
    decoded = coder.load(bytes)
    expect(decoded.value).to eq(value)
    expect(decoded.version).to eq(version)
    expect(decoded.expires_at).to eq(expires_at)
    if format == 'coder_7_1'
      expect(bytes.bytes.first(2)).to eq([0, 17])
    else
      large = value.is_a?(String) && value.bytesize > 1024 || version.to_s.bytesize > 1024
      expected = format.end_with?('_compressed') && large ? 1 : 0
      expect(bytes.getbyte(0)).to eq(expected)
    end
    Base64.strict_encode64(bytes)
  end

  def registration_legacy
    registration_coders.keys.grep(/^marshal/).index_with do |format|
      registration_values.transform_values { |value| registration_bytes(format, value) }
    end
  end

  def registration_controls
    registration_coders.keys.to_h do |format|
      values = registration_values.flat_map do |name, value|
        [["versioned_#{name}", registration_bytes(format, value, version: 'a13g-version')],
         ["expiring_#{name}", registration_bytes(format, value, expires_at: 1_800_000_000.0)]]
      end.to_h
      values['non_boolean'] = registration_bytes(format, 'x' * 4096)
      values['compressed_versioned_false'] = registration_bytes(format, false, version: 'v' * 4096)
      [format, values]
    end
  end

  def devise_mail(kind, locale)
    seed = kind == :reset_password_instructions ? 'a' * 20 : 'b' * 20
    user = create(:user, email: "a11a-#{kind.to_s.split('_').first}-#{locale}@dawarich.test")
    user.update_columns(settings: user.settings.merge('locale' => locale))
    message = DeviseMailer.public_send(kind, user.reload, seed).message
    message.message_id = "<a11a-#{kind}-#{locale}@dawarich.test>"
    raw = wire(message)
    expect(message.multipart?).to be(false)
    expect(message.mime_type).to eq('text/html')

    {
      'kind' => kind.to_s, 'locale' => locale, 'seed' => seed, 'to' => user.email,
      'from' => message[:from].value, 'reply_to' => message[:reply_to].value, 'subject' => message.subject,
      'html' => message.body.decoded.gsub("\r\n", "\n"), 'transfer' => message.content_transfer_encoding,
      'wire' => Base64.strict_encode64(raw)
    }
  end

  def control(name, html)
    message = Mail.new
    message.message_id = "<a11a-control-#{name}@dawarich.test>"
    message.from = sender
    message.to = 'control@dawarich.test'
    message.subject = 'Control'
    message.content_type = 'text/html; charset=UTF-8'
    message.body = html
    raw = wire(message)
    { 'html' => html, 'transfer' => message.content_transfer_encoding, 'wire' => Base64.strict_encode64(raw) }
  end

  def stable(fixture)
    fixture.merge(
      'mails' => fixture['mails'].map { |mail| mail.except('wire') },
      'controls' => fixture['controls'].transform_values { |entry| entry.except('wire') }
    )
  end

  def provider_result(provider, verified, email, uid, allow_registration: true)
    user, created = Auth::FindOrCreateOauthUser.new(
      provider: provider, provider_label: provider, claims: { sub: uid, email: email },
      email_verified: verified, on_email_collision: :raise_only,
      allow_registration: allow_registration
    ).call
    { 'outcome' => user ? 'account' : 'denied', 'created' => created,
      'provider' => user&.provider, 'uid' => user&.uid, 'email' => user&.email }
  rescue Auth::FindOrCreateOauthUser::LinkVerificationSent => e
    { 'outcome' => 'challenge', 'provider' => e.user.reload.provider, 'rate_limited' => e.rate_limited }
  rescue Auth::FindOrCreateOauthUser::UnverifiedEmail
    { 'outcome' => 'unverified_email' }
  rescue Auth::FindOrCreateOauthUser::AccountPendingDeletion
    { 'outcome' => 'pending_deletion' }
  end

  def record_provider_contracts
    cases = %w[github google_oauth2 openid_connect].to_h do |provider|
      email = "a12f2g-#{provider}@dawarich.test"
      local = create(:user, email: email)
      collision = [true, false, 'true', nil].to_h do |verified|
        auth = OmniAuth::AuthHash.new(
          provider: provider, uid: 'synthetic-subject', info: { email: email },
          extra: { raw_info: { email_verified: verified } }
        )
        value = begin
          user = User.from_omniauth(auth)
          { 'outcome' => user ? 'account' : 'denied' }
        rescue Auth::FindOrCreateOauthUser::LinkVerificationSent
          { 'outcome' => 'challenge' }
        rescue Auth::FindOrCreateOauthUser::UnverifiedEmail
          { 'outcome' => 'unverified_email' }
        end
        [verified.inspect, value]
      end
      local.update_columns(deleted_at: Time.current)
      deleted = provider_result(provider, true, email, 'deleted')
      fresh = provider_result(provider, true, "fresh-#{email}", 'fresh')
      returning = provider_result(provider, false, '', 'fresh', allow_registration: false)
      missing = provider_result(provider, false, '', 'missing')
      denied = provider_result(provider, true, "denied-#{email}", 'denied', allow_registration: false)
      [provider, { 'collision' => collision, 'deleted' => deleted, 'fresh' => fresh,
                   'returning' => returning, 'missing_email' => missing, 'registration_disabled' => denied }]
    end
    public_env = { 'OIDC_CLIENT_ID' => 'synthetic-client', 'OIDC_PKCE_ENABLED' => 'true',
                   'OIDC_ISSUER' => 'https://idp.dawarich.test/.well-known/openid-configuration#paste',
                   'APPLICATION_URL' => 'http://www.example.com' }
    oidc = OidcConfig.build(public_env)
    fixture = { 'accounts' => cases, 'oidc_public' => oidc,
                'failure_messages' => %w[invalid_credentials connection_timeout security_error
                                         provider_unavailable provider_configuration_error unknown_error].index_with do |key|
                  I18n.t("controllers.users.omniauth_callbacks.#{key}", locale: :en)
                end }
    output = Rails.root.join('app-phoenix/test/fixtures/auth/a12f2g/providers.json')
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(output.dirname)
      File.write(output, "#{JSON.pretty_generate(fixture)}\n")
    else
      expect(JSON.parse(output.read)).to eq(JSON.parse(fixture.to_json))
    end
  end

  it 'writes app-phoenix/test/fixtures/auth/activation.json' do
    allow(Devise).to receive(:mailer_sender).and_return(sender)
    kinds = %i[reset_password_instructions unlock_instructions].product(%w[en de es fr pl ca zh])

    fixture = {
      'rails_version' => Rails.version,
      'reset_password_within_seconds' => Devise.reset_password_within.to_i,
      'base_url' => 'http://www.example.com',
      'registration' => registration_values.transform_values { |value| Base64.strict_encode64(flag_bytes(value)) },
      'registration_legacy' => registration_legacy,
      'registration_controls' => registration_controls,
      'mails' => kinds.map { |kind, locale| devise_mail(kind, locale) },
      'controls' => controls.to_h { |name, html| [name, control(name, html)] }
    }
    record_provider_contracts
    fixture = JSON.parse(fixture.to_json)

    expect(fixture['registration'].values.uniq.size).to eq(3)
    expect(fixture['mails'].map { |mail| mail['transfer'] }).to include('7bit')
    expect(fixture['controls'].values_at('tie', 'long_tail').pluck('transfer')).to all(eq('quoted-printable'))

    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      File.write(path, "#{JSON.pretty_generate(fixture)}\n")
    else
      expect(stable(JSON.parse(path.read))).to eq(stable(fixture))
    end
  end
end
