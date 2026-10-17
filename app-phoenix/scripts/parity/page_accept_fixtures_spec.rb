# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixtures: Rails Accept algorithm', type: :request do
  include FixtureRecording::SyntheticSecret

  let(:user) { create(:user, :admin, id: 880_001, email: 'envelopes@example.invalid', changelog_consent: :declined) }

  before do
    user.update_columns(settings: user.settings.merge('onboarding_completed' => true, 'timezone' => 'UTC'))
  end

  it 'F5 records leading decimal qualities in both calendar directions' do
    corpus = [
      ['text/html; q=.9, text/vnd.turbo-stream.html; q=0.5', 'text/html'],
      ['text/vnd.turbo-stream.html; q=.9, text/html; q=0.5', 'text/vnd.turbo-stream.html']
    ].to_h do |accept, type|
      result = contract('/map/timeline_feeds/calendar?month=2026-10', accept)
      expect(result).to include('status' => 200, 'type' => type)
      [accept, result]
    end
    verify('f5', corpus)
  end

  it 'F6 records mixed malformed MIME refusal before unknown type filtering' do
    corpus = ['bogus', ';', 'text/', '/html', 'application/unknown'].to_h do |type|
      accept = "text/html, #{type}"
      result = contract('/tags', accept)
      expect(result['status']).to eq(type == 'application/unknown' ? 200 : 406)
      [accept, result]
    end
    verify('f6', corpus)
  end

  it 'F7 records mixed JavaScript HTML template negotiation for tags and calendar' do
    corpus = [
      'text/javascript; q=0.9, text/html; q=0.5', 'text/javascript, text/html',
      'text/javascript; charset=utf-8, text/html', 'text/javascript; q=1, text/html; q=0'
    ].to_h do |accept|
      tags = contract('/tags', accept)
      calendar = contract('/map/timeline_feeds/calendar?month=2026-10', accept)
      expect(tags).to include('status' => 200, 'type' => 'text/html', 'document' => true)
      expect(calendar).to include('status' => 200, 'type' => 'text/html', 'stream' => false)
      [accept, { 'tags' => tags, 'calendar' => calendar }]
    end
    verify('f7', corpus)
  end

  it 'F8 records Ruby dotted exponent numeric prefixes in both calendar directions and XHR modes' do
    expect('1.e-1'.to_f).to eq(0.1)
    expect('.9'.to_f).to eq(0.9)
    expect('garbage'.to_f).to eq(0.0)
    corpus = ['1.e-1', '.9', 'garbage'].product([false, true], [false, true]).map do |q, turbo, xhr|
      preferred, alternative = if turbo
                                 ['text/vnd.turbo-stream.html', 'text/html']
                               else
                                 ['text/html', 'text/vnd.turbo-stream.html']
                               end
      accept = "#{preferred}; q=#{q}, #{alternative}; q=0.5"
      result = contract('/map/timeline_feeds/calendar?month=2026-10', accept, xhr:)
      expect(result).to include('status' => 200, 'type' => (q.to_f > 0.5 ? preferred : alternative))
      { 'accept' => accept, 'xhr' => xhr, 'response' => result }
    end
    verify('f8', corpus)
  end

  it 'F9 records clean malformed MIME refusals on place and share hub routes' do
    create(:place, id: 880_004, user:)
    corpus = ['/places/880004', '/share_links/hub'].to_h do |path|
      result = contract(path, 'text/html, bogus')
      expect(result).to include('status' => 406, 'type' => 'text/plain')
      [path, result]
    end
    verify('f9', corpus)
  end

  it 'records a generated corpus of Rails formats and calendar negotiation' do
    headers = generated_headers
    expect(headers.uniq.length).to be >= 200
    corpus = headers.product([false, true]).map do |accept, xhr|
      env = { 'HTTP_ACCEPT' => accept }
      env['HTTP_X_REQUESTED_WITH'] = 'XMLHttpRequest' if xhr
      probe = { 'accept' => accept, 'xhr' => xhr }
      begin
        request = ActionDispatch::Request.new(env)
        probe.merge('formats' => request.formats.map(&:to_s),
                    'calendar' => request.negotiate_mime([Mime[:turbo_stream], Mime[:html]])&.to_s)
      rescue ActionDispatch::Http::MimeNegotiation::InvalidType
        probe.merge('error' => 'invalid_type', 'status' => 406)
      end
    end
    verify('accept_corpus', corpus)
  end

  def generated_headers
    defaults = [
      nil, '', ' ', '*/*', 'text/html', 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml',
      'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'text/javascript, text/html, application/xml, text/xml, */*', 'application/json, text/plain, */*',
      'text/*', 'application/*', 'text/*garbage', 'text/html; note="a,b"; q=.9, text/javascript; q=.5',
      'application/xml, text/html, text/xml, application/rss+xml, application/atom+xml',
      'text/xml, application/rss+xml', 'application/xml, text/html, text/xml; q=0.9',
      'text/html,,text/javascript', ', ; q=0.5, text/html', '"', 'text/html, "unterminated',
      'text/html; q=1.e-1, text/vnd.turbo-stream.html; q=0.5'
    ]
    types = %w[text/html text/javascript application/javascript text/vnd.turbo-stream.html application/json
               application/unknown text/xml application/xml application/rss+xml bogus text/ /html ; */*]
    qualities = ['.9', '.5', '-.5', '+.9', '0', '1', '0.999', '0.991', 'bad', 'garbage', '', '2', '-1',
                 '1e-1', '1e+1', '1.e-1', '1.e+1', '1.e', '.9suffix', '1_0', '0.9_9', '0x1',
                 'NaN', 'Infinity', '".9"', '  .9']
    generated = types.product(qualities).map { |type, q| "#{type}; q=#{q}, text/html; q=0.5" }
    params = types.product(['; charset=utf-8', '; Q=0.1', ';q=0.5', '; note="a,b"', '; q=.9; q=.1'])
                  .flat_map { |type, param| ["#{type}#{param}", "#{type}#{param}, text/javascript"] }
    (defaults + generated + params).uniq
  end

  def contract(path, accept, xhr: true)
    Warden.on_next_request { _1.set_user(user, scope: :user) }
    session = ActionDispatch::Integration::Session.new(Rails.application)
    headers = { 'Accept' => accept }
    headers['X-Requested-With'] = 'XMLHttpRequest' if xhr
    session.get(path, headers:)
    result = session.response
    { 'status' => result.status, 'type' => result.media_type,
      'document' => result.body.include?('<html'), 'assets' => result.body.include?('/assets/application'),
      'stream' => result.body.include?('<turbo-stream') }
  rescue ActionDispatch::Http::MimeNegotiation::InvalidType
    { 'status' => 406, 'error' => 'invalid_type' }
  end

  def verify(name, corpus)
    path = Rails.root.join("app-phoenix/test/fixtures/page_envelopes/#{name}.json")
    FixtureRecording.verify(path, "#{JSON.pretty_generate(corpus)}\n")
  end
end
