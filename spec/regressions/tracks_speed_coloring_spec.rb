# frozen_string_literal: true

require 'rails_helper'
require 'open3'

RSpec.describe 'Tracks honor the saved speed coloring preference', type: :request do
  let(:user) do
    create(:user, settings: { 'speed_colored_routes' => true, 'enabled_map_layers' => ['Tracks'] })
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    sign_in user
  end

  # Execute the same settings -> layer-manager -> MVT-layer path as Map v2.
  # As in spec/javascript/tracks_mvt_layer_test.mjs, strip importmap imports
  # and load these real modules together; only the map and API transport are fake.
  def frontend_track_layer
    get '/api/v1/settings', params: { api_key: user.api_key }
    expect(response).to have_http_status(:ok)

    script = <<~'JS'
      import { readFileSync } from 'node:fs';
      import { createRequire } from 'node:module';
      const require = createRequire(process.cwd() + '/package.json');
      const { expression } = require('@maplibre/maplibre-gl-style-spec');
      const files = [
        'app/javascript/maps_maplibre/layers/base_layer.js',
        'app/javascript/maps_maplibre/utils/tile_freshness.js',
        'app/javascript/maps_maplibre/utils/settings_manager.js',
        'app/javascript/maps_maplibre/layers/tracks_mvt_layer.js',
        'app/javascript/controllers/maps/maplibre/layer_manager.js'
      ];
      const source = files.map(file => readFileSync(file, 'utf8')
        .replace(/^import[\s\S]*?from "[^"]+"\n/gm, '')).join('\n');
      const { SettingsManager, LayerManager } = await import(
        'data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
      const backend = JSON.parse(readFileSync(0, 'utf8'));
      globalThis.fetch = async () => ({ ok: true, json: async () => backend });
      SettingsManager.initialize('synthetic-key');
      await SettingsManager.loadFromBackend();
      let tileUrl, paint;
      const map = {
        getSource() {}, getLayer() {}, on() {}, setLayoutProperty() {},
        addSource(id, config) { tileUrl = config.tiles[0]; },
        addLayer(config) { paint = config.paint['line-color']; }
      };
      // Keep BaseLayer's diagnostic logs out of the JSON result.
      console.log = () => {};
      const manager = new LayerManager(map, SettingsManager.getSettings(), null,
        { apiKeyValue: 'synthetic-key' });
      manager._addTracksMvtLayer();
      const compiled = expression.createExpression(paint, 'layers[0].paint.line-color');
      if (compiled.result !== 'success') throw new Error(JSON.stringify(compiled.value));
      const colors = [4, 40, 80].map(speed => compiled.value.evaluate(
        { zoom: 15 }, { properties: { segment_speed: speed, avg_speed: 15 } }));
      process.stdout.write(JSON.stringify({ tileUrl, colors }));
    JS
    stdout, stderr, status = Open3.capture3('node', '--input-type=module', '-e', script,
                                            stdin_data: response.body, chdir: Rails.root.to_s)
    expect(status.success?).to be(true), stderr
    JSON.parse(stdout)
  end

  it 'requests per-segment speeds for the tile used by the frontend' do
    track = create(:track, user:, start_at: Time.utc(2026, 10, 10, 12),
                           end_at: Time.utc(2026, 10, 10, 12, 0, 20),
                           original_path: 'LINESTRING(0.001 0.001, 0.002 0.001, 0.0021 0.001)')
    [0.001, 0.002, 0.0021].each_with_index do |longitude, index|
      create(:point, user:, track:, longitude:, latitude: 0.001,
                     timestamp: track.start_at.to_i + index * 10)
    end
    tile_url = frontend_track_layer.fetch('tileUrl')
                                   .sub('{z}', '15').sub('{x}', '16384').sub('{y}', '16383')
    get tile_url, headers: { 'Authorization' => "Bearer #{user.api_key}" }

    expect(response).to have_http_status(:ok)
    failure_message = "Frontend tile #{tile_url} has no segment speeds"
    expect(response.body.b.include?('segment_speed')).to be(true), failure_message
  end

  it 'renders slow and fast segments in different colors' do
    colors = frontend_track_layer.fetch('colors')

    expect(colors.uniq.size).to be > 1,
                                "Speed coloring is enabled, but 4, 40 and 80 km/h all render as #{colors.first}"
  end

  it 'provides a speed coloring toggle and a color scale editor on Map v2' do
    get map_v2_path
    expect(response).to have_http_status(:ok)
    panel = Nokogiri::HTML(response.body).at_css('#map-settings-panel')

    aggregate_failures do
      expect(panel.css('input[type="checkbox"][name*="speed_colored_routes"]').size).to be > 0
      expect(panel.css('[data-controller~="speed-color-editor"]').size).to be > 0
    end
  end
end
