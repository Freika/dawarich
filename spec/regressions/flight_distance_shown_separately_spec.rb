# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Flight distance is shown separately from tracked distance' do
  let(:user) { create(:user, settings: { 'distance_unit' => 'km' }) }

  describe 'the monthly stats page', type: :request do
    before { sign_in user }

    it 'shows the flight figure alongside the tracked one' do
      create(:stat, user: user, year: 2026, month: 4, distance: 120_000,
                    flight_distance: 633_400, daily_distance: [[1, 120_000]])

      get '/stats/2026/4'

      expect(response.body).to include('Flight distance')
      expect(response.body).to include('633')
      expect(response.body).to include('120')
      expect(response.body).to include('not counted in distance')
    end

    it 'hides the flight figure when the month has no flights' do
      create(:stat, user: user, year: 2026, month: 4, distance: 120_000,
                    flight_distance: 0, daily_distance: [[1, 120_000]])

      get '/stats/2026/4'

      expect(response.body).not_to include('Flight distance')
    end
  end

  describe 'the monthly digest email', type: :mailer do
    let(:digest) do
      create(:users_digest, :monthly, user: user, year: 2026, month: 4,
                                      distance: 120_000, flight_distance: 633_400)
    end
    let(:mail) { Users::DigestsMailer.with(user: user, digest: digest).monthly_digest }

    it 'lists flights as their own line in both parts' do
      expect(mail.html_part.body.to_s).to include('Flights')
      expect(mail.text_part.body.to_s).to include('Flights')
      expect(mail.text_part.body.to_s).to include('633')
    end

    context 'when the month has no flights' do
      let(:digest) do
        create(:users_digest, :monthly, user: user, year: 2026, month: 4,
                                        distance: 120_000, flight_distance: 0)
      end

      it 'omits the line' do
        expect(mail.text_part.body.to_s).not_to include('Flights')
      end
    end
  end
end
