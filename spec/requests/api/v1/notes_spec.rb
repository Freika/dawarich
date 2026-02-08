# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/api/v1/notes', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  describe 'GET /index' do
    let!(:note) { create(:note, user: user, noted_at: Time.current) }

    it 'renders a successful response' do
      get api_v1_notes_url, headers: headers
      expect(response).to be_successful
    end

    it 'returns notes for the current user' do
      get api_v1_notes_url, headers: headers
      json = JSON.parse(response.body)
      expect(json.length).to eq(1)
      expect(json.first['id']).to eq(note.id)
    end

    context 'with filtering params' do
      let(:trip) { create(:trip, user: user) }
      let!(:trip_note) do
        create(:note, user: user, attachable: trip,
                      noted_at: trip.started_at.to_date.to_datetime.noon)
      end

      it 'filters by attachable_type' do
        get api_v1_notes_url, headers: headers, params: { attachable_type: 'Trip' }
        json = JSON.parse(response.body)
        expect(json.length).to eq(1)
        expect(json.first['id']).to eq(trip_note.id)
      end

      it 'filters standalone notes' do
        get api_v1_notes_url, headers: headers, params: { standalone: 'true' }
        json = JSON.parse(response.body)
        expect(json.length).to eq(1)
        expect(json.first['id']).to eq(note.id)
      end
    end

    it 'returns 401 without auth' do
      get api_v1_notes_url
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /show' do
    let(:note) { create(:note, user: user, noted_at: Time.current) }

    it 'renders a successful response' do
      get api_v1_note_url(note), headers: headers
      expect(response).to be_successful
    end

    it 'returns the note' do
      get api_v1_note_url(note), headers: headers
      json = JSON.parse(response.body)
      expect(json['id']).to eq(note.id)
    end

    it 'returns 404 for another user note' do
      other_note = create(:note, noted_at: Time.current)
      get api_v1_note_url(other_note), headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /create' do
    context 'with valid parameters' do
      let(:valid_params) do
        { note: { body: 'A test note', noted_at: Time.current.iso8601 } }
      end

      it 'creates a new Note' do
        expect do
          post api_v1_notes_url, headers: headers, params: valid_params
        end.to change(Note, :count).by(1)
      end

      it 'returns created status' do
        post api_v1_notes_url, headers: headers, params: valid_params
        expect(response).to have_http_status(:created)
      end
    end

    context 'with attachable' do
      let(:trip) { create(:trip, user: user) }

      it 'creates a note attached to a trip' do
        params = {
          note: {
            body: 'Trip note',
            noted_at: trip.started_at.to_date.to_datetime.noon.iso8601,
            attachable_type: 'Trip',
            attachable_id: trip.id
          }
        }

        expect do
          post api_v1_notes_url, headers: headers, params: params
        end.to change(Note, :count).by(1)

        expect(response).to have_http_status(:created)
      end
    end

    context 'with cross-user attachable' do
      let(:other_user) { create(:user) }
      let(:other_trip) { create(:trip, user: other_user) }

      it 'rejects note attached to another user trip' do
        params = {
          note: {
            body: 'Sneaky note',
            noted_at: other_trip.started_at.to_date.to_datetime.noon.iso8601,
            attachable_type: 'Trip',
            attachable_id: other_trip.id
          }
        }

        expect do
          post api_v1_notes_url, headers: headers, params: params
        end.not_to change(Note, :count)

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['errors']).to include('Attachable must belong to the same user')
      end
    end

    context 'with invalid parameters' do
      it 'returns 422 when noted_at is missing' do
        post api_v1_notes_url, headers: headers, params: { note: { body: 'No date' } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'PATCH /update' do
    let(:note) { create(:note, user: user, body: 'Original', noted_at: Time.current) }

    context 'with valid parameters' do
      it 'updates the note' do
        patch api_v1_note_url(note), headers: headers,
                                     params: { note: { body: 'Updated' } }
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['body']).to eq('Updated')
      end
    end

    context 'with invalid parameters' do
      it 'returns 422' do
        patch api_v1_note_url(note), headers: headers,
                                     params: { note: { noted_at: nil } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'with another user note' do
      let(:other_note) { create(:note, noted_at: Time.current) }

      it 'returns 404' do
        patch api_v1_note_url(other_note), headers: headers,
                                           params: { note: { body: 'Hijack' } }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /destroy' do
    let!(:note) { create(:note, user: user, noted_at: Time.current) }

    it 'destroys the note' do
      expect do
        delete api_v1_note_url(note), headers: headers
      end.to change(Note, :count).by(-1)
    end

    it 'returns ok status' do
      delete api_v1_note_url(note), headers: headers
      expect(response).to have_http_status(:ok)
    end

    context 'with another user note' do
      let!(:other_note) { create(:note, noted_at: Time.current) }

      it 'returns 404' do
        expect do
          delete api_v1_note_url(other_note), headers: headers
        end.not_to change(Note, :count)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /create with invalid attachable_type' do
    it 'rejects an invalid attachable_type' do
      params = {
        note: {
          body: 'Sneaky note',
          noted_at: Time.current.iso8601,
          attachable_type: 'User',
          attachable_id: user.id
        }
      }

      expect do
        post api_v1_notes_url, headers: headers, params: params
      end.not_to change(Note, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
