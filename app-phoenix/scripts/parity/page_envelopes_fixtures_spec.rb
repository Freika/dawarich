# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixtures: Rails page envelopes', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include FixtureRecording::SyntheticSecret

  it 'records the audited HTML XHR Turbo and historical-navigation contracts' do
    travel_to(Time.utc(2026, 10, 7, 12)) do
      user = create(:user, :admin, id: 880_001, email: 'envelopes@example.invalid',
                                 changelog_consent: :declined)
      user.update_columns(settings: user.settings.merge('onboarding_completed' => true, 'timezone' => 'UTC'))
      sign_in user
      create(:import, id: 42, user:)
      create(:notification, id: 42, user:)
      create(:trip, id: 42, user:)
      create(:place, id: 42, user:)
      create(:tag, id: 42, user:)
      create(:stat, id: 42, user:, year: 2026, month: 10)
      dir = Rails.root.join('app-phoenix/test/fixtures/page_envelopes')
      routes = JSON.parse(File.read(dir.join('routes.json'))).map { _1.fetch('route') }
      routes += %w[/recede_historical_location /resume_historical_location /refresh_historical_location]
      view_prefix = Rails.root.join('app/views').to_s
      variants = {
        'html' => ['', { 'ACCEPT' => 'text/html' }],
        'suffix' => ['.html', { 'ACCEPT' => 'text/html' }],
        'query' => ['?format=html', { 'ACCEPT' => 'application/json' }],
        'xhr' => ['', { 'ACCEPT' => 'text/html', 'X-Requested-With' => 'XMLHttpRequest' }],
        'xhr_js' => ['', { 'ACCEPT' => 'text/javascript', 'X-Requested-With' => 'XMLHttpRequest' }],
        'xhr_absent' => ['', { 'ACCEPT' => nil, 'X-Requested-With' => 'XMLHttpRequest' }],
        'empty_accept' => ['', { 'ACCEPT' => '', 'X-Requested-With' => 'XMLHttpRequest' }],
        'stream' => ['', { 'ACCEPT' => 'text/vnd.turbo-stream.html' }],
        'frame' => ['', { 'ACCEPT' => 'text/html', 'Turbo-Frame' => 'envelope-frame' }]
      }
      corpus = routes.to_h do |route|
        path = route.gsub(/:uuid|:token/, '00000000-0000-4000-8000-000000000042')
                    .gsub(':year', '2026').gsub(':month', '10').gsub(/:[a-z_]+/, '42')
        cases = variants.to_h do |name, (suffix, headers)|
          templates = []
          enqueued_jobs.clear
          event_name = /render_(template|partial|layout)\.action_view/
          subscriber = ActiveSupport::Notifications.subscribe(event_name) do |event|
            templates << event.payload[:identifier].to_s.delete_prefix(view_prefix).delete_prefix('/')
          end
          begin
            ActiveRecord::Base.transaction(requires_new: true) do
              target = path + (path == '/' ? '' : suffix)
              query = []
              query << 'format=html' if path == '/' && name == 'query'
              query << 'theme=dark' if route == '/settings/theme'
              query << 'latitude=51&longitude=12' if route == '/places/nearby'
              target += (target.include?('?') ? '&' : '?') + query.join('&') unless query.empty?
              get target, headers:
            end
            location = response.headers['Location']&.sub(%r{https?://[^/]+}, '')
            body = response.body if route.end_with?('_historical_location')
            jobs = enqueued_jobs.map { _1[:job].name }.sort
            [name, { 'status' => response.status, 'type' => response.media_type, 'location' => location,
                     'templates' => templates.uniq.sort, 'body' => body,
                     'document' => response.body.include?('<html'), 'flash' => flash.to_hash, 'jobs' => jobs }]
          rescue StandardError => e
            [name, { 'error' => e.class.name }]
          ensure
            ActiveSupport::Notifications.unsubscribe(subscriber)
          end
        end
        [route, cases]
      end
      corpus['_formatted_xhr'] = %w[/tags.html /tags?format=html].to_h do |path|
        get path, headers: { 'Accept' => nil, 'X-Requested-With' => 'XMLHttpRequest' }
        [path, { 'status' => response.status, 'document' => response.body.include?('<html') }]
      end
      expect(corpus['_formatted_xhr'].values).to all(include('status' => 200, 'document' => true))
      Warden.on_next_request { _1.set_user(user, scope: :user) }
      raw_env = Rack::MockRequest.env_for('/tags', 'HTTP_HOST' => 'www.example.com',
                                                'HTTP_X_REQUESTED_WITH' => 'XMLHttpRequest')
      raw_status, raw_headers, raw_body = Rails.application.call(raw_env)
      raw_bytes = raw_body.to_a.join
      corpus['_raw_xhr'] = { 'status' => raw_status, 'type' => raw_headers['content-type'],
                             'document' => raw_bytes.include?('<html') }
      raw_body.close if raw_body.respond_to?(:close)
      sign_out user
      get '/tags', headers: { 'Accept' => 'text/html', 'X-Requested-With' => 'XMLHttpRequest' }
      corpus['_guest_xhr'] = { 'status' => response.status, 'type' => response.media_type, 'body' => response.body }
      expect(corpus['_guest_xhr']['status']).to eq(401)
      expect(corpus.fetch('/tags').fetch('html').fetch('status')).to eq(200)
      expect(corpus.fetch('/map/timeline_feeds/calendar').fetch('stream').fetch('type'))
        .to eq('text/vnd.turbo-stream.html')
      expect(corpus.fetch('/recede_historical_location').fetch('html').fetch('body')).to eq('Going back…')
      FixtureRecording.verify(dir.join('rails.json'), "#{JSON.pretty_generate(corpus)}\n")
    end
  end
end
