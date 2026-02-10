# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/trips/:trip_id/notes', type: :request do
  let(:user) { create(:user) }
  let(:trip) { create(:trip, user: user) }

  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})

    sign_in user
  end

  describe 'POST /trips/:trip_id/notes' do
    let(:valid_params) do
      {
        note: {
          date: trip.started_at.to_date,
          body: 'Great day exploring!'
        }
      }
    end

    context 'with valid parameters' do
      it 'creates a new note' do
        expect do
          post trip_notes_url(trip), params: valid_params
        end.to change(Note, :count).by(1)
      end

      it 'redirects to the trip for HTML format' do
        post trip_notes_url(trip), params: valid_params
        expect(response).to redirect_to(trip)
      end

      it 'responds with turbo stream for turbo requests' do
        post trip_notes_url(trip), params: valid_params,
                                  headers: { Accept: 'text/vnd.turbo-stream.html' }
        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      end
    end

    context 'with find_or_initialize (idempotent create)' do
      let!(:existing_note) do
        create(:note, user: user, attachable: trip,
                      noted_at: trip.started_at.to_date.to_datetime.noon, body: 'Old note')
      end

      it 'updates existing note instead of creating a duplicate' do
        expect do
          post trip_notes_url(trip), params: valid_params
        end.not_to change(Note, :count)

        existing_note.reload
        expect(existing_note.body.to_plain_text).to eq('Great day exploring!')
      end
    end

    context 'with date outside trip range' do
      let(:invalid_params) do
        {
          note: {
            date: trip.started_at.to_date - 10.days,
            body: 'This should fail'
          }
        }
      end

      it 'does not create the note' do
        expect do
          post trip_notes_url(trip), params: invalid_params
        end.not_to change(Note, :count)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        post trip_notes_url(trip), params: valid_params
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when accessing another user trip' do
      let(:other_user) { create(:user) }
      let(:other_trip) { create(:trip, user: other_user) }

      it 'returns not found' do
        post trip_notes_url(other_trip), params: valid_params
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PATCH /trips/:trip_id/notes/:id' do
    let!(:note) do
      create(:note, user: user, attachable: trip,
                    noted_at: trip.started_at.to_date.to_datetime.noon, body: 'Original note')
    end

    let(:update_params) do
      {
        note: {
          body: 'Updated note content'
        }
      }
    end

    context 'with valid parameters' do
      it 'updates the note' do
        patch trip_note_url(trip, note), params: update_params
        note.reload
        expect(note.body.to_plain_text).to eq('Updated note content')
      end

      it 'redirects to the trip for HTML format' do
        patch trip_note_url(trip, note), params: update_params
        expect(response).to redirect_to(trip)
      end
    end

    context 'when accessing another user trip' do
      let(:other_user) { create(:user) }
      let(:other_trip) { create(:trip, user: other_user) }
      let!(:other_note) do
        create(:note, user: other_user, attachable: other_trip,
                      noted_at: other_trip.started_at.to_date.to_datetime.noon, body: 'Other note')
      end

      it 'returns not found' do
        patch trip_note_url(other_trip, other_note), params: update_params
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /trips/:trip_id/notes/:id' do
    let!(:note) do
      create(:note, user: user, attachable: trip,
                    noted_at: trip.started_at.to_date.to_datetime.noon, body: 'Note to delete')
    end

    it 'destroys the note' do
      expect do
        delete trip_note_url(trip, note)
      end.to change(Note, :count).by(-1)
    end

    it 'redirects to the trip for HTML format' do
      delete trip_note_url(trip, note)
      expect(response).to redirect_to(trip)
    end

    context 'when accessing another user trip' do
      let(:other_user) { create(:user) }
      let(:other_trip) { create(:trip, user: other_user) }
      let!(:other_note) do
        create(:note, user: other_user, attachable: other_trip,
                      noted_at: other_trip.started_at.to_date.to_datetime.noon, body: 'Other note')
      end

      it 'returns not found' do
        expect do
          delete trip_note_url(other_trip, other_note)
        end.not_to change(Note, :count)

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
