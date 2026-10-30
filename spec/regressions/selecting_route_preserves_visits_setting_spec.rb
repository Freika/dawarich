# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'json'

RSpec.describe 'Opening Timeline with Visits disabled' do
  # Execute the real controllers together. Only browser/Stimulus, map layers
  # and API boundaries are replaced; no running server or database is needed.
  def run_scenario(scenario)
    script = <<~'JS'
      import { readFileSync } from 'node:fs';

      globalThis.CustomEvent ??= class CustomEvent extends Event {
        constructor(type, options = {}) {
          super(type, options);
          this.detail = options.detail ?? null;
        }
      };

      async function loadController(path, dependencies) {
        const source = readFileSync(path, 'utf8')
          .replace(/^import[\s\S]*?from "[^"]+"\n/gm, '');
        return import(`data:text/javascript;base64,${Buffer.from(dependencies + '\n' + source).toString('base64')}`);
      }
      const sidebarLayout = readFileSync('app/javascript/maps_maplibre/utils/sidebar_layout.js', 'utf8')
        .replace(/^export /gm, '');
      const { default: MapController } = await loadController(
        'app/javascript/controllers/maps/maplibre_controller.js', `class Controller {}\n${sidebarLayout}`);
      const { default: PanelController } = await loadController(
        'app/javascript/controllers/map_panel_controller.js', `class Controller {}\n${sidebarLayout}`);
      const { EventHandlers } = await loadController(
        'app/javascript/controllers/maps/maplibre/event_handlers.js',
        'class PointDragGesture { attach() {} }');

      function classes(initial = []) {
        const values = new Set(initial);
        return {
          contains: name => values.has(name),
          add: name => values.add(name),
          remove: name => values.delete(name),
          toggle: (name, enabled = !values.has(name)) => enabled ? values.add(name) : values.delete(name)
        };
      }
      const panel = Object.assign(new EventTarget(), { classList: classes() });
      const container = { classList: classes() };
      globalThis.window = { location: { search: '' } };
      globalThis.document = Object.assign(new EventTarget(), {
        querySelector: selector => selector === '.map-control-panel' ? panel :
          selector === '.maps-maplibre-container' ? container : null,
        getElementById: id => id === 'maps-maplibre-container' ? container : null,
        querySelectorAll: () => []
      });

      const map = new MapController();
      const visits = {
        data: { features: [] }, visible: false,
        update(data) { this.data = data; },
        show() { this.visible = true; }
      };
      let selectedTrackId = null;
      let timelineLoads = 0;
      let visitsFetches = 0;
      const tracks = { setSelectedTrack: feature => selectedTrackId = feature.properties.id };
      Object.assign(map, {
        map: { getLayer: () => null, resize() {} },
        settings: { visitsEnabled: false },
        settingsController: { settings: { visitsEnabled: false } },
        dataLoader: {
          settings: { visitsEnabled: false },
          visitsToGeoJSON: features => ({ type: 'FeatureCollection', features })
        },
        api: {
          fetchTrackWithSegments: async () => null,
          fetchVisits: async () => { visitsFetches++; return []; }
        },
        layerManager: { getLayer: name => ({ visits, tracks })[name] },
        hasVisitsToggleTarget: true,
        visitsToggleTarget: { checked: false },
        hasVisitsSearchTarget: true,
        visitsSearchTarget: { style: { display: 'none' } },
        hasSettingsPanelTarget: true,
        settingsPanelTarget: panel,
        hasContainerTarget: true,
        containerTarget: container,
        loadTimelineFeed: () => timelineLoads++
      });
      const tabs = ['layers', 'timeline-feed'].map(tab => ({
        dataset: { tabContent: tab }, classList: classes(tab === 'layers' ? ['active'] : [])
      }));
      const panelController = new PanelController();
      Object.assign(panelController, {
        application: {
          getControllerForElementAndIdentifier: element => element === panel ? panelController : map
        },
        tabButtonTargets: [], tabContentTargets: tabs, hasTitleTarget: false
      });
      panelController.connect();
      document.addEventListener('map-panel:tab-changed', map.handleTabChanged.bind(map));
      const handlers = new EventHandlers(map.map, map);
      const initiallyChecked = map.visitsToggleTarget.checked;
      if (process.env.SCENARIO === 'track') {
        handlers.handleTrackClick({
          point: { x: 200, y: 200 },
          features: [{
            type: 'Feature',
            geometry: { type: 'LineString', coordinates: [[-130.03, -55.01], [-129.97, -54.99]] },
            properties: { id: 900001, start_at: '2026-10-20T12:00:00Z' }
          }]
        });
      } else {
        panelController.openTabByName('timeline-feed');
      }
      await new Promise(resolve => setImmediate(resolve));
      console.log(JSON.stringify({
        initiallyChecked, selectedTrackId, timelineLoads,
        timelineOpen: panel.classList.contains('open') && tabs[1].classList.contains('active'),
        visitsChecked: map.visitsToggleTarget.checked,
        visitsEnabled: map.settings.visitsEnabled,
        visitsVisible: visits.visible, visitsFetches
      }));
      panelController.disconnect();
    JS

    root = File.expand_path('../..', __dir__)
    stdout, stderr, status = Open3.capture3({ 'SCENARIO' => scenario }, 'node', '--input-type=module', '-e', script,
                                            chdir: root)
    expect(status.success?).to be(true), stderr
    JSON.parse(stdout)
  end

  it 'opens the route in Timeline without enabling Visits' do
    state = run_scenario('track')

    expect(state).to include('initiallyChecked' => false, 'selectedTrackId' => 900_001,
                             'timelineLoads' => 1, 'timelineOpen' => true)
    expect(state).to include('visitsChecked' => false, 'visitsEnabled' => false,
                             'visitsVisible' => false, 'visitsFetches' => 0)
  end

  it 'opens Timeline directly without enabling Visits' do
    state = run_scenario('tab')

    expect(state).to include('initiallyChecked' => false, 'selectedTrackId' => nil,
                             'timelineLoads' => 1, 'timelineOpen' => true)
    expect(state).to include('visitsChecked' => false, 'visitsEnabled' => false,
                             'visitsVisible' => false, 'visitsFetches' => 0)
  end
end
