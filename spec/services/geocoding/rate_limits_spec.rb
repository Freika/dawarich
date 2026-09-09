# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geocoding::RateLimits do
  describe '.for' do
    it 'locks komoot to one request per second' do
      rule = described_class.for('photon', 'photon.komoot.io')

      expect(rule.locked).to be(true)
      expect(rule.default).to eq(1.0)
      expect(rule.max).to eq(1.0)
    end

    it 'recognises komoot behind a port suffix' do
      expect(described_class.for('photon', 'photon.komoot.io:443').locked).to be(true)
    end

    it 'gives chibigeo an editable range between the free and the top public plan' do
      rule = described_class.for('photon', 'app.chibigeo.com/v1/photon')

      expect(rule.locked).to be(false)
      expect(rule.default).to eq(1.0)
      expect(rule.min).to eq(1.0)
      expect(rule.max).to eq(25.0)
    end

    it 'leaves unknown hosts unlimited by default' do
      rule = described_class.for('photon', 'photon.example.com')

      expect(rule.locked).to be(false)
      expect(rule.default).to be_nil
    end

    it 'treats non-photon providers as unknown hosts' do
      expect(described_class.for('geoapify', nil).default).to be_nil
      expect(described_class.for('nominatim', 'nominatim.example.com').default).to be_nil
    end
  end

  describe '#normalize' do
    it 'ignores a submitted value for a locked host' do
      expect(described_class.for('photon', 'photon.komoot.io').normalize('50')).to eq(1.0)
    end

    it 'raises a chibigeo value below the floor to the floor' do
      expect(described_class.for('photon', 'app.chibigeo.com/v1/photon').normalize('0.2')).to eq(1.0)
    end

    it 'lowers a chibigeo value above the ceiling to the ceiling' do
      expect(described_class.for('photon', 'app.chibigeo.com/v1/photon').normalize('100')).to eq(25.0)
    end

    it 'keeps a chibigeo value inside the range' do
      expect(described_class.for('photon', 'app.chibigeo.com/v1/photon').normalize('5')).to eq(5.0)
    end

    it 'falls back to the default when the value is blank' do
      expect(described_class.for('photon', 'app.chibigeo.com/v1/photon').normalize('')).to eq(1.0)
      expect(described_class.for('photon', 'photon.example.com').normalize('')).to be_nil
    end

    it 'reads zero and negatives as unlimited on an unbounded host' do
      rule = described_class.for('photon', 'photon.example.com')

      expect(rule.normalize('0')).to be_nil
      expect(rule.normalize('-3')).to be_nil
    end

    it 'reads zero as the floor on a host with a minimum' do
      expect(described_class.for('photon', 'app.chibigeo.com/v1/photon').normalize('0')).to eq(1.0)
    end

    it 'clamps an absurd custom value into the sanity range' do
      rule = described_class.for('photon', 'photon.example.com')

      expect(rule.normalize('99999')).to eq(described_class::CUSTOM_MAX)
      expect(rule.normalize('0.001')).to eq(described_class::CUSTOM_MIN)
    end

    it 'ignores junk input' do
      expect(described_class.for('photon', 'photon.example.com').normalize('fast')).to be_nil
    end

    it 'accepts a numeric value as well as a string' do
      expect(described_class.for('photon', 'app.chibigeo.com/v1/photon').normalize(5)).to eq(5.0)
    end
  end
end
