# frozen_string_literal: true

require 'rails_helper'
require 'open3'

RSpec.describe 'Selected tracks cross the antimeridian by the short path', type: :request do
  let(:user) { create(:user) }

  # Use the real track-detail response and browser modules. Only MapLibre's
  # source storage and animation scheduler are doubles; no geometry is mocked.
  def selection_geometry(body)
    script = <<~'JS'
      import { readFileSync } from 'node:fs';
      import { TracksLayer } from 'maps_maplibre/layers/tracks_layer';
      globalThis.requestAnimationFrame = () => 1;
      globalThis.cancelAnimationFrame = () => {};
      const sources = new Map();
      const map = {
        getSource: id => sources.get(id),
        addSource(id, config) {
          sources.set(id, { ...config, setData(data) { this.data = data; } });
        },
        getLayer() {}, addLayer() {}, setLayoutProperty() {},
        getStyle: () => ({ layers: [] }),
      };
      const feature = JSON.parse(readFileSync(0, 'utf8')).features[0];
      const originalGeometry = JSON.stringify(feature.geometry);
      const layer = new TracksLayer(map);
      layer.add({ type: 'FeatureCollection', features: [] });
      layer.setSelectedTrack(feature);
      process.stdout.write(JSON.stringify({
        geometry: sources.get(layer.selectionSourceId).data.features[0].geometry,
        inputUnchanged: JSON.stringify(feature.geometry) === originalGeometry,
      }));
    JS
    stdout, stderr, status = Open3.capture3(
      'node', '--no-warnings', '--experimental-loader=./spec/javascript/support/importmap_loader.mjs',
      '--input-type=module', '-e', script, stdin_data: body, chdir: Rails.root.to_s
    )
    expect(status.success?).to be(true), "Selection module failed: #{stderr}"
    JSON.parse(stdout)
  end

  {
    'sparse eastbound' => [[176.125, -55.625], [-176.125, -55.625]],
    'sparse westbound' => [[-176.125, -55.625], [176.125, -55.625]],
    'dense eastbound' => [[179.875, -55.625], [-179.875, -55.625]],
    'dense westbound' => [[-179.875, -55.625], [179.875, -55.625]]
  }.each do |description, coordinates|
    it "keeps the #{description} track highlight continuous across 180 degrees" do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      # Made-up positions in the open South Pacific, away from settlements.
      path = "LINESTRING(#{coordinates.map { |point| point.join(' ') }.join(', ')})"
      track = create(:track, user:, original_path: path,
                             start_at: Time.utc(2026, 10, 10, 12),
                             end_at: Time.utc(2026, 10, 10, 13))

      get api_v1_track_path(track), headers: { 'Authorization' => "Bearer #{user.api_key}" }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig('features', 0, 'geometry', 'coordinates')).to eq(coordinates)

      selected = selection_geometry(response.body)
      geometry = selected.fetch('geometry')
      drawn = geometry.fetch('coordinates')
      lines = geometry.fetch('type') == 'MultiLineString' ? drawn : [drawn]
      jumps = lines.flat_map { |line| line.each_cons(2).map { |a, b| (b[0] - a[0]).abs } }

      expect(jumps).not_to be_empty
      expect(jumps.max).to be <= 180,
                           "Selected #{description} track has a #{jumps.max} degree longitude jump in MapLibre's source"
      expect(selected.fetch('inputUnchanged')).to be(true)
    end
  end
end
