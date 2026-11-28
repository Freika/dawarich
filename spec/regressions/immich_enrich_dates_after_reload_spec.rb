# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Immich enrichment dates after a full map reload', type: :request do
  let(:user) do
    create(
      :user, :pro_plan,
      settings: {
        'timezone' => 'UTC',
        'immich_url' => 'http://127.0.0.1:9',
        'immich_api_key' => 'synthetic-immich-key'
      }
    )
  end

  before { sign_in user }

  it 'defaults both photo dates to the selected map range before controllers load' do
    get map_v2_path(start_at: '2026-04-12T00:00:00Z', end_at: '2026-04-15T23:59:00Z'),
        headers: { 'Cache-Control' => 'no-cache', 'Pragma' => 'no-cache' }

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    map = document.at_css('[data-controller~="maps--maplibre"]')
    panel = document.at_css('[data-controller="maps--immich-enrich"]')
    expect(panel).to be_present

    expected_dates = %w[start end].map do |boundary|
      map["data-maps--maplibre-#{boundary}-date-value"].split('T').first
    end
    expect(expected_dates).to eq(%w[2026-04-12 2026-04-15])

    actual_dates = %w[startDate endDate].map do |target|
      panel.at_css("input[data-maps--immich-enrich-target='#{target}']")['value'].to_s
    end
    expect(actual_dates).to eq(expected_dates)
  end

  it 'defaults both photo dates to the map dates in the user timezone across UTC midnight' do
    user.update!(settings: user.settings.merge('timezone' => 'America/Los_Angeles'))

    get map_v2_path(start_at: '2026-04-12T00:30:00Z', end_at: '2026-04-15T00:30:00Z'),
        headers: { 'Cache-Control' => 'no-cache', 'Pragma' => 'no-cache' }

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    map = document.at_css('[data-controller~="maps--maplibre"]')
    panel = document.at_css('[data-controller="maps--immich-enrich"]')
    expect(panel).to be_present

    expected_dates = %w[start end].map do |boundary|
      map["data-maps--maplibre-#{boundary}-date-value"].split('T').first
    end
    expect(expected_dates).to eq(%w[2026-04-11 2026-04-14])

    actual_dates = %w[startDate endDate].map do |target|
      panel.at_css("input[data-maps--immich-enrich-target='#{target}']")['value'].to_s
    end
    expect(actual_dates).to eq(expected_dates)
  end
end
