# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Atlas::Configuration do
  describe 'defaults' do
    subject(:configuration) { described_class.new }

    it 'defaults the url to the local Atlas instance' do
      expect(configuration.url).to eq('http://localhost:8080')
    end

    it 'reads the api key from ATLAS_API_KEY' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('ATLAS_API_KEY', nil).and_return('secret')

      expect(described_class.new.api_key).to eq('secret')
    end

    it 'defaults the timeout to 5 seconds' do
      expect(configuration.timeout).to eq(5)
    end

    it 'falls back to the default timeout when ATLAS_API_TIMEOUT is zero or negative' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('ATLAS_API_TIMEOUT', described_class::DEFAULT_TIMEOUT).and_return('0')

      expect(described_class.new.timeout).to eq(described_class::DEFAULT_TIMEOUT)
    end
  end

  describe 'enabled tools' do
    it 'enables every known tool by default' do
      expect(described_class.new.enabled_tools).to match_array(Atlas::Configuration::KNOWN_TOOLS)
    end

    it 'reports a default tool as enabled' do
      expect(described_class.new.tool_enabled?(:geocoding)).to be(true)
    end

    it 'reads ATLAS_ENABLED_TOOLS as a comma-separated allowlist' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('ATLAS_ENABLED_TOOLS', nil).and_return('geocoding')

      configuration = described_class.new

      expect(configuration.enabled_tools).to eq(%i[geocoding])
    end

    it 'ignores blank segments and surrounding whitespace in ATLAS_ENABLED_TOOLS' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('ATLAS_ENABLED_TOOLS', nil).and_return('geocoding, ,map_matching,')

      expect(described_class.new.enabled_tools).to eq(%i[geocoding map_matching])
    end

    it 'disables tools that are not in the allowlist' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('ATLAS_ENABLED_TOOLS', nil).and_return('geocoding')

      expect(described_class.new.tool_enabled?(:map_matching)).to be(false)
    end

    it 'normalizes a string allowlist assigned at runtime into symbols' do
      configuration = described_class.new
      configuration.enabled_tools = %w[map_matching]

      expect(configuration.tool_enabled?(:map_matching)).to be(true)
    end

    it 'raises on an unknown tool name to catch typos' do
      expect { described_class.new.enabled_tools = [:teleport] }
        .to raise_error(ArgumentError, /unknown atlas tool/i)
    end
  end

  describe '.configure' do
    around do |example|
      original = Atlas.instance_variable_get(:@configuration)
      example.run
      Atlas.instance_variable_set(:@configuration, original)
    end

    it 'yields the singleton configuration for url overrides' do
      Atlas.configure { |config| config.url = 'https://atlas.example.com' }

      expect(Atlas.configuration.url).to eq('https://atlas.example.com')
    end

    it 'yields the singleton configuration for api key overrides' do
      Atlas.configure { |config| config.api_key = 'override' }

      expect(Atlas.configuration.api_key).to eq('override')
    end

    it 'yields the singleton configuration for tool allowlist overrides' do
      Atlas.configure { |config| config.enabled_tools = %i[geocoding] }

      expect(Atlas.configuration.tool_enabled?(:map_matching)).to be(false)
    end
  end
end
