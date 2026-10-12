# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Manual recalculation of a trip after underlying points change',
               type: :request do
  let(:user) { create(:user) }

  let!(:trip) do
    create(:trip,
           user: user,
           started_at: DateTime.new(2024, 11, 27, 12, 0, 0),
           ended_at: DateTime.new(2024, 11, 27, 14, 0, 0),
           distance: 130_362,
           path: 'LINESTRING(13.0 52.0, 13.5 52.5, 14.0 53.0)',
           visited_countries: ['Germany'])
  end

  before { sign_in user }

  describe 'POST /trips/:id/recalculate' do
    it 'enqueues Trips::CalculateAllJob with the trip id and stamps last_recalculated_at' do
      expect do
        post recalculate_trip_path(trip)
      end.to have_enqueued_job(Trips::CalculateAllJob).with(trip.id, anything)

      expect(trip.reload.last_recalculated_at).to be_within(5.seconds).of(Time.current)
    end

    it 'responds with a turbo_stream that swaps the recalculate frame' do
      post recalculate_trip_path(trip), headers: { 'Accept' => Mime[:turbo_stream].to_s }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body).to include('turbo-stream')
      expect(response.body).to include('trip_recalculate_frame')
    end

    it 'falls back to an HTML redirect with a notice for non-turbo requests' do
      allow_any_instance_of(Trip).to receive(:photo_previews).and_return([])
      allow_any_instance_of(Trip).to receive(:photo_sources).and_return([])

      post recalculate_trip_path(trip)

      expect(response).to redirect_to(trip_path(trip))
      follow_redirect!
      expect(flash[:notice]).to match(/recalculat/i)
    end

    it 'does not enqueue a second job while a recalculation is in flight' do
      post recalculate_trip_path(trip)

      expect do
        post recalculate_trip_path(trip)
      end.not_to have_enqueued_job(Trips::CalculateAllJob)
    end

    it 'returns 404 for another user\'s trip and does not enqueue the job' do
      other_user = create(:user)
      foreign_trip = create(:trip, user: other_user, path: nil)

      expect do
        post recalculate_trip_path(foreign_trip)
      end.not_to have_enqueued_job(Trips::CalculateAllJob)

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects inactive users via authenticate_active_user!' do
      user.update!(active_until: 1.day.ago)

      expect do
        post recalculate_trip_path(trip)
      end.not_to have_enqueued_job(Trips::CalculateAllJob)

      expect(response).to redirect_to(root_path)
    end
  end

  describe 'GET /trips/:id' do
    before do
      allow_any_instance_of(Trip).to receive(:photo_previews).and_return([])
      allow_any_instance_of(Trip).to receive(:photo_sources).and_return([])
    end

    it 'does not auto-enqueue CalculateAllJob when all cached fields are populated' do
      expect { get trip_path(trip) }.not_to have_enqueued_job(Trips::CalculateAllJob)
    end

    it 'auto-enqueues CalculateAllJob when path, distance, or visited countries are blank' do
      stale_trip = create(:trip,
                          user: user,
                          started_at: DateTime.new(2024, 11, 27, 12, 0, 0),
                          ended_at: DateTime.new(2024, 11, 27, 14, 0, 0),
                          distance: nil,
                          path: nil,
                          visited_countries: [])

      expect { get trip_path(stale_trip) }
        .to have_enqueued_job(Trips::CalculateAllJob).with(stale_trip.id, anything)
    end
  end
end
