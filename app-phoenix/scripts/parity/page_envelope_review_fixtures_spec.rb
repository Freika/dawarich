# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixtures: reviewed page envelopes', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include FixtureRecording::SyntheticSecret

  let(:uuid) { '00000000-0000-4000-8000-000000000077' }
  let(:user) { create(:user, :admin, id: 880_001, email: 'envelopes@example.invalid', changelog_consent: :declined) }

  before do
    user.update_columns(settings: user.settings.merge('onboarding_completed' => true, 'timezone' => 'UTC'))
    create(:stat, user:, year: 2026, month: 10, sharing_uuid: uuid,
                  sharing_settings: { 'enabled' => true }, toponyms: [], daily_distance: [])
    create(:users_digest, user:, year: 2026, sharing_uuid: uuid,
                          sharing_settings: { 'enabled' => true }, toponyms: [], monthly_distances: {},
                          first_time_visits: {}, time_spent_by_location: {}, year_over_year: {}, all_time_stats: {})
  end

  it 'F1 records accessible shared monthly and digest frame and XHR layouts' do
    corpus = %w[month digest].to_h do |kind|
      path = "/shared/#{kind}/#{uuid}"
      variants = {
        'html' => ["#{path}.html", { 'Accept' => 'text/html' }],
        'frame' => [path, { 'Accept' => 'text/html', 'Turbo-Frame' => 'review-frame' }],
        'js' => [path, { 'Accept' => 'text/javascript', 'X-Requested-With' => 'XMLHttpRequest' }],
        'absent' => [path, { 'Accept' => nil, 'X-Requested-With' => 'XMLHttpRequest' }]
      }
      cases = variants.transform_values { |target, headers| contract(target, headers) }
      expect(cases['html']).to include('status' => 200, 'document' => true, 'assets' => true)
      expect(cases['frame']).to include('status' => 200, 'document' => true, 'assets' => false)
      %w[js absent].each do |name|
        expect(cases[name]).to include('status' => 200, 'document' => false, 'assets' => false)
      end
      [kind, cases]
    end
    verify('f1', corpus)
  end

  it 'F2 records parameterized JavaScript XHR negotiation and HTML precedence' do
    @authenticated = true
    corpus = %w[text/javascript application/javascript].to_h do |type|
      headers = { 'Accept' => "#{type}; charset=utf-8", 'X-Requested-With' => 'XMLHttpRequest' }
      cases = {
        'tags' => contract('/tags', headers),
        'suffix' => contract('/tags.html', headers),
        'query' => contract('/tags?format=html', headers),
        'calendar' => contract('/map/timeline_feeds/calendar', headers)
      }
      expect(cases['tags']).to include('status' => 200, 'type' => 'text/html', 'document' => false)
      %w[suffix query].each { expect(cases[_1]).to include('status' => 200, 'document' => true) }
      expect(cases['calendar']).to include('status' => 406)
      [type, cases]
    end
    verify('f2', corpus)
  end

  it 'F3 records calendar quality preference parameters and stable ties' do
    @authenticated = true
    cases = [
      ['text/vnd.turbo-stream.html; q=0.5, text/html; q=1.0', false],
      ['text/html; q=0.5, text/vnd.turbo-stream.html; q=1.0', true],
      ['text/html; charset=utf-8; q=1, text/vnd.turbo-stream.html; q=0.5', false],
      ['text/vnd.turbo-stream.html; q=1, text/html; q=1', true],
      ['text/html; q=1, text/vnd.turbo-stream.html; q=1', false],
      ['text/vnd.turbo-stream.html; q=0, text/html; q=1', false],
      ['text/vnd.turbo-stream.html; q="0.5", text/html; q="1"', false],
      ['text/html; note="a,b"; q=1, text/vnd.turbo-stream.html; q=0.5', false]
    ]
    corpus = cases.to_h do |accept, stream|
      result = contract('/map/timeline_feeds/calendar?month=2026-10', { 'Accept' => accept })
      expect(result).to include('status' => 200, 'type' => stream ? 'text/vnd.turbo-stream.html' : 'text/html',
                                'stream' => stream)
      tags = contract('/tags', { 'Accept' => accept })
      expect(tags).to include('status' => 200, 'document' => true)
      [accept, result.merge('tags' => tags)]
    end
    probes = cases.map(&:first) + [
      'text/javascript; charset=utf-8', 'application/javascript; q=0',
      'application/xhtml+xml; charset=utf-8', 'text/*', 'application/*', '*/*', '',
      'text/vnd.turbo-stream.html, text/html', 'text/vnd.turbo-stream.html, */*',
      'application/unknown, text/html; q=0.5',
      'text/html; q=0, text/javascript; q=0',
      'text/html; q=bad, text/javascript; q=0.5',
      'text/html; q=0.999, text/vnd.turbo-stream.html; q=0.991',
      'text/xml; q=0.8, application/xml; q=0.5, text/html; q=1',
      'application/xml, application/rss+xml, application/atom+xml'
    ]
    negotiation = probes.product([false, true]).map do |accept, xhr|
      env = { 'HTTP_ACCEPT' => accept }
      env['HTTP_X_REQUESTED_WITH'] = 'XMLHttpRequest' if xhr
      formats = ActionDispatch::Request.new(env).formats.map(&:to_s)
      { 'accept' => accept, 'xhr' => xhr, 'formats' => formats }
    end
    verify('f3', { 'responses' => corpus, 'negotiation' => negotiation })
  end

  it 'F4 records accessible shared explicit template Turbo failures as 500' do
    corpus = %w[month digest].to_h do |kind|
      path = "/shared/#{kind}/#{uuid}"
      result = contract(path, { 'Accept' => 'text/vnd.turbo-stream.html' })
      expect(result).to include('status' => 500, 'error' => 'ActionView::MissingTemplate')
      [kind, result]
    end
    verify('f4', corpus)
  end

  def contract(path, headers)
    Warden.on_next_request { _1.set_user(user, scope: :user) } if @authenticated
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.get(path, headers: headers)
    result = session.response
    { 'status' => result.status, 'type' => result.media_type,
      'document' => result.body.include?('<html'), 'assets' => result.body.include?('/assets/application'),
      'stream' => result.body.include?('<turbo-stream') }
  rescue ActionView::MissingTemplate, ActionController::UnknownFormat => e
    { 'status' => ActionDispatch::ExceptionWrapper.status_code_for_exception(e.class.name), 'error' => e.class.name }
  end

  def verify(name, corpus)
    path = Rails.root.join("app-phoenix/test/fixtures/page_envelopes/#{name}.json")
    FixtureRecording.verify(path, "#{JSON.pretty_generate(corpus)}\n")
  end
end
