# frozen_string_literal: true

require 'rails_helper'
require 'open3'
require 'tempfile'

RSpec.describe 'Import status recovery after a late subscription', type: :request do
  include ActionCable::TestHelper
  include Turbo::Streams::StreamName

  before do
    available = system('node', '-e', "require.resolve('@playwright/test')",
                       chdir: Rails.root, out: File::NULL, err: File::NULL)
    skip 'Requires Node and @playwright/test; sync is also covered by npm test' unless available
  end

  # Playwright runs the real imports controller, Stimulus and Turbo against
  # HTML rendered from the test database. All browser requests are intercepted;
  # no server, development records or external network are needed by this spec.
  def playwright_script
    <<~'JS'
      const { chromium, expect } = require('@playwright/test');
      let input = '';
      process.stdin.on('data', chunk => input += chunk);
      process.stdin.on('end', async () => {
        const data = JSON.parse(input);
        const options = { channel: process.env.PLAYWRIGHT_CHANNEL || 'chrome' };
        const browser = await chromium.launch(options);
        let heartbeat;
        try {
          const page = await browser.newPage();
          let reads = 0;
          let connect;
          await page.route('**/*', route => {
            const url = new URL(route.request().url());
            if (url.hostname !== '127.0.0.1') return route.abort();
            if (url.pathname === '/imports') {
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
          await page.goto('http://127.0.0.1:53959/imports');
          const status = page.locator(`#import_${data.id} [data-status-display]`);
          await expect(status).toContainText('Processing');
          await expect.poll(() => Boolean(connect)).toBe(true);
          // The actual job has already emitted Completed, before this subscription.
          // A normal subscription confirmation does not replay that lost frame.
          connect();
          await expect(page.locator(`turbo-cable-stream-source[signed-stream-name="${data.stream}"][connected]`)).toHaveCount(1);
          await expect(status).toContainText('Completed', { timeout: 8000 });
        } finally {
          clearInterval(heartbeat);
          await browser.close();
        }
      });
      process.on('unhandledRejection', error => { console.error(error); process.exitCode = 1; });
    JS
  end

  def browser_html(html)
    document = Nokogiri::HTML(html)
    document.css('script, link').remove
    imports = {
      '@hotwired/stimulus' => '/regression/stimulus.js',
      '@hotwired/turbo-rails' => '/regression/turbo.js',
      'controllers/imports_controller' => '/regression/imports_controller.js'
    }
    import_map = { imports: }.to_json
    document.at_css('head').add_child("<script type=\"importmap\">#{import_map}</script>")
    document.at_css('body').add_child(<<~HTML)
      <script type="module">
        import { Application } from '@hotwired/stimulus';
        import '@hotwired/turbo-rails';
        import ImportsController from 'controllers/imports_controller';
        Application.start().register('imports', ImportsController);
      </script>
    HTML
    document.to_html
  end

  it 'shows Completed without reloading when the completion broadcast precedes subscription' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    user = create(:user, settings: { 'timezone' => 'UTC' })
    sign_in user
    import = build(:import, user: user, name: 'synthetic-ocean.rec', source: :owntracks,
                            status: :processing, skip_background_processing: true)
    record = { '_type' => 'location', 'lat' => -55.0, 'lon' => -130.0, 'tst' => 1_765_000_000 }
    import.file.attach(io: StringIO.new("2025-12-06T12:26:40Z\t*\t#{record.to_json}\n"), filename: import.name)
    import.save!

    get imports_path
    expect(response).to have_http_status(:ok)
    initial = browser_html(response.body)

    messages = capture_broadcasts(stream_name_from([user, :imports])) { Import::ProcessJob.perform_now(import.id) }
    expect(import.reload).to be_completed
    expect(import.points.count).to eq(1)
    expect(messages.last).to include('Completed', "import_#{import.id}")

    get imports_path
    expect(response).to have_http_status(:ok)
    assets = {
      '/regression/stimulus.js' => Rails.application.assets.find_asset('stimulus.min.js').to_s,
      '/regression/turbo.js' => Rails.application.assets.find_asset('turbo.min.js').to_s,
      '/regression/imports_controller.js' => Rails.root.join('app/javascript/controllers/imports_controller.js').read,
      '/regression/base_controller' => Rails.root.join('app/javascript/controllers/base_controller.js').read
    }
    payload = { id: import.id, stream: Turbo::StreamsChannel.signed_stream_name([user, :imports]),
                initial:, latest: browser_html(response.body), assets: }
    directory = Rails.root.join('tmp/factory')
    FileUtils.mkdir_p(directory)
    Tempfile.create(['late-import-subscription-', '.cjs'], directory) do |script|
      script.write(playwright_script)
      script.flush
      stdout, stderr, result = Open3.capture3('node', script.path, stdin_data: payload.to_json)
      expect(result.success?).to be(true), "Playwright failed:\n#{stdout}\n#{stderr}"
    end
  end
end
