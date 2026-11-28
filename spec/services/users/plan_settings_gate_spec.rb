# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::PlanSettingsGate do
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/user_settings_lite.json').read) }

  it 'shows a Lite account its Pro-only settings as defaults and keeps integrations readable' do
    config = Users::SafeSettings.new(fixture['stored'], plan: :lite).api_config.as_json
    defaults = Users::SafeSettings.new({}).api_config.as_json

    expect(config).to include(fixture['lite_reads'])
    fixture['lite_reads_default'].each do |key|
      expect(config[key]).to eq(defaults[key]), "#{key} should read as its default"
    end
  end

  it 'shows a Pro account its stored settings' do
    config = Users::SafeSettings.new(fixture['stored'], plan: :pro).api_config.as_json

    expect(config['globe_projection']).to be true
    expect(config['enabled_map_layers']).to include('Heatmap', 'Hexagons', 'Fog of War')
    expect(config['track_color']).to eq('#123456')
  end

  it 'drops Pro-only changes from a Lite write and keeps the stored gated layers' do
    applied = described_class.writable(fixture['lite_write']['incoming'], fixture['stored'])

    expect(applied).to eq(fixture['lite_write']['applied'])
  end
end
