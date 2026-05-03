# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trip countries card empty-state honesty' do
  let(:user) { create(:user) }
  let(:trip) do
    create(:trip,
           user: user,
           started_at: DateTime.new(2024, 11, 27, 0, 0, 0),
           ended_at:   DateTime.new(2024, 11, 29, 0, 0, 0))
  end

  def render_partial
    ApplicationController.render(
      partial: 'trips/countries',
      locals: { trip: trip.reload, current_user: user, distance_unit: 'km' }
    )
  end

  context 'when no point in the trip window has a country_name' do
    before do
      3.times do |i|
        create(:point,
               user: user,
               timestamp: trip.started_at.to_i + (i + 1) * 3600,
               country_name: nil,
               city: nil,
               reverse_geocoded_at: nil)
      end
      trip.calculate_countries
      trip.save!
    end

    it 'leaves visited_countries empty' do
      expect(trip.reload.visited_countries).to eq([])
    end

    it 'renders an em-dash placeholder in the card, not an indefinite spinner' do
      html = render_partial
      card_segment = html.split('<dialog').first

      expect(card_segment).to include('&mdash;')
      expect(card_segment).not_to include('loading loading-dots')
    end

    it 'still explains the empty state in the modal' do
      html = render_partial
      modal_segment = html.partition('<dialog').last

      expect(modal_segment).to include('No countries data available yet.')
    end
  end

  context 'when a point has country_name set' do
    before do
      create(:point,
             user: user,
             timestamp: trip.started_at.to_i + 3600,
             country_name: 'Germany',
             city: 'Berlin',
             reverse_geocoded_at: Time.current)
      trip.calculate_countries
      trip.save!
    end

    it 'shows the count in the card and the country in the modal' do
      html = render_partial

      expect(html).to match(%r{Countries</div>\s*<div[^>]*>\s*1\s*</div>}m)
      expect(html).to include('Germany')
      expect(html).not_to include('loading loading-dots')
      expect(html).not_to include('&mdash;')
    end
  end
end
