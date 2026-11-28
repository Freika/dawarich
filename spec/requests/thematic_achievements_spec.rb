# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Thematic achievement collections' do
  let(:user) { create(:user) }

  before { sign_in user }

  def exploration(earned)
    create(:achievement_progress, user: user, achievement_key: 'exploration', state: { 'earned' => earned })
  end

  it 'offers the three country collections alongside continents, keeping world tiers hidden' do
    get achievements_path

    document = Nokogiri::HTML(response.body)
    section = document.at_css('#thematic-collections')
    expect(section).to be_present
    expect(section.css('.card-title').map(&:text)).to eq(%w[Benelux Baltics Scandinavia])
    expect(section.css('a.ach-card-link').map { |link| link['href'] }).to include(
      achievement_path('thematic_benelux_v1'), achievement_path('thematic_baltics_v1'),
      achievement_path('thematic_scandinavia_v1')
    )
    expect(response.body).not_to include('Border Hopper')
  end

  it 'counts visited countries independently of their subdivision completion' do
    exploration('EE' => '2026-05-01', 'LV' => '2026-05-02', 'DE' => '2026-05-03')

    get achievement_path('thematic_baltics_v1')

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('h1').text).to eq('Baltics')
    expect(document.at_css('.ach-progress-summary').text).to include('2 of 3 countries visited')
    expect(document.css('.ach-child-grid .card-title').map(&:text)).to match_array(%w[Estonia Latvia Lithuania])
    estonia = document.at_css('[data-achievement-card-key-value="country_ee"]')
    expect(estonia.text).to include('Visited', '1 May 2026')
    expect(estonia.text).not_to include('regions')
    expect(document.at_css('.ach-side--desktop [aria-current="page"]')['href'])
      .to eq(achievement_path('thematic_baltics_v1'))
    expect(document.at_css('.ach-mobile-nav summary').text).to include('Baltics')
  end

  it 'filters visited countries as unlocked even when no subdivisions are earned' do
    exploration('EE' => '2026-05-01')

    get achievement_path('thematic_baltics_v1'), params: { status: 'unlocked' }

    document = Nokogiri::HTML(response.body)
    expect(document.css('.ach-child-grid .card-title').map(&:text)).to eq(['Estonia'])
    expect(document.css('select[name="status"] option').map { |option| option['value'] })
      .not_to include('in_progress')
  end

  it 'celebrates a completed theme once and dates it from the last visited member' do
    progress = exploration('EE' => '2026-05-01', 'LV' => '2026-05-02', 'LT' => '2026-05-03')

    get achievements_path

    expect(progress.reload.state.dig('celebrated', 'thematic_baltics_v1')).to be_present
    get achievement_path('thematic_baltics_v1')

    document = Nokogiri::HTML(response.body)
    expect(document.at_css('.ach-progress-caption').text).to include('May 03, 2026')
    expect(document.css('.ach-card-wrap--celebrate')).to be_empty
  end

  it 'localizes the collection and keeps its public sharing private until enabled' do
    user.persist_locale!(:de)
    get achievement_path('thematic_baltics_v1')

    document = Nokogiri::HTML(response.body)
    expect(document.at_css('h1').text).to eq('Baltikum')
    expect(document.at_css('.card-description').text).to include('allen 3 Ländern')
    expect(user.achievement_progresses.where(sharing_enabled: true)).not_to exist

    patch toggle_sharing_achievement_path('thematic_baltics_v1'), params: { enabled: true }, as: :json
    uuid = response.parsed_body.fetch('uuid')
    sign_out user
    get shared_achievement_path(uuid)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Baltikum')
  end
end
