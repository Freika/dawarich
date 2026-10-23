# frozen_string_literal: true

require 'rails_helper'
require 'open3'

RSpec.describe 'Heatmap sampling frequency invariance' do
  let(:user) { create(:user) }

  # The same synthetic 1 km / 10 minute path in the South Pacific, recorded
  # every minute or ~0.6 seconds. No real location data is used.
  def tile_features(samples, started_at)
    rows = samples.times.map do |index|
      fraction = index.to_f / (samples - 1)
      attributes_for(:point, user_id: user.id,
                             lonlat: "POINT(#{-140.0 + (0.0104 * fraction)} -30)",
                             timestamp: started_at + (600 * fraction).round,
                             velocity: 1.67, accuracy: 1, raw_data: {})
    end
    Point.insert_all!(rows)
    scope = user.points.where(timestamp: started_at..(started_at + 600))
    zoom = 14
    tile_x = ((-140.0 + 180) / 360 * (2**zoom)).floor
    latitude_radians = -30 * Math::PI / 180
    tile_y = ((1 - (Math.log(Math.tan(latitude_radians) + (1 / Math.cos(latitude_radians))) / Math::PI)) /
              2 * (2**zoom)).floor

    Points::VectorTileQuery.new(scope: scope, z: zoom, x: tile_x, y: tile_y)
                           .feature_rows.map { |row| row.except('geom') }
  end

  def rendered_weights(feature_sets)
    # Load the real layer configuration and use MapLibre's own expression
    # evaluator, rather than duplicating the heatmap weight formula in Ruby.
    script = <<~'JS'
      const fs = require('node:fs');
      const {createExpression} = require('@maplibre/maplibre-gl-style-spec');
      (async () => {
        const paths = [
          'layers/base_layer.js', 'layers/heatmap_layer.js',
          'utils/marker_theme.js', 'utils/tile_freshness.js',
          'layers/points_mvt_layer.js'
        ];
        const source = paths.map(path => fs.readFileSync(
          `app/javascript/maps_maplibre/${path}`, 'utf8'
        ).replace(/^import[\s\S]*?from "[^"]+"\n/gm, '')).join('\n');
        const {PointsMvtLayer} = await import(
          `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`
        );
        const layer = new PointsMvtLayer({});
        const paint = layer.getLayerConfigs().find(config => config.type === 'heatmap').paint;
        const compiled = createExpression(paint['heatmap-weight'], 'heatmap-weight');
        if (compiled.result !== 'success') throw new Error(JSON.stringify(compiled.value));
        const featureSets = JSON.parse(fs.readFileSync(0, 'utf8'));
        console.log(JSON.stringify(featureSets.map(features => features.reduce(
          (sum, properties) => sum + compiled.value.evaluate({zoom: 14}, {type: 1, properties}), 0
        ))));
      })().catch(error => { console.error(error); process.exit(1); });
    JS
    stdout, stderr, status = Open3.capture3('node', '-e', script, stdin_data: feature_sets.to_json,
                                                              chdir: Rails.root.to_s)
    expect(status.success?).to be(true), stderr
    JSON.parse(stdout)
  end

  it 'gives equal heat to equal time on the same path regardless of recording frequency' do
    start = Time.utc(2024, 1, 1, 12).to_i
    # Separate dates isolate the two recordings while keeping their geometry,
    # speed and elapsed time identical; only the sampling frequency differs.
    sparse = tile_features(11, start)
    dense = tile_features(1001, start + 1.day.to_i)

    # Verify that the complete inputs reached the renderer; failures should
    # concern heat weighting, not clipping, date filtering or empty tiles.
    expect(sparse.sum { |row| row.fetch('count') }).to eq(11)
    expect(dense.sum { |row| row.fetch('count') }).to eq(1001)
    expect(sparse.map { |row| row.fetch('max_timestamp') }.max -
           sparse.map { |row| row.fetch('timestamp') }.min).to eq(600)
    expect(dense.map { |row| row.fetch('max_timestamp') }.max -
           dense.map { |row| row.fetch('timestamp') }.min).to eq(600)

    sparse_weight, dense_weight = rendered_weights([sparse, dense])
    expect(sparse_weight).to be_positive
    expect(dense_weight).to be_within(sparse_weight * 0.1).of(sparse_weight),
                            "Equal 600-second paths receive weights #{sparse_weight} and #{dense_weight}; " \
                            'recording frequency must not determine heat'
  end
end
