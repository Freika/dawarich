# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/notes', type: :request do
  let(:user) { create(:user) }
  let(:turbo) { { Accept: 'text/vnd.turbo-stream.html' } }

  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
    user.update!(settings: user.settings.merge('timezone' => 'Asia/Tokyo'))
    sign_in user
  end

  describe 'GET /notes' do
    it 'leads to the diary on the map' do
      get notes_url

      expect(response).to redirect_to(map_v2_path(panel: 'timeline', month: 'latest'))
    end
  end

  describe 'GET /notes/new' do
    it 'renders a form for the clicked point with the moment in the user timezone' do
      get new_note_url, params: { latitude: 35.68, longitude: 139.76, noted_at: '2025-05-03T16:30:00Z' }

      expect(response).to be_successful
      expect(response.body).to include('value="35.68"', 'value="139.76"', 'value="2025-05-04T01:30"')
    end
  end

  describe 'POST /notes' do
    let(:params) do
      { note: { body: 'Rain started here', noted_at: '2025-05-04T01:30', latitude: 35.68, longitude: 139.76 } }
    end

    it 'creates a standalone map note at the moment given in the user timezone' do
      expect { post notes_url, params: params, headers: turbo }.to change(user.notes.standalone, :count).by(1)

      note = user.notes.last
      expect(note.noted_at).to eq(Time.utc(2025, 5, 3, 16, 30))
      expect(note.latitude).to be_within(0.0001).of(35.68)
      expect(response.body).to include('note:saved')
    end

    it 'rejects a note without a point' do
      expect do
        post notes_url, params: { note: params[:note].except(:latitude, :longitude) }, headers: turbo
      end.not_to change(Note, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'rejects an empty note and renders the form again' do
      post notes_url, params: { note: params[:note].merge(body: '') }, headers: turbo

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('map-note-form')
    end
  end

  describe 'PATCH /notes/:id' do
    let(:note) { create(:note, user: user, body: 'Old', latitude: 35.68, longitude: 139.76) }

    it 'updates text and time but never the point' do
      patch note_url(note), headers: turbo,
                            params: { note: { body: 'New', noted_at: '2025-05-04T09:00', latitude: 1, longitude: 2 } }

      note.reload
      expect(note.body).to eq('New')
      expect(note.noted_at).to eq(Time.utc(2025, 5, 4, 0, 0))
      expect(note.latitude).to be_within(0.0001).of(35.68)
    end

    it 'does not reach a trip day note or another user\'s note' do
      trip_note = create(:note, :trip_day, user: user)
      foreign = create(:note, latitude: 1, longitude: 2)

      patch note_url(trip_note), params: { note: { body: 'x' } }, headers: turbo
      patch note_url(foreign), params: { note: { body: 'x' } }, headers: turbo

      expect(trip_note.reload.body).not_to eq('x')
      expect(foreign.reload.body).not_to eq('x')
    end
  end

  describe 'DELETE /notes/:id' do
    it 'deletes the note and tells the map' do
      note = create(:note, user: user, latitude: 35.68, longitude: 139.76)

      expect { delete note_url(note), headers: turbo }.to change(Note, :count).by(-1)
      expect(response.body).to include('note:deleted')
    end
  end

  it 'requires sign in' do
    sign_out user
    get new_note_url
    expect(response).to redirect_to(new_user_session_path)
  end
end
