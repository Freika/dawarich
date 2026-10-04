# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: admin user management', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/admin_users') }
  let(:now) { Time.utc(2026, 10, 3, 10) }

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    travel_to(now) { example.run }
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  before do
    FileUtils.mkdir_p(dir)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
  end

  def seed_users
    users = (1..26).map do |n|
      email = n == 2 ? 'literal-%_@example.invalid' : format('a10-user-%02d@example.invalid', n)
      user = create(:user, id: 10_000 + n, email:, admin: [1, 5].include?(n), changelog_consent: :declined,
                           password: 'a10-synthetic-password', created_at: now - n.days, updated_at: now)
      user.update_columns(status: (n - 1) % 4, api_key: "a10-k-#{10_000 + n}",
                          settings: { 'timezone' => n == 1 ? 'Europe/Berlin' : 'UTC', 'onboarding_completed' => true },
                          points_count: n * 1234, sign_in_count: n,
                          last_sign_in_at: n.even? ? now - n.hours : nil,
                          last_sign_in_ip: n.even? ? '192.0.2.10' : nil,
                          current_sign_in_ip: '192.0.2.20', theme: 'dark')
      user.reload
    end
    users.first.update_columns(status: User.statuses.fetch('active'))
    deleted = create(:user, id: 10_999, email: 'deleted-sentinel@example.invalid', password: 'a10-synthetic-password',
                            created_at: now, updated_at: now)
    deleted.update_columns(deleted_at: now)
    seed_counts(users[1])
    users
  end

  def seed_counts(user)
    stamps = { user_id: user.id, created_at: now, updated_at: now }
    Track.insert!({ id: 10_001, start_at: now - 1.hour, end_at: now,
original_path: 'LINESTRING(0 0,0.001 0.001)' }.merge(stamps))
    Import.insert!({ id: 10_001, name: 'Synthetic import' }.merge(stamps))
    Export.insert!({ id: 10_001, name: 'Synthetic export' }.merge(stamps))
    Area.insert!({ id: 10_001, name: 'Synthetic area', radius: 100, latitude: 0, longitude: 0 }.merge(stamps))
  end

  def user_row(user, detail: false)
    row = { 'id' => user.id, 'email' => user.email, 'admin' => user.admin, 'theme' => user.theme,
            'settings' => user.settings, 'status' => User.statuses.fetch(user.status),
            'plan' => User.plans.fetch(user.plan),
            'active_until' => user.active_until.utc.iso8601(6), 'created_at' => user.created_at.utc.iso8601(6),
            'last_sign_in_at' => user.last_sign_in_at&.utc&.iso8601(6), 'points_count' => user.points_count,
            'changelog_consent' => User.changelog_consents.fetch(user.changelog_consent) }
    return row unless detail

    row.merge('api_key' => user.api_key, 'sign_in_count' => user.sign_in_count,
              'last_sign_in_ip' => user.last_sign_in_ip&.to_s, 'current_sign_in_ip' => user.current_sign_in_ip&.to_s,
              'counts' => { 'tracks' => user.tracks.count, 'imports' => user.imports.count,
                           'exports' => user.exports.count, 'areas' => user.areas.count })
  end

  def capture(name, actor, path, kind:, target: nil, registration: true)
    Rails.cache.clear
    Rails.cache.write('dawarich/registration_enabled', registration)
    reset!
    sign_in actor
    get path
    doc = Nokogiri::HTML5(response.body)
    html = doc.at_css('body > div.container > div.w-full > div.flex').inner_html
              .gsub(/(name="authenticity_token" value=")[^"]*/, '\1CSRF')
    fragment = Nokogiri::HTML5.fragment(html)
    visible_ids = fragment.css('tbody tr td:first-child a').map { |link| link['href'].split('/').last.to_i }
    { 'name' => name, 'kind' => kind, 'path' => path, 'now' => now.iso8601, 'status' => response.status,
      'title' => doc.at_css('title').text, 'headers' => response.headers.slice('Content-Type', 'Cache-Control'),
      'html' => html, 'self_hosted' => true, 'registration' => DawarichSettings.registration_enabled?,
      'user' => user_row(actor), 'target' => target && user_row(target, detail: kind == 'show'),
      'visible_ids' => visible_ids, 'rows' => if kind == 'list'
                                                User.order(created_at: :desc).map do |user|
                                                  user_row(user)
                                                end
                                              else
                                                []
                                              end }
  end

  def save_capture(capture)
    name = capture.fetch('name')
    html = capture.fetch('html').gsub(/[ \t]+$/, '').rstrip
    File.write(dir.join("#{name}.html"), html.empty? ? '' : "#{html}\n")
    File.write(dir.join("#{name}.json"),
               "#{Oj.dump(capture.except('html'), mode: :strict, float_precision: 0, indent: 2).rstrip}\n")
  end

  def management_cases
    users = seed_users
    actor = users.first.reload
    target = users[1]
    results = [['list', '/settings/users'], ['list_page2', '/settings/users?page=2'],
               ['list_out', '/settings/users?page=3'],
               ['list_literal', '/settings/users?search=%25_'], ['list_empty', '/settings/users?search=no-match']]
              .map do |name, path|
      capture(name, actor, path, kind: 'list')
    end
    results << capture('registration_disabled', actor, '/settings/users', kind: 'list', registration: false)
    [['show_target', target, 'show'], ['show_self', actor, 'show'], ['edit_target', target, 'edit'],
     ['edit_self', actor, 'edit']].each do |name, user, kind|
      suffix = kind == 'edit' ? '/edit' : ''
      results << capture(name, actor, "/settings/users/#{user.id}#{suffix}", kind:, target: user)
    end
    results
  end

  def status_cases
    users = seed_users
    actor = users.first.reload
    target = users[1]
    User.statuses.keys.map do |status|
      target.update_columns(status: User.statuses.fetch(status))
      target.reload
      capture("edit_#{status}", actor, "/settings/users/#{target.id}/edit", kind: 'edit', target:)
        .merge('selected' => status)
    end
  end

  it 'writes filtered paginated and management form cases' do
    cases = management_cases
    expect(cases.map { |capture| capture.fetch('name') })
      .to eq(%w[list list_page2 list_out list_literal list_empty registration_disabled show_target show_self
                edit_target edit_self])
    cases.each do |capture|
      expect(capture.fetch('status')).to eq(200)
      doc = Nokogiri::HTML5.fragment(capture.fetch('html'))
      if capture.fetch('kind') == 'list'
        ids = doc.css('tbody tr td:first-child a').map { |link| link['href'].split('/').last.to_i }
        expect(capture.fetch('visible_ids')).to eq(ids)
        expect(ids).not_to include(10_999)
        expect(ids.length).to be <= 25
        expect(doc.at_css('#create_user input[type="password"]')['minlength']).to eq(Devise.password_length.min.to_s)
        expect(doc.at_css("#delete_user_#{capture.dig('user', 'id')}")).to be_nil
      end
      expect(doc.css('input[name="authenticity_token"]').map { |node| node['value'] }.uniq).to eq(['CSRF'])
      save_capture(capture)
    end
    expect(cases.find { |capture| capture['name'] == 'list_literal' }.fetch('visible_ids')).to eq([10_002])
    expect(cases.find { |capture| capture['name'] == 'list_page2' }.fetch('visible_ids').length).to eq(1)
    expect(cases.find { |capture| capture['name'] == 'list_out' }.fetch('visible_ids')).to eq([])
  end

  it 'writes exact named user status options' do
    cases = status_cases
    expect(cases.map do |capture|
      capture.fetch('name')
    end).to eq(%w[edit_inactive edit_active edit_trial edit_pending_payment])
    cases.each do |capture|
      options = Nokogiri::HTML5.fragment(capture.fetch('html')).css('#user_status option')
      expect(options.map { |option| option['value'] }).to eq(%w[inactive active trial pending_payment])
      expect(options.map(&:text)).to eq(User.statuses.keys.map { |status| I18n.t("enums.user.status.#{status}") })
      selected = options.select { |option| option.key?('selected') }
      expect(selected.map { |option| option['value'] }).to eq([capture.fetch('selected')])
      save_capture(capture)
    end
  end
end
