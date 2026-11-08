# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'

RSpec.describe 'Video export waits for the current route to render' do
  # Exercise the production frame loop, timeline, smoothing and render plan.
  # Replace browser I/O with a map whose asynchronous source processing takes
  # a known time. No GPU, remote tiles, codecs or real location data are used.
  def render_script
    <<~'JS'
      import { readFileSync } from 'node:fs';
      const delay = Number(process.env.SOURCE_DELAY_MS);
      const captures = [];
      let map;
      class AsyncMap {
        constructor() {
          map = this;
          this.listeners = new Map();
          this.pending = 0;
          this.requested = 0;
          this.rendered = 0;
          queueMicrotask(() => this.idle());
        }
        once(event, callback) {
          const callbacks = this.listeners.get(event) ?? new Set();
          callbacks.add(callback);
          this.listeners.set(event, callbacks);
        }
        off(event, callback) { this.listeners.get(event)?.delete(callback); }
        idle() {
          const callbacks = [...(this.listeners.get('idle') ?? [])];
          this.listeners.delete('idle');
          for (const callback of callbacks) callback();
        }
        getSource(id) {
          return { setData: data => {
            const version = id === 'poster-track' ? ++this.requested : null;
            this.pending++;
            setTimeout(() => {
              if (version !== null) this.rendered = version;
              if (--this.pending === 0) this.idle();
            }, delay);
          }};
        }
        triggerRepaint() {
          if (this.pending === 0) queueMicrotask(() => this.idle());
        }
        getCanvas() { return this; }
        remove() {}
      }
      const ctx = {
        drawImage(canvas) {
          captures.push({ requested: canvas.requested, rendered: canvas.rendered });
        },
      };
      globalThis.document = {
        hidden: false,
        addEventListener() {},
        removeEventListener() {},
        body: { appendChild() {} },
        createElement: () => ({ style: {}, getContext: () => ctx, remove() {} }),
      };
      const encoder = { async addFrame() {}, async finalize() { return {}; }, abort() {} };
      // Importmap dependencies are concatenated as in the existing JS tests.
      // Only browser adapters and HUD drawing are substituted.
      const adapters = `
        const maplibregl = { Map: globalThis.testMap };
        const TRACK_SOURCE_ID = 'poster-track';
        const RENDER_CSS_SCALE = 0.5, RENDER_FIT_PADDING = 40;
        const trackBounds = () => null;
        const ensureHudFonts = async () => ({});
        const createMp4Encoder = async () => globalThis.testEncoder;
        const drawHud = () => {}, drawRouteMarker = () => {}, drawFogOverlay = () => {};
      `;
      globalThis.testMap = AsyncMap;
      globalThis.testEncoder = encoder;
      const files = ['geo', 'color_util', 'path_smoothing', 'route_timeline',
        'route_clock', 'camera_path', 'render_plan', 'video_renderer'];
      const source = adapters + files.map(name =>
        readFileSync(`app/javascript/video_studio/${name}.js`, 'utf8')
          .replace(/^import[\s\S]*?from "[^"]+"\n/gm, '')
          .replace(/^export /gm, '')
      ).join('\n') + '\nexport { renderRouteVideo };';
      const { renderRouteVideo } = await import(
        'data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
      // Invented dense route in the open South Pacific, far from settlements.
      const coordinates = Array.from({ length: 410_000 }, (_, i) => [-140 + i / 1_000_000, -50]);
      await renderRouteVideo({
        style: { sources: { 'poster-track': {} }, layers: [] },
        trackGeojson: { type: 'FeatureCollection', features: [{
          type: 'Feature', properties: { startTime: 1_780_272_000 },
          geometry: { type: 'LineString', coordinates },
        }] },
        points: [], width: 1440, height: 900, durationSec: 8, fps: 1,
      });
      console.log(JSON.stringify({
        frames: captures.length,
        staleFrames: captures.flatMap((frame, index) =>
          frame.rendered === frame.requested ? [] : [{ index, ...frame }]),
      }));
    JS
  end

  [50, 650].each do |delay|
    it "captures only the current route when source processing takes #{delay} ms" do
      stdout, stderr, status = Open3.capture3(
        { 'SOURCE_DELAY_MS' => delay.to_s }, 'node', '--input-type=module', '-e', render_script,
        chdir: File.expand_path('../..', __dir__)
      )
      expect(status.success?).to be(true), "Renderer harness failed:\n#{stderr}"
      result = JSON.parse(stdout)

      expect(result.fetch('frames')).to eq(8)
      stale = result.fetch('staleFrames')
      expect(stale).to eq([]), "Export captured an older route before the map finished rendering: #{stale}"
    end
  end
end
