# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CheckAppVersion do
  include ActiveSupport::Testing::TimeHelpers

  let(:version_url) { 'https://api.github.com/repos/Freika/dawarich/tags' }

  before do
    stub_const('APP_VERSION', '1.0.0')
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  describe '#call' do
    subject(:check_app_version) { described_class.new.call }

    it 'returns false before the first background refresh' do
      expect(check_app_version).to be false
    end

    context 'with a cached release' do
      before { Rails.cache.write(described_class::VERSION_CACHE_KEY, '1.0.0') }

      it { is_expected.to be false }

      context 'when latest version is newer' do
        before { stub_const('APP_VERSION', '0.9.0') }

        it { is_expected.to be true }
      end

      context 'when latest version is older' do
        before { stub_const('APP_VERSION', '1.1.0') }

        it { is_expected.to be false }
      end

      context 'when in production' do
        before do
          stub_const('APP_VERSION', '0.9.0')
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        end

        it { is_expected.to be false }
      end
    end
  end

  describe '#refresh' do
    subject(:refresh) { described_class.new.refresh }

    it 'caches the first stable release, replacing the previous value' do
      Rails.cache.write(described_class::VERSION_CACHE_KEY, '0.9.0')
      stub_request(:get, version_url).to_return(body: '[{"name":"1.2.0-rc.1"},{"name":"1.1.0"}]')

      refresh

      expect(Rails.cache.read(described_class::VERSION_CACHE_KEY)).to eq('1.1.0')
      expect(described_class.new.call).to be true
    end

    it 'uses the current version when there are no stable releases' do
      stub_request(:get, version_url).to_return(body: '[{"name":"1.2.0-rc.1"}]')

      refresh

      expect(described_class.new.call).to be false
      expect(Rails.cache.read(described_class::VERSION_CACHE_KEY)).to eq('1.0.0')
    end

    it 'expires the cached release after six hours' do
      refresh

      travel 6.hours + 1.second do
        expect(Rails.cache.read(described_class::VERSION_CACHE_KEY)).to be_nil
      end
    end

    it 'preserves the cached version when GitHub times out' do
      Rails.cache.write(described_class::VERSION_CACHE_KEY, '1.1.0')
      stub_request(:get, version_url).to_timeout

      expect(refresh).to be false
      expect(Rails.cache.read(described_class::VERSION_CACHE_KEY)).to eq('1.1.0')
    end

    it 'ignores HTTP failures even when the body resembles a release list' do
      stub_request(:get, version_url).to_return(status: 503, body: '[{"name":"1.1.0"}]')

      expect(refresh).to be false
      expect(Rails.cache.read(described_class::VERSION_CACHE_KEY)).to be_nil
    end

    it 'preserves the cached version when GitHub returns malformed data' do
      Rails.cache.write(described_class::VERSION_CACHE_KEY, '1.1.0')
      stub_request(:get, version_url).to_return(body: 'not JSON')

      expect(refresh).to be false
      expect(Rails.cache.read(described_class::VERSION_CACHE_KEY)).to eq('1.1.0')
    end

    it 'does not contact GitHub in production' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

      expect(refresh).to be false
      expect(a_request(:get, version_url)).not_to have_been_made
    end
  end
end
