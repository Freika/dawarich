# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SmtpConfig do
  describe '.smtp_settings' do
    def settings_for(value)
      described_class.smtp_settings('SMTP_OPENSSL_VERIFY_MODE' => value)
    end

    it 'omits openssl_verify_mode when SMTP_OPENSSL_VERIFY_MODE is unset' do
      expect(described_class.smtp_settings({})).not_to have_key(:openssl_verify_mode)
    end

    it 'omits openssl_verify_mode when the value is blank' do
      expect(settings_for('   ')).not_to have_key(:openssl_verify_mode)
    end

    it 'passes through none' do
      expect { expect(settings_for('none')[:openssl_verify_mode]).to eq('none') }
        .to output(/SMTP_OPENSSL_VERIFY_MODE=none/).to_stderr
    end

    it 'passes through peer' do
      expect(settings_for('peer')[:openssl_verify_mode]).to eq('peer')
    end

    it 'normalizes case and whitespace' do
      expect { expect(settings_for('  NONE  ')[:openssl_verify_mode]).to eq('none') }
        .to output.to_stderr
    end

    it 'warns that certificate verification is disabled when set to none' do
      expect { settings_for('none') }
        .to output(/TLS certificate verification is disabled/).to_stderr
    end

    it 'does not warn when set to peer' do
      expect { settings_for('peer') }.not_to output.to_stderr
    end

    it 'raises on an unsupported value' do
      expect { settings_for('bogus') }
        .to raise_error(ArgumentError, /SMTP_OPENSSL_VERIFY_MODE/)
    end

    it 'leaves implicit TLS and STARTTLS resolution untouched' do
      settings = described_class.smtp_settings(
        'SMTP_PORT' => '465', 'SMTP_OPENSSL_VERIFY_MODE' => 'peer'
      )

      expect(settings).to include(ssl: true, enable_starttls: false, port: 465)
    end
  end
end
