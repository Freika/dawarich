# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: the achievement pages as Rails renders them', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/achievements_ui') }
  let(:clock) { Time.utc(2026, 7, 19, 10) }
  let(:stamp) { clock.iso8601 }
  let(:secret) { 'phoenix-a2-cookie-fixture-secret-not-for-production' }

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    travel_to(clock) { example.run }
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  def shapes
    square = 'MULTIPOLYGON (((12.25 51.25,12.25 51.5,12.5 51.5,12.5 51.25,12.25 51.25)))'
    create(:country, id: 79_501, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU', geom: square)
    create(:country, id: 79_502, name: 'France', iso_a2: 'FR', iso_a3: 'FRA',
                     geom: 'MULTIPOLYGON (((12.5 51.25,12.5 51.375,12.625 51.375,12.625 51.25,12.5 51.25)))')
    create(:region, id: 79_503, code: 'DE-BY', geom: square)
  end

  def set_snapshot(set, art: false)
    result = { key: set.definition.key, name: set.name, place: set.place, total: set.total,
               target: set.target, count: set.earned_count, percent: set.percent,
               locked: set.locked?, completed: set.completed?, celebrate: set.celebrate?,
               parent_key: set.parent_key, sharing_enabled: set.sharing_enabled?, sharing_uuid: set.sharing_uuid }
    result[:card] = set.card_attributes if art
    result
  end

  def view_snapshot
    a = controller.view_assigns
    summary = a.fetch('summary')
    result = { continents: a.fetch('continents').map { |set| set_snapshot(set) },
               orphans: a.fetch('orphans').map { |set| set_snapshot(set, art: !a['set']) },
               summary: { earned_countries: summary.earned_countries, total_countries: summary.total_countries,
                          earned_subdivisions: summary.earned_subdivisions,
                          total_subdivisions: summary.total_subdivisions, percent: summary.percent } }
    return result.merge(sets: a.fetch('sets').map { |set| set_snapshot(set, art: true) }) unless a['set']

    children = a.fetch('children')
    result.merge(set: set_snapshot(a['set'], art: true), children: children.to_a, query: a['query'],
                 status: a['filter_status'], sidebar_key: a['sidebar_key'], page: children.current_page,
                 pages: children.total_pages, total: children.total_count)
  end

  def capture(name, path, user, seed_state)
    get path
    expect(response).to have_http_status(:ok)
    node = Nokogiri::HTML5(response.body).at_css('.ach-page')
    node.css('[name="authenticity_token"]').each { |input| input['value'] = 'CSRF' }
    html = "#{node.to_html}\n"
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      File.write(dir.join("#{name}.html"), html)
    else
      expect(dir.join("#{name}.html").read).to eq(html)
    end
    record = { name:, path:, user_id: user.id, settings: user.settings.slice('timezone', 'locale'), seed_state:,
               state: user.achievement_progresses.find_by(achievement_key: 'exploration')&.state,
               view: I18n.with_locale(user.locale) { view_snapshot } }
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      File.write(dir.join("#{name}.json"), "#{JSON.pretty_generate(record.deep_stringify_keys)}\n")
    else
      expect(JSON.parse(dir.join("#{name}.json").read)).to eq(record.deep_stringify_keys.as_json)
    end
  end

  def scenarios(locale)
    progress = { 'earned' => { 'DE' => stamp, 'DE-BY' => stamp } }
    france = { 'earned' => progress['earned'].merge('FR' => stamp) }
    complete = { 'earned' => Achievements::Registry.find('country_de').region_codes.index_with { stamp } }
    seen = complete.merge('celebrated' => { 'country_de' => '2026-07-19T12:00:00+02:00' })
    europe = '/achievements/continent_europe'

    [['index-empty', '/achievements', nil], ['index-progress', '/achievements', progress],
     ['detail-progress', '/achievements/country_de', progress],
     ['detail-filter', "#{europe}?q=germ&status=in_progress&commit=Apply", progress],
     ['detail-in-progress', "#{europe}?status=in_progress", france],
     ['detail-page2', "#{europe}?page=2&q=+a+&status=locked", progress],
     ['detail-locale-page2', "#{europe}?locale=#{locale}&page=2", progress],
     ['detail-page-text', "#{europe}?page=abc&status=locked", progress],
     ['detail-page-out', "#{europe}?page=1000000", progress],
     ['detail-blank-query', "#{europe}?q=%C2%A0", progress],
     ['detail-line-separator', "#{europe}?q=%E2%80%A8germany%E2%80%A8", progress],
     ['detail-empty-query', '/achievements/country_de?q=%3Cscript%3E&status=locked', progress],
     ['complete-first', '/achievements/country_de', complete], ['complete-second', '/achievements/country_de', seen]]
  end

  it 'writes the achievement pages for each locale and the state they render' do
    expect(Rails.application.secret_key_base).to eq(secret)
    expect(ENV.fetch('TIME_ZONE', nil)).to be_nil
    shapes

    %w[en de es fr pl ca zh].each_with_index do |locale, index|
      picked = scenarios(locale)
      if index > 1
        existing, additional = picked.partition { |name, *| %w[index-progress detail-page2].include?(name) }
        picked = existing + additional
      end
      picked.each_with_index do |(name, path, state), offset|
        user = create(:user, id: 79_401 + (index * 20) + offset, email: "a10-#{locale}-#{name}@example.invalid",
                             settings: { 'timezone' => 'Europe/Berlin', 'locale' => locale })
        user.persist_locale!(locale)
        create(:achievement_progress, id: user.id, user:, achievement_key: 'exploration', state:) if state
        sign_in user
        capture("#{locale}-#{name}", path, user, state)
        sign_out :user
      end
    end
  end
end
