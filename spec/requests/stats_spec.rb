# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/stats', type: :request do
  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

  context 'when user is not signed in' do
    describe 'GET /index' do
      it 'redirects to the sign in page' do
        get stats_url

        expect(response.status).to eq(302)
      end
    end

    describe 'GET /show' do
      it 'redirects to the sign in page' do
        get stats_url(2024)

        expect(response.status).to eq(401)
      end
    end
  end

  context 'when user is signed in' do
    before do
      sign_in user
    end

    let(:user) { create(:user) }

    describe 'GET /index' do
      it 'renders a successful response' do
        get stats_url

        expect(response.status).to eq(200)
      end
    end

    describe 'GET /show' do
      let(:stat) { create(:stat, user:, year: 2024) }

      it 'renders a successful response' do
        get stats_url(stat.year)

        expect(response.status).to eq(200)
      end
    end

    describe 'POST /update' do
      let(:stat) { create(:stat, user:, year: 2024) }

      it 'enqueues Stats::CalculatingJob for each tracked year and month' do
        allow(user).to receive(:years_tracked).and_return([2024])

        post stats_url

        (1..12).each do |month|
          expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, 2024, month)
        end
      end
    end
  end
end
