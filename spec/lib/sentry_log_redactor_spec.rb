# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/sentry_log_redactor')

RSpec.describe SentryLogRedactor do
  let(:log_class) { Struct.new(:attributes, :body) }

  def build_log(attributes: {}, body: nil)
    log_class.new(attributes, body)
  end

  describe 'attribute redaction' do
    it 'replaces values for sensitive keys with [FILTERED]' do
      log = build_log(attributes: { 'password' => 'hunter2', 'name' => 'Eugene' })

      described_class.call(log)

      expect(log.attributes['password']).to eq('[FILTERED]')
      expect(log.attributes['name']).to eq('Eugene')
    end

    it 'matches sensitive keys regardless of case and surrounding text' do
      log = build_log(
        attributes: {
          'Authorization' => 'Bearer abc',
          'X-API-KEY' => 'k_live_...',
          'user_password_confirmation' => 'pw',
          'safe_value' => 'visible'
        }
      )

      described_class.call(log)

      expect(log.attributes['Authorization']).to eq('[FILTERED]')
      expect(log.attributes['X-API-KEY']).to eq('[FILTERED]')
      expect(log.attributes['user_password_confirmation']).to eq('[FILTERED]')
      expect(log.attributes['safe_value']).to eq('visible')
    end

    it 'replaces emails inside non-sensitive string attributes' do
      log = build_log(
        attributes: {
          'user' => 'Contact me at eugene@example.com today',
          'count' => 5
        }
      )

      described_class.call(log)

      expect(log.attributes['user']).to eq('Contact me at [EMAIL] today')
      expect(log.attributes['count']).to eq(5)
    end

    it 'leaves non-string attribute values untouched' do
      log = build_log(attributes: { 'count' => 5, 'flag' => true, 'list' => [1, 2] })

      described_class.call(log)

      expect(log.attributes['count']).to eq(5)
      expect(log.attributes['flag']).to be(true)
      expect(log.attributes['list']).to eq([1, 2])
    end
  end

  describe 'body redaction' do
    it 'replaces emails in the log body' do
      log = build_log(body: 'Login failed for eugene@example.com')

      described_class.call(log)

      expect(log.body).to eq('Login failed for [EMAIL]')
    end

    it 'replaces multiple emails in a single body' do
      log = build_log(body: 'a@b.io contacted c@d.com')

      described_class.call(log)

      expect(log.body).to eq('[EMAIL] contacted [EMAIL]')
    end

    it 'is a no-op when the body is nil or non-string' do
      log = build_log(body: nil)
      expect { described_class.call(log) }.not_to raise_error

      log_with_int = build_log(body: 123)
      expect { described_class.call(log_with_int) }.not_to raise_error
      expect(log_with_int.body).to eq(123)
    end
  end

  describe 'edge cases' do
    it 'handles non-Hash attributes without raising' do
      log = build_log(attributes: nil, body: 'plain')
      expect { described_class.call(log) }.not_to raise_error
      expect(log.body).to eq('plain')
    end

    it 'returns the log object' do
      log = build_log(attributes: {}, body: nil)

      expect(described_class.call(log)).to be(log)
    end
  end
end
