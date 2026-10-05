# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixtures: POST /exports as Rails answers it', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/point_exports') }
  let(:now) { Time.utc(2026, 9, 30, 12, 0, 0) }

  around { |example| Time.use_zone('Europe/Berlin') { example.run } }

  before do
    stub_const('Users::SafeSettings::DEFAULT_VALUES',
               Users::SafeSettings::DEFAULT_VALUES.merge('timezone' => 'UTC'))
  end

  def write_json(name, data) = FixtureRecording.verify(dir.join(name), "#{JSON.pretty_generate(data)}\n")
  def stamp(time) = time&.utc&.strftime('%Y-%m-%dT%H:%M:%S.%6NZ')

  def header_names
    %w[location content-type cache-control vary x-frame-options x-xss-protection x-content-type-options
       x-permitted-cross-domain-policies referrer-policy]
  end

  def cookie_attribute_names(header)
    header&.split('; ')&.drop(1)&.map { _1.split('=').first.downcase }&.sort
  end

  def zones
    { 9721 => 'UTC', 9722 => 'Etc/UTC', 9723 => 'Europe/Berlin', 9724 => 'Europe/London',
      9725 => 'Asia/Kathmandu', 9726 => 'America/St_Johns', 9727 => 'Pacific/Chatham',
      9728 => 'Pacific/Kiritimati', 9729 => 'America/New_York', 9730 => nil }
  end

  def ranges = [%w[2024-03-01 2024-03-31], %w[2024-10-27 2024-10-27], %w[1970-01-01 1970-12-31], [nil, nil]]

  def ok = { 'end_at' => '2024-03-31 00:00:00 +0100', 'file_format' => 'json' }
  def utc = ok.merge('start_at' => '2024-03-01 00:00:00 UTC')

  def hand_cases
    [
      ['minus zero offset', ok.merge('start_at' => '2024-03-01 00:00:00 -0000'), 'phoenix'],
      ['largest offset', ok.merge('start_at' => '2024-03-01 00:00:00 +2359'), 'phoenix'],
      ['negative offset with minutes', ok.merge('start_at' => '2024-03-01 00:00:00 -0930'), 'phoenix'],
      ['first Gregorian-only year', ok.merge('start_at' => '1583-01-01 00:00:00 +0000'), 'phoenix'],
      ['leap day', ok.merge('start_at' => '2024-02-29 23:59:59 UTC'), 'phoenix'],
      ['gpx', utc.merge('file_format' => 'gpx'), 'phoenix'],
      ['parameters Rails ignores', utc.merge('commit' => 'x', 'authenticity_token' => 'x', '_method' => 'post'),
       'phoenix'],
      ['archive format', utc.merge('file_format' => 'archive'), 'rails'],
      ['unknown format', utc.merge('file_format' => 'csv'), 'rails'],
      ['upper-case format', utc.merge('file_format' => 'JSON'), 'rails'],
      ['blank format', utc.merge('file_format' => ''), 'rails'],
      ['missing format', utc.except('file_format'), 'rails'],
      ['missing start', ok, 'rails'],
      ['blank start', ok.merge('start_at' => ''), 'rails'],
      ['date only', ok.merge('start_at' => '2024-03-01'), 'rails'],
      ['datetime-local', ok.merge('start_at' => '2024-03-01T00:00'), 'rails'],
      ['no offset', ok.merge('start_at' => '2024-03-01 00:00:00'), 'rails'],
      ['colon offset', ok.merge('start_at' => '2024-03-01 00:00:00 +01:00'), 'rails'],
      ['ISO 8601 with T and Z', ok.merge('start_at' => '2024-03-01T00:00:00Z'), 'rails'],
      ['zone abbreviation', ok.merge('start_at' => '2024-03-01 00:00:00 CET'), 'rails'],
      ['GMT', ok.merge('start_at' => '2024-03-01 00:00:00 GMT'), 'rails'],
      ['leading space', ok.merge('start_at' => ' 2024-03-01 00:00:00 UTC'), 'rails'],
      ['trailing space', ok.merge('start_at' => '2024-03-01 00:00:00 UTC '), 'rails'],
      ['impossible day', ok.merge('start_at' => '2024-02-30 00:00:00 UTC'), 'rails'],
      ['hour 24', ok.merge('start_at' => '2024-03-01 24:00:00 UTC'), 'rails'],
      ['second 60', ok.merge('start_at' => '2024-03-01 23:59:60 UTC'), 'rails'],
      ['offset hour 24', ok.merge('start_at' => '2024-03-01 00:00:00 +2400'), 'rails'],
      ['offset minute 60', ok.merge('start_at' => '2024-03-01 00:00:00 +0060'), 'rails'],
      ['Julian calendar day', ok.merge('start_at' => '1582-10-10 00:00:00 +0000'), 'rails'],
      ['year before 1583', ok.merge('start_at' => '1500-02-29 00:00:00 +0000'), 'rails'],
      ['five-digit year', ok.merge('start_at' => '10000-01-01 00:00:00 UTC'), 'rails'],
      ['single-digit month', ok.merge('start_at' => '2024-3-01 00:00:00 UTC'), 'rails'],
      ['impossible end month', utc.merge('end_at' => '2024-13-01 00:00:00 UTC'), 'rails'],
      ['method override to delete', utc.merge('_method' => 'delete'), 'rails'],
      ['client parameter', utc.merge('client' => 'ios'), 'rails'],
      ['ignored ?format=json on the request', utc, 'phoenix', '/exports?format=json']
    ]
  end

  def create_users!
    rows = zones.map { |id, zone| [id, zone ? { 'timezone' => zone } : {}, {}] }
    rows << [9731, { 'timezone' => 'UTC' }, { status: 0, plan: 0, active_until: now - 1.day }]
    rows << [9732, { 'timezone' => 'UTC' }, { status: 3 }]
    rows.map do |id, settings, columns|
      user = create(:user, id:, email: "a7s2-#{id}@dawarich.test", changelog_consent: :declined)
      user.update_columns(settings: user.settings.merge(settings).merge('onboarding_completed' => true), **columns)
      user.reload
      { id:, email: user.email, settings: user.settings, status: User.statuses[user.status],
        plan: User.plans[user.plan], active_until: user.active_until&.utc&.iso8601 }
    end
  end

  def export_links(user_id, range)
    sign_in User.find(user_id)
    start_at, end_at = range
    get '/points', params: { start_at:, end_at: }.compact
    expect(response).to have_http_status(:ok)
    links = Nokogiri::HTML5(response.body).css('a[data-turbo-method="post"][href^="/exports?"]')
    expect(links.size).to eq(2)
    sign_out :user
    links.map { |a| Rack::Utils.parse_query(URI.parse(a['href']).query) }
  end

  def export_columns(export)
    { name: export.name, status: Export.statuses[export.status],
      file_format: export.file_format && Export.file_formats[export.file_format],
      file_type: Export.file_types[export.file_type], start_at: stamp(export.start_at), end_at: stamp(export.end_at),
      url: export.url, error_message: export.error_message,
      processing_started_at: stamp(export.processing_started_at) }
  end

  def rails_answer(user_id, params, path: '/exports')
    reset!
    sign_in User.find(user_id)
    clear_enqueued_jobs
    post path, params: params
    exports = Export.where(user_id:).to_a
    expect(exports.size).to be <= 1
    answer = { status: response.status, headers: header_names.index_with { response.headers[_1] },
               header_set: response.headers.to_h.keys.map(&:downcase).sort,
               set_cookie: cookie_attribute_names(response.headers['Set-Cookie']),
               flash: flash.to_hash, export: exports.first && export_columns(exports.first),
               export_jobs: enqueued_jobs.count { _1[:job] == ExportJob } }
    Export.where(user_id:).delete_all
    sign_out :user
    answer
  end

  it 'writes the create cases' do
    travel_to now do
      users = create_users!
      cases = zones.keys.product(ranges).flat_map do |id, range|
        export_links(id, range).map do |params|
          { name: "points page, user #{id}, #{range.compact.join('..').presence || 'default range'}, " \
                  "#{params['file_format']}", user_id: id, source: 'link', expect: 'phoenix', params:,
            path: '/exports' }
        end
      end
      [9731, 9732].each do |id|
        export_links(id, ranges.first).each do |params|
          cases << { name: "points page, user #{id} (plan and status are not gated), #{params['file_format']}",
                     user_id: id, source: 'link', expect: 'phoenix', params:, path: '/exports' }
        end
      end
      hand_cases.each do |name, params, expect, path|
        cases << { name:, user_id: 9723, source: 'hand', expect:, params:, path: path || '/exports' }
      end
      cases.each { _1[:rails] = rails_answer(_1[:user_id], _1[:params], path: _1[:path] || '/exports') }

      expect(cases.select { _1[:expect] == 'phoenix' }.map { _1[:rails][:status] }.uniq).to eq([302])
      expect(cases.map { _1[:rails][:flash].keys }).to all(satisfy { |keys| keys.size <= 1 })
      expect(cases.find { _1[:name] == 'method override to delete' }.dig(:rails, :flash)).to eq({})
      write_json('cases.json', { users:, cases: })
    end
  end
end
