# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SslConfigurable do
  let(:test_class) do
    Class.new do
      include SslConfigurable
    end
  end
  let(:instance) { test_class.new }
  let(:user) { create(:user) }

  describe '#ssl_verification_enabled?' do
    it 'returns true when skip_ssl_verification is false' do
      user.settings['immich_skip_ssl_verification'] = false
      expect(instance.send(:ssl_verification_enabled?, user, :immich)).to be true
    end

    it 'returns false when skip_ssl_verification is true' do
      user.settings['immich_skip_ssl_verification'] = true
      expect(instance.send(:ssl_verification_enabled?, user, :immich)).to be false
    end

    it 'works with photoprism service type' do
      user.settings['photoprism_skip_ssl_verification'] = true
      expect(instance.send(:ssl_verification_enabled?, user, :photoprism)).to be false
    end
  end

  describe '#http_options_with_ssl' do
    it 'merges verify option with base options when verification is disabled' do
      user.settings['immich_skip_ssl_verification'] = true
      result = instance.send(:http_options_with_ssl, user, :immich, { timeout: 10 })
      expect(result).to eq({ timeout: 10, verify: false })
    end

    it 'merges verify option with base options when verification is enabled' do
      user.settings['immich_skip_ssl_verification'] = false
      result = instance.send(:http_options_with_ssl, user, :immich, { timeout: 10 })
      expect(result).to eq({ timeout: 10, verify: true })
    end
  end
end
