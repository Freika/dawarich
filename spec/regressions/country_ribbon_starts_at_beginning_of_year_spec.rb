# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Country ribbon at the start of the year', type: :request do
  it 'counts days and year bounds in the user timezone so a New Year crossing starts the ribbon on January 1' do
    user = create(:user, :pro_plan, settings: { 'timezone' => 'Europe/Berlin' })
    create(:stat, user:, year: 2030, month: 1, distance: 0, toponyms: [], daily_distance: {})

    # 22:30 UTC on December 31 is still 2029 in Berlin; 23:30 UTC is already January 1.
    timestamps = [Time.utc(2029, 12, 31, 22, 30), Time.utc(2029, 12, 31, 23, 30)] +
                 (2..9).map { |day| Time.utc(2030, 1, day, 12) }
    timestamps.each_with_index do |timestamp, index|
      create(:point, user:, timestamp: timestamp.to_i,
                     longitude: -140.0 + index * 0.001, latitude: -50.0,
                     country_name: 'Ribbon Testland', reverse_geocoded_at: Time.current)
    end

    sign_in user
    get map_residency_path(year: 2030)

    expect(response).to have_http_status(:ok)
    ribbon = Nokogiri::HTML(response.body).at_css('[data-testid="country-ribbon"]')
    expect(ribbon).to be_present
    segments = ribbon.css('.country-ribbon__segment')
    expect(segments.size).to eq(1)

    aggregate_failures do
      expect(segments.first['style'][/left: ([\d.]+)%/, 1].to_f).to eq(0.0)
      expect(segments.first['aria-label']).to eq('Ribbon Testland, Jan 1 – Jan 9, 9 days')
      expect(ribbon.at_css('.badge').text.squish).to eq('9 / 365 days')
    end
  end
end
