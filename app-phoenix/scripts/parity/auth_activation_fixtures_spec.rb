# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixture: the registration flag and Devise recovery mail as Rails writes them' do
  let(:path) { Rails.root.join('app-phoenix/test/fixtures/auth/activation.json') }
  let(:sender) { 'Dawarich <a11a@dawarich.test>' }
  let(:flag) { 'dawarich/registration_enabled' }
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
    encoded = message.encoded
    encoded.end_with?("\r\n") ? encoded : "#{encoded}\r\n"
  end

  def flag_bytes(value)
    DawarichSettings.set_registration_enabled(value)
    Rails.cache.redis.with { |redis| redis.get(flag) }
  ensure
    Rails.cache.delete(flag)
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

  it 'writes app-phoenix/test/fixtures/auth/activation.json' do
    allow(Devise).to receive(:mailer_sender).and_return(sender)
    kinds = %i[reset_password_instructions unlock_instructions].product(%w[en de fr])

    fixture = {
      'rails_version' => Rails.version,
      'reset_password_within_seconds' => Devise.reset_password_within.to_i,
      'base_url' => 'http://www.example.com',
      'registration' => { 'true' => true, 'false' => false, 'nil' => nil }
        .transform_values { |value| Base64.strict_encode64(flag_bytes(value)) },
      'mails' => kinds.map { |kind, locale| devise_mail(kind, locale) },
      'controls' => controls.to_h { |name, html| [name, control(name, html)] }
    }
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
