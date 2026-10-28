# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geocoding::ProviderTest do
  let(:config) { instance_double(Geocoding::Config, enabled?: true) }
  let(:result) { double(city: 'Test City', country: 'Test Country') }

  before { allow(Geocoding::Search).to receive(:with_config).and_return([result]) }

  it 'preserves the existing call without arguments' do
    allow(Geocoding::Config).to receive(:resolved_config).and_return(config)

    expect(described_class.call.first).to eq(:notice)
    expect(Geocoding::Search).to have_received(:with_config).with(
      config: config, query: [51.3402, 12.3712], limit: 1, max_wait: 5.0
    )
  end

  [[nil, nil], ['', ''], ['  ', "\t"]].each do |latitude, longitude|
    it "uses the default coordinates for blank input #{[latitude, longitude].inspect}" do
      described_class.call(config, latitude: latitude, longitude: longitude)

      expect(Geocoding::Search).to have_received(:with_config).with(
        config: config, query: described_class::TEST_COORDINATES, limit: 1, max_wait: 5.0
      )
    end
  end

  [
    ['40.7128', '-74.0060', [40.7128, -74.006]],
    [' -33.8688 ', '151.2093', [-33.8688, 151.2093]],
    [0, 0, [0.0, 0.0]],
    ['90', '180', [90.0, 180.0]],
    ['-90', '-180', [-90.0, -180.0]],
    ['+4e1', '-7.4e1', [40.0, -74.0]]
  ].each do |latitude, longitude, expected|
    it "looks up the supplied coordinates #{[latitude, longitude].inspect}" do
      expect(described_class.call(config, latitude: latitude, longitude: longitude).first).to eq(:notice)
      expect(Geocoding::Search).to have_received(:with_config).with(
        config: config, query: expected, limit: 1, max_wait: 5.0
      )
    end
  end

  [
    [nil, '12'], ['51', ''], ['', '12'], ['51', nil],
    ['90.0001', '0'], ['-90.0001', '0'], ['0', '180.0001'], ['0', '-180.0001'],
    ['not a number', '12'], ['51', '12abc'], ['51,3', '12'], ['0x10', '12'], ['1_0', '12'],
    ['NaN', '12'], ['51', 'Infinity'], ['1e999', '12'], [Float::NAN, '12'],
    [[], []], [{}, '12'], [false, '12']
  ].each do |latitude, longitude|
    it "rejects invalid input #{[latitude, longitude].inspect} without a lookup" do
      expect(described_class.call(config, latitude: latitude, longitude: longitude)).to eq(
        [:alert, I18n.t('admin.settings.test_geocoding.invalid_coordinates')]
      )
      expect(Geocoding::Search).not_to have_received(:with_config)
    end
  end

  it 'reports an empty result for the supplied coordinates' do
    allow(Geocoding::Search).to receive(:with_config).and_return([])

    expect(described_class.call(config, latitude: '0', longitude: '0')).to eq(
      [:alert, I18n.t('admin.settings.test_geocoding.empty')]
    )
  end
end
