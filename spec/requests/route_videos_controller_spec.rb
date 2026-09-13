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

  # Mirrors what the studio actually posts: FormData, so every value is a
  # string, and the provenance the re-render path reads back.
  let(:settings) do
    {
      'theme' => 'noir', 'format' => 'portrait', 'duration_sec' => '15',
      'units' => 'km', 'track_width' => '120', 'hud_scale' => '140',
      'camera_mode' => 'follow', 'track_color' => '#2563EB', 'watermark' => 'true',
      'source' => 'map', 'start_at' => '2026-06-14T00:00', 'end_at' => '2026-06-16T23:59'
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
      it 'keeps the route a video was made from, not just its looks' do
        post route_videos_path,
             params: { route_video: { name: 'Berlin week', file: signed_id, settings: settings } },
             as: :turbo_stream

        expect(user.route_videos.sole.settings).to include(
          'source' => 'map', 'start_at' => '2026-06-14T00:00', 'end_at' => '2026-06-16T23:59'
        )
      end

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

      # The signed id comes back from a direct upload, so the blob it names is
      # whatever the browser chose to send. Nothing about that is trusted.
      it 'refuses a blob that is not a video' do
        other = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new('not a video'),
          filename: 'notes.txt',
          content_type: 'text/plain'
        ).signed_id

        post route_videos_path,
             params: { route_video: { name: 'Berlin week', file: other, settings: settings } },
             as: :turbo_stream

        expect(response).to have_http_status(:unprocessable_content)
        expect(user.route_videos.reload).to be_empty
      end

      it 'refuses a blob bigger than the ceiling' do
        stub_const('RouteVideosController::MAX_FILE_BYTES', 8)

        post route_videos_path,
             params: { route_video: { name: 'Berlin week', file: signed_id, settings: settings } },
             as: :turbo_stream

        expect(response).to have_http_status(:unprocessable_content)
        expect(user.route_videos.reload).to be_empty
      end

      # The cap is a rolling window, matching what the env sample promises and
      # what the nightly purge does — refusing here would throw away a video
      # the browser has already spent a minute rendering and uploading.
      it 'expires the oldest video rather than refusing a save past the cap' do
        allow(DawarichSettings).to receive(:video_max_per_user).and_return(1)
        oldest = create(:route_video, :with_file, user: user, created_at: 2.days.ago)

        post route_videos_path,
             params: { route_video: { name: 'Berlin week', file: signed_id, settings: settings } },
             as: :turbo_stream

        expect(user.route_videos.reload.count).to eq(2)
        expect(oldest.reload).to be_status_expired
        expect(user.route_videos.status_stored.sole.name).to eq('Berlin week')
      end

      # The evicted card is already on the page with a playable source that is
      # about to 404, so the same response has to redraw it.
      it 'redraws the card of a video the save evicted' do
        allow(DawarichSettings).to receive(:video_max_per_user).and_return(1)
        oldest = create(:route_video, :with_file, user: user, created_at: 2.days.ago)

        post route_videos_path,
             params: { route_video: { name: 'Berlin week', file: signed_id, settings: settings } },
             as: :turbo_stream

        expect(response.body).to include("replace\" target=\"#{ActionView::RecordIdentifier.dom_id(oldest)}")
      end

      # A direct upload has already written the blob by the time the request
      # arrives, and nothing sweeps unattached blobs.
      # `attach` on an unsaved record only stages the join row, so a `save!`
      # that raises leaves the uploaded blob with no owner and nothing sweeps
      # unattached blobs.
      it 'purges the uploaded file when the save fails before it is attached' do
        allow_any_instance_of(RouteVideo).to receive(:save!).and_raise('boom')
        blob = ActiveStorage::Blob.find_signed!(signed_id)

        expect do
          post route_videos_path,
               params: { route_video: { name: 'Berlin week', file: blob.signed_id, settings: settings } },
               as: :turbo_stream
        end.to have_enqueued_job(ActiveStorage::PurgeJob).with(blob)
      end

      # The raise lands after `save!`, so the blob is attached and committed —
      # the guard has to leave it alone rather than purge a live video's file.
      it 'keeps the uploaded file when the save blows up after attaching it' do
        allow(RouteVideo).to receive(:expire_over_cap).and_raise('boom')

        expect do
          post route_videos_path,
               params: { route_video: { name: 'Berlin week', file: signed_id, settings: settings } },
               as: :turbo_stream
        end.not_to have_enqueued_job(ActiveStorage::PurgeJob)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'does not strand the uploaded file when it refuses one' do
        other = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new('not a video'),
          filename: 'notes.txt',
          content_type: 'text/plain'
        )

        expect do
          post route_videos_path,
               params: { route_video: { name: 'Berlin week', file: other.signed_id, settings: settings } },
               as: :turbo_stream
        end.to have_enqueued_job(ActiveStorage::PurgeJob).with(other)
      end

      it 'still stores when the cap is switched off' do
        allow(DawarichSettings).to receive(:video_max_per_user).and_return(0)
        create_list(:route_video, 3, :with_file, user: user)

        post route_videos_path,
             params: { route_video: { name: 'Berlin week', file: signed_id, settings: settings } },
             as: :turbo_stream

        expect(user.route_videos.reload.count).to eq(4)
      end

      it 'does not let a crafted setting grow the row without bound' do
        post route_videos_path,
             params: {
               route_video: {
                 name: 'Berlin week', file: signed_id,
                 settings: settings.merge('theme' => 'x' * 5_000)
               }
             },
             as: :turbo_stream

        expect(user.route_videos.sole.settings['theme'].length).to be <= 64
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
