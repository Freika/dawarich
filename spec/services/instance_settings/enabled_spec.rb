# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstanceSettings, '.enabled?' do
  # The resolver reroutes geocoding provider selection away from the boot-time
  # Geocoder global. If that goes wrong on a self-hosted instance the operator
  # needs a switch, not an image rollback.
  it 'is off by default so a fresh install keeps the constant-driven behaviour' do
    expect(FeatureFlags::DEFAULTS[:instance_settings_resolver]).to be(false)
  end

  it 'reports disabled when the flag is off' do
    allow(Flipper).to receive(:enabled?).with(:instance_settings_resolver).and_return(false)

    expect(described_class.enabled?).to be(false)
  end

  it 'reports enabled when the flag is on' do
    allow(Flipper).to receive(:enabled?).with(:instance_settings_resolver).and_return(true)

    expect(described_class.enabled?).to be(true)
  end

  it 'degrades to disabled rather than raising when Flipper cannot answer' do
    allow(Flipper).to receive(:enabled?).and_raise(StandardError, 'flipper down')

    expect { described_class.enabled? }.not_to raise_error
    expect(described_class.enabled?).to be(false)
  end
end
