# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RouteVideos', type: :request do
  let(:user) { create(:user) }

  let(:signed_id) do
    ActiveStorage::Blob.create_and_upload!(
      io: Rails.root.join('spec/fixtures/files/route_video.mp4').open,
      filename: 'route_video.mp4',
      content_type: 'video/mp4'
    ).signed_id
  end

  let(:settings) do
    {
      'theme' => 'noir', 'format' => 'portrait', 'duration_sec' => '15',
      'units' => 'km', 'track_width' => '120', 'hud_scale' => '140',
      'camera_mode' => 'follow', 'track_color' => '#2563EB', 'watermark' => 'true'
    }
  end

  describe 'POST /route_videos' do
    context 'when signed out' do
      it 'does not create a video' do
        expect do
          post route_videos_path, params: { route_video: { name: 'Berlin', file: signed_id } }
        end.not_to change(RouteVideo, :count)
      end
    end

    context 'when signed in' do
      before { sign_in user }

      it 'stores the uploaded video against the user' do
        post route_videos_path,
             params: { route_video: { name: 'Berlin week', file: signed_id, settings: settings } },
             as: :turbo_stream

        route_video = user.route_videos.sole
        expect(route_video).to have_attributes(name: 'Berlin week', status: 'stored')
        expect(route_video.file).to be_attached
      end

      it 'keeps the recipe so the video can be re-rendered later' do
        post route_videos_path,
             params: { route_video: { name: 'Berlin week', file: signed_id, settings: settings } },
             as: :turbo_stream

        expect(user.route_videos.sole.settings).to eq(settings)
      end

      # Every control the studio offers has to survive the round trip, or a
      # re-rendered video silently comes back different from the one saved.
      it 'keeps every setting the studio can change' do
        post route_videos_path,
             params: { route_video: { name: 'Berlin week', file: signed_id, settings: settings } },
             as: :turbo_stream

        expect(user.route_videos.sole.settings.keys).to match_array(settings.keys)
      end

      it 'ignores settings keys the studio does not send' do
        post route_videos_path,
             params: {
               route_video: {
                 name: 'Berlin week', file: signed_id,
                 settings: settings.merge('payload' => 'x' * 100)
               }
             },
             as: :turbo_stream

        expect(user.route_videos.sole.settings).not_to have_key('payload')
      end

      it 'falls back to a placeholder name' do
        post route_videos_path,
             params: { route_video: { name: '', file: signed_id, settings: settings } },
             as: :turbo_stream

        expect(user.route_videos.sole.name).to eq('Untitled video')
      end

      it 'renders the new card into the gallery' do
        post route_videos_path,
             params: { route_video: { name: 'Berlin week', file: signed_id, settings: settings } },
             as: :turbo_stream

        expect(response.body).to include('route-video-gallery-list')
        expect(response.body).to include('Berlin week')
      end

      it 'reports a failure instead of raising when the blob is unusable' do
        post route_videos_path,
             params: { route_video: { name: 'Berlin week', file: 'not-a-signed-id', settings: settings } },
             as: :turbo_stream

        expect(response).to have_http_status(:unprocessable_content)
        expect(user.route_videos.reload).to be_empty
      end
    end
  end

  describe 'DELETE /route_videos/:id' do
    before { sign_in user }

    it 'removes the video' do
      route_video = create(:route_video, user: user)

      expect do
        delete route_video_path(route_video), as: :turbo_stream
      end.to change(RouteVideo, :count).by(-1)
    end

    it 'does not touch another user\'s video' do
      theirs = create(:route_video, user: create(:user))

      expect do
        delete route_video_path(theirs), as: :turbo_stream
      end.not_to change(RouteVideo, :count)

      expect(response).to have_http_status(:not_found)
    end
  end
end
