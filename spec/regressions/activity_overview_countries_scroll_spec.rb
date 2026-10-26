# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Activity Overview countries scrolling', type: :request do
  let(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC' }) }

  [1, 24].each do |country_count|
    context "with #{country_count} visited countries in a year" do
      let(:country_names) { Array.new(country_count) { |index| format('Synthetic Country %02d', index + 1) } }

      before do
        create(:stat, user:, year: 2025, month: 3, distance: 1_000,
                      daily_distance: { '1' => 1_000 }, toponyms: [])
        country_names.each_with_index do |name, index|
          # Made-up points in the open South Pacific, without real location data.
          create(:point, user:, country_name: name, lonlat: 'POINT(-140 -55)',
                         timestamp: Time.utc(2025, 3, index + 1, 12).to_i)
        end
        sign_in user
      end

      it 'renders every country inside a height-limited vertical scroll area' do
        get insights_path(year: 2025)

        expect(response).to have_http_status(:ok)
        frame = Nokogiri::HTML(response.body).at_css('turbo-frame#residency-content')
        expect(frame).to be_present
        expect(frame['src']).to eq(map_residency_path(year: 2025))

        get frame['src']

        expect(response).to have_http_status(:ok)
        countries = Nokogiri::HTML(response.body).at_css('[data-testid="year-calendar-countries"]')
        expect(countries).to be_present
        expect(countries.css('button').map { |button| button['data-country'] }).to match_array(country_names)

        # Both are required: overflow alone cannot scroll an unconstrained list.
        # Leave the particular height to the layout, but reject an unlimited one.
        aggregate_failures 'bounded country list scrolling' do
          expect(countries['class'].split).to include('overflow-y-auto')
          expect(countries['class'].split).to include(a_string_matching(/\Amax-h-(?!none\z)\S+\z/))
        end
      end
    end
  end
end
