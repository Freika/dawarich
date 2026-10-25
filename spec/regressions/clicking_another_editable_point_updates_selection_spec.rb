# frozen_string_literal: true

require 'rails_helper'
require 'open3'

RSpec.describe 'Clicking another editable point updates the selection' do
  # Execute the production event wiring, editor and tile exclusions. Only the
  # MapLibre rendering surface and unrelated UI dependencies are substituted.
  def run_harness(scenario)
    script = <<~'JS'
      const fs = require('node:fs');
      const vm = require('node:vm');
      const root = 'app/javascript/';
      const read = name => fs.readFileSync(root + name, 'utf8')
        .replace(/^import[\s\S]*?from "[^"]+"\n/gm, '')
        .replace(/^export /gm, '');
      const context = vm.createContext({ console, setTimeout, clearTimeout, scenario: process.env.SCENARIO,
        structuredClone, document: { addEventListener() {}, getElementById() { return null; } } });
      vm.runInContext(`
        const translate = key => key;
        const formatTimestamp = value => String(value);
        const formatSpeed = value => String(value);
        const formatDistance = value => String(value);
        const escapeHtml = value => String(value);
        const SettingsManager = { getSetting: () => true };
        const isGatedPlan = () => false;
        const Toast = { error: console.error };
        class EditorHistory { sync() {} }
        class EditSuccessIndicator { cancel() {} }
        class EditableTrackLayer {
          constructor(map) { this.map = map; }
          add(data) {
            this.map.layers['track-points'] = true;
            this.map.overlay = data.features.filter(f => f.properties.kind === 'point');
          }
          setData(data) { this.add(data); }
          remove() { delete this.map.layers['track-points']; this.map.overlay = []; }
        }
      `, context);
      for (const file of [
        'maps_maplibre/editing/point_drag_gesture.js',
        'maps_maplibre/editing/tile_exclusions.js',
        'maps_maplibre/editing/editable_track_data.js',
        'maps_maplibre/editing/map_editor.js',
        'controllers/maps/maplibre/event_handlers.js',
        'controllers/maps/maplibre/layer_manager.js'
      ]) vm.runInContext(read(file), context, { filename: file });
      (async () => {
        const result = await vm.runInContext(`(async () => {
          const points = [
            { id: 101, longitude: '-130.002', latitude: '-55', timestamp: 1792497600 },
            { id: 102, longitude: '-130', latitude: '-55', timestamp: 1792497660 }
          ];
          const tiles = points.map(point => ({ type: 'Feature',
            geometry: { type: 'Point', coordinates: [Number(point.longitude), Number(point.latitude)] },
            properties: { ...point, track_id: 201, count: 1 }, layer: { id: 'points-mvt' } }));
          const track = { type: 'Feature', properties: { id: 201, revision: 0, segments: [] },
            geometry: { type: 'LineString', coordinates: tiles.map(f => f.geometry.coordinates) } };
          const listeners = [];
          const filters = {};
          const matches = (filter, properties) => {
            if (filter == null) return true;
            if (!Array.isArray(filter)) return filter;
            const [op, ...args] = filter;
            const values = () => args.map(arg => matches(arg, properties));
            switch (op) {
              case 'get': return properties[args[0]];
              case 'literal': return args[0];
              case '!': return !matches(args[0], properties);
              case 'in': { const [item, list] = values(); return list.includes(item); }
              case '!=': { const [left, right] = values(); return left !== right; }
              case 'all': return values().every(Boolean);
              default: throw new Error('Unsupported filter: ' + op);
            }
          };
          const map = {
            layers: { 'points-mvt': true, 'tracks-mvt': true }, overlay: [],
            on(event, layer, handler) { listeners.push({ event, layer, handler }); },
            off(event, layer, handler) {
              const index = listeners.findIndex(l => l.event === event && l.layer === layer && l.handler === handler);
              if (index >= 0) listeners.splice(index, 1);
            },
            getLayer(id) { return this.layers[id]; },
            getFilter(id) { return filters[id] || null; },
            setFilter(id, filter) { filters[id] = filter; }, setPaintProperty() {},
            getZoom() { return 16; }, getCanvas() { return { style: {} }; },
            queryRenderedFeatures(point, { layers }) {
              return layers.flatMap(layer => {
                const features = layer === 'points-mvt' ? tiles : layer === 'track-points' ? this.overlay : [];
                return features.filter(f => Number(f.properties.id) === point.id && matches(filters[layer], f.properties))
                  .map(f => ({ ...f, layer: { id: layer } }));
              });
            },
            async click(id) {
              const event = { point: { id }, lngLat: { lng: -130, lat: -55 } };
              for (const listener of [...listeners].filter(l => l.event === 'click')) {
                if (typeof listener.layer === 'function') listener.layer(event);
                else if (this.getLayer(listener.layer)) {
                  const features = this.queryRenderedFeatures(event.point, { layers: [listener.layer] });
                  if (features.length) listener.handler({ ...event, features });
                }
              }
              // _showPointFeature opens the editor asynchronously.
              await new Promise(resolve => setTimeout(resolve, 0));
            }
          };
          const controller = { settings: {}, userPlanValue: 'pro', closeInfo() {},
            showInfo(title, content, actions) { this.info = { content, deleteId: actions?.[0]?.id }; } };
          const manager = new LayerManager(map, {}, {}, controller);
          controller.layerManager = manager;
          const handlers = new EventHandlers(map, controller);
          controller.eventHandlers = handlers;
          const editor = new MapEditor(map, { layerManager: manager, editable: true,
            apiClient: { fetchTrackWithSegments: async () => track, fetchTrackPoints: async () => points } });
          manager.registerLayer('map-editor', editor);
          manager.setupLayerEventHandlers({
            handlePointClick: handlers.handlePointClick.bind(handlers),
            handleEditablePointClick: handlers.handleEditablePointClick.bind(handlers),
            handleTrackClick: handlers.handleTrackClick.bind(handlers),
            clearTrackSelection: handlers.clearTrackSelection.bind(handlers),
            clearPointSelection: handlers.clearPointSelection.bind(handlers)
          });
          if (scenario === 'track_points_toggle') {
            handlers.selectedTrackFeature = track;
            await handlers._toggleTrackPoints(201, true);
            await map.click(102);
            return { trackStillSelected: handlers.selectedTrackFeature === track, info: controller.info ?? null };
          }
          await map.click(101);
          const first = controller.info.deleteId;
          const secondTileHits = map.queryRenderedFeatures({ id: 102 }, { layers: ['points-mvt'] }).length;
          const secondOverlayHits = map.queryRenderedFeatures({ id: 102 }, { layers: ['track-points'] }).length;
          await map.click(102);
          return { first, secondTileHits, secondOverlayHits, ...controller.info };
        })()`, context);
        process.stdout.write(JSON.stringify(result));
      })().catch(error => { console.error(error); process.exitCode = 1; });
    JS

    stdout, stderr, status = Open3.capture3({ 'SCENARIO' => scenario }, 'node', '-e', script, chdir: Rails.root)
    expect(status.success?).to be(true), "JavaScript harness failed: #{stderr}"
    JSON.parse(stdout)
  end

  it 'replaces the point details and delete target without first clicking empty map' do
    result = run_harness('editor')
    expect(result.fetch('first')).to eq(101)
    expect(result.fetch('secondTileHits')).to eq(0)
    expect(result.fetch('secondOverlayHits')).to eq(1)
    expect(result.fetch('deleteId')).to eq(102),
                                        "After clicking point 102 the Delete action still targets #{result['deleteId']}"
    expect(result.fetch('content')).to include('-55.000000, -130.000000')
  end

  it 'keeps the selected track when a point shown by the track points toggle is clicked' do
    result = run_harness('track_points_toggle')
    expect(result.fetch('trackStillSelected')).to be(true)
    expect(result.fetch('info')).to be_nil
  end
end
