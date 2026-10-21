# frozen_string_literal: true

require 'rails_helper'
require 'open3'
require 'tempfile'

RSpec.describe 'Trip path recovery after a late subscription', type: :request do
  include ActionCable::TestHelper
  include Turbo::Streams::StreamName

  before do
    available = system('node', '-e', "require.resolve('@playwright/test')",
                       chdir: Rails.root, out: File::NULL, err: File::NULL)
    skip 'Requires Node and @playwright/test; sync is also covered by npm test' unless available
  end

  # Run the real trip controller, Stimulus and Turbo with test-database HTML.
  # Intercept every browser request: no running server or external tiles needed.
  def browser_html(html)
    document = Nokogiri::HTML(html)
    document.css('script:not([type="importmap"]):not(#i18n-translations), link').remove
    document.at_css('body').add_child(<<~HTML)
      <script type="module">
        import { Application } from '@hotwired/stimulus';
        import '@hotwired/turbo-rails';
        import TripController from 'controllers/trip_maplibre_controller';
        window.regressionApplication = Application.start();
        window.regressionApplication.register('trip-maplibre', TripController);
      </script>
    HTML
    document.to_html
  end

  def browser_assets(html)
    imports = JSON.parse(Nokogiri::HTML(html).at_css('script[type="importmap"]').text).fetch('imports')
    imports.values.each_with_object({}) do |url, assets|
      if url.start_with?('/assets/')
        logical_path = url.delete_prefix('/assets/').sub(/-[0-9a-f]{64}(?=\.)/, '')
        asset = Rails.application.assets.find_asset(logical_path)
        next unless asset

        assets[url] = asset.to_s
        assets["/assets/#{logical_path}"] = asset.to_s
        assets["/assets/#{logical_path.delete_suffix('.js')}"] = asset.to_s
      elsif url.start_with?('/maplibre/')
        directory = Rails.root.join('public', File.dirname(url).delete_prefix('/'))
        directory.glob('*.mjs').each { |file| assets["#{File.dirname(url)}/#{file.basename}"] = file.read }
      end
    end
  end

  def playwright_script
    <<~'JS'
      const { chromium, expect } = require('@playwright/test');
      let input = '';
      process.stdin.on('data', chunk => input += chunk);
      process.stdin.on('end', async () => {
        const data = JSON.parse(input);
        const browser = await chromium.launch({ channel: process.env.PLAYWRIGHT_CHANNEL || 'chrome' });
        let heartbeat;
        try {
          const page = await browser.newPage();
          const errors = [];
          page.on('pageerror', error => errors.push(error.message));
          let reads = 0;
          let connect;
          await page.route('**/*', route => {
            const url = new URL(route.request().url());
            if (url.hostname !== '127.0.0.1') return route.abort();
            if (url.pathname === data.path) {
              return route.fulfill({ contentType: 'text/html', body: reads++ === 0 ? data.initial : data.latest });
            }
            if (data.assets[url.pathname]) {
              return route.fulfill({ contentType: 'text/javascript', body: data.assets[url.pathname] });
            }
            return route.abort();
          });
          await page.routeWebSocket('**/cable', socket => {
            let connected = false;
            const pending = [];
            const confirm = message => {
              const command = JSON.parse(String(message));
              if (command.command === 'subscribe') {
                socket.send(JSON.stringify({ type: 'confirm_subscription', identifier: command.identifier }));
              }
            };
            socket.onMessage(message => connected ? confirm(message) : pending.push(message));
            connect = () => {
              connected = true;
              socket.send(JSON.stringify({ type: 'welcome' }));
              pending.splice(0).forEach(confirm);
              heartbeat = setInterval(() => socket.send(JSON.stringify({ type: 'ping', message: Date.now() / 1000 })), 1000);
            };
          });
          await page.goto(`http://127.0.0.1:57964${data.path}`);
          const placeholder = page.getByText('Trip path is being calculated...');
          const map = page.locator('[data-trip-maplibre-target="map"]');
          await expect(placeholder).toBeVisible();
          await expect.poll(() => page.evaluate(() => Boolean(window.regressionApplication?.getControllerForElementAndIdentifier(
            document.querySelector('[data-controller="trip-maplibre"]'), 'trip-maplibre'
          ))), { message: `Trip controller must load: ${errors.join('; ')}` }).toBe(true);
          expect(errors).toEqual([]);
          await expect.poll(() => Boolean(connect)).toBe(true);
          // CalculatePathJob already broadcast refresh before this subscription.
          // ActionCable confirms the subscription without replaying old frames.
          connect();
          await expect(page.locator(`turbo-cable-stream-source[signed-stream-name="${data.stream}"][connected]`)).toHaveCount(1);
          let automaticRefreshError;
          try {
            await expect(map).toHaveCount(1, { timeout: 8000 });
            await expect(placeholder).toHaveCount(0);
          } catch (error) {
            automaticRefreshError = error;
          }
          // Sanity check: the ready response really does contain a map.
          await page.reload();
          await expect(map).toHaveCount(1);
          await expect(placeholder).toHaveCount(0);
          if (automaticRefreshError) throw automaticRefreshError;
        } finally {
          clearInterval(heartbeat);
          await browser.close();
        }
      });
      process.on('unhandledRejection', error => { console.error(error); process.exitCode = 1; });
    JS
  end

  it 'replaces the calculating placeholder when the path finishes before the browser subscribes' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    user = create(:user, settings: { 'timezone' => 'UTC' })
    sign_in user
    start = Time.utc(2026, 1, 10, 12)
    trip = create(:trip, user:, name: 'Synthetic short ocean trip', started_at: start,
                         ended_at: start + 10.minutes, path: nil, distance: nil,
                         skip_calculation_enqueue: true)
    3.times do |index|
      create(:point, user:, timestamp: start.to_i + index * 120,
                      lonlat: "POINT(#{-130.0 + index * 0.001} -55.0)", tracker_id: 'synthetic-ocean')
    end

    get trip_path(trip)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Trip path is being calculated...')
    initial = browser_html(response.body)
    assets = browser_assets(response.body)

    messages = capture_broadcasts(stream_name_from(trip)) { Trips::CalculatePathJob.perform_now(trip.id) }
    expect(trip.reload.path).to be_present
    expect(messages).to include(a_string_including('action="refresh"'))

    get trip_path(trip)
    expect(response).to have_http_status(:ok)
    payload = { path: trip_path(trip), stream: Turbo::StreamsChannel.signed_stream_name(trip),
                initial:, latest: browser_html(response.body), assets: }
    directory = Rails.root.join('tmp/factory')
    FileUtils.mkdir_p(directory)
    Tempfile.create(['late-trip-subscription-', '.cjs'], directory) do |script|
      script.write(playwright_script)
      script.flush
      stdout, stderr, result = Open3.capture3('node', script.path, stdin_data: payload.to_json)
      expect(result.success?).to be(true), "Playwright failed:\n#{stdout}\n#{stderr}"
    end
  end
end
