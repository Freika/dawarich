# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Current-year digest boundary', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }
  let(:current_year) { Time.current.year }

  around { |example| travel_to(Time.utc(2026, 6, 15, 12)) { example.run } }

  before do
    # A stat for the in-progress current year exists, so the only thing that can
    # reject `year == Time.current.year` is the upper-bound operator in
    # `valid_year?` (`>` accepts, `>=` rejects the current year).
    create(:stat, user: user, year: current_year, month: 1)
    # A stat for a complete, past year exists to keep the "still accepts a past
    # year" regression assertions meaningful.
    create(:stat, user: user, year: 2024, month: 1)
    sign_in user
  end

  describe 'POST /users/digests (web)' do
    it 'rejects the in-progress current year with an alert and does not enqueue a calculating job' do
      expect do
        post users_digests_path, params: { year: current_year }
      end.not_to have_enqueued_job(Users::Digests::Yearly::CalculatingJob)

      expect(response).to redirect_to(users_digests_path)
      expect(flash[:alert]).to eq('Invalid year selected')
      expect(flash[:notice]).to be_nil
    end

    it 'still accepts a complete, past year and enqueues a calculating job' do
      expect do
        post users_digests_path, params: { year: 2024 }
      end.to have_enqueued_job(Users::Digests::Yearly::CalculatingJob).with(user.id, 2024)

      expect(response).to redirect_to(users_digests_path)
      expect(flash[:notice]).to be_present
    end
  end

  describe 'POST /api/v1/digests (API, reference)' do
    it 'rejects the in-progress current year with 422 and does not enqueue a calculating job' do
      expect do
        post api_v1_digests_path, params: { year: current_year }, headers: headers
      end.not_to have_enqueued_job(Users::Digests::Yearly::CalculatingJob)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'still accepts a complete, past year and returns 202' do
      expect do
        post api_v1_digests_path, params: { year: 2024 }, headers: headers
      end.to have_enqueued_job(Users::Digests::Yearly::CalculatingJob).with(user.id, 2024)

      expect(response).to have_http_status(:accepted)
    end
  end
end
