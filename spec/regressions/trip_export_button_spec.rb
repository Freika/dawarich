# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trip export button creates a points export over the trip window', type: :request do
  let(:user) { create(:user) }
  let(:trip) do
    create(:trip,
           user:,
           name: 'Alpine Loop',
           started_at: DateTime.new(2026, 4, 1, 10, 0, 0),
           ended_at: DateTime.new(2026, 4, 3, 18, 0, 0))
  end

  before do
    allow_any_instance_of(Trip).to receive(:photo_previews).and_return([])
    sign_in user
  end

  describe 'POST /trips/:id/export' do
    context 'with format=gpx' do
      it 'creates a GPX export scoped to the trip window' do
        expect do
          post export_trip_url(trip), params: { file_format: 'gpx' }
        end.to change(user.exports, :count).by(1)

        export = user.exports.last
        expect(export.file_format).to eq('gpx')
        expect(export.file_type).to eq('points')
        expect(export.start_at).to be_within(1.second).of(trip.started_at)
        expect(export.end_at).to be_within(1.second).of(trip.ended_at)
        expect(export.name).to include('alpine-loop')
      end

      it 'enqueues the export job' do
        expect do
          post export_trip_url(trip), params: { file_format: 'gpx' }
        end.to have_enqueued_job(ExportJob)
      end

      it 'redirects to the exports index with a notice' do
        post export_trip_url(trip), params: { file_format: 'gpx' }

        expect(response).to redirect_to(exports_url)
        expect(flash[:notice]).to match(/export/i)
      end
    end

    context 'with format=json (GeoJSON)' do
      it 'creates a JSON export' do
        post export_trip_url(trip), params: { file_format: 'json' }

        expect(user.exports.last.file_format).to eq('json')
      end
    end

    context 'with an unsupported format' do
      it 'rejects the request and does not create an export' do
        expect do
          post export_trip_url(trip), params: { file_format: 'csv' }
        end.not_to change(user.exports, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(flash[:alert]).to be_present
      end
    end

    context 'when the trip belongs to another user' do
      let(:other_user) { create(:user) }
      let(:other_trip) { create(:trip, user: other_user) }

      it 'returns 404 and does not create an export' do
        expect do
          post export_trip_url(other_trip), params: { file_format: 'gpx' }
        end.not_to change(Export, :count)

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the user account is inactive' do
      before { user.update!(status: :inactive, active_until: 1.day.ago) }

      it 'still allows the trip export (matches /exports behavior)' do
        expect do
          post export_trip_url(trip), params: { file_format: 'gpx' }
        end.to change(user.exports, :count).by(1)

        expect(response).to redirect_to(exports_url)
      end
    end
  end
end
