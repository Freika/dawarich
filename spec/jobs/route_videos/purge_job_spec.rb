# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RouteVideos::PurgeJob, type: :job do
  subject(:run) { described_class.perform_now }

  let(:user) { create(:user) }

  describe 'the retention window' do
    before { allow(DawarichSettings).to receive(:video_max_per_user).and_return(0) }

    it 'expires videos older than the window' do
      allow(DawarichSettings).to receive(:video_retention_days).and_return(30)
      old = create(:route_video, :with_file, user: user, created_at: 31.days.ago)

      run

      expect(old.reload).to be_status_expired
    end

    it 'leaves videos inside the window alone' do
      allow(DawarichSettings).to receive(:video_retention_days).and_return(30)
      recent = create(:route_video, :with_file, user: user, created_at: 29.days.ago)

      run

      expect(recent.reload).to be_status_stored
    end

    it 'keeps everything when the window is switched off' do
      allow(DawarichSettings).to receive(:video_retention_days).and_return(0)
      ancient = create(:route_video, :with_file, user: user, created_at: 5.years.ago)

      run

      expect(ancient.reload).to be_status_stored
    end
  end

  describe 'the per-user cap' do
    before { allow(DawarichSettings).to receive(:video_retention_days).and_return(0) }

    it 'keeps the newest videos up to the cap and expires the rest' do
      allow(DawarichSettings).to receive(:video_max_per_user).and_return(2)
      oldest = create(:route_video, :with_file, user: user, created_at: 3.days.ago)
      middle = create(:route_video, :with_file, user: user, created_at: 2.days.ago)
      newest = create(:route_video, :with_file, user: user, created_at: 1.day.ago)

      run

      expect([newest.reload.status, middle.reload.status, oldest.reload.status])
        .to eq(%w[stored stored expired])
    end

    it 'counts each user separately' do
      allow(DawarichSettings).to receive(:video_max_per_user).and_return(1)
      other_user = create(:user)
      create(:route_video, :with_file, user: user, created_at: 2.days.ago)
      theirs = create(:route_video, :with_file, user: other_user, created_at: 2.days.ago)

      run

      expect(theirs.reload).to be_status_stored
    end

    it 'keeps everything when the cap is switched off' do
      allow(DawarichSettings).to receive(:video_max_per_user).and_return(0)
      videos = create_list(:route_video, 3, :with_file, user: user)

      run

      expect(videos.map { |video| video.reload.status }).to all(eq('stored'))
    end
  end

  it 'never resurrects an already expired video' do
    allow(DawarichSettings).to receive_messages(video_retention_days: 30, video_max_per_user: 10)
    already = create(:route_video, :expired, user: user, created_at: 1.hour.ago)

    expect { run }.not_to(change { already.reload.expired_at })
  end

  it 'runs on the route_videos queue' do
    expect { described_class.perform_later }.to have_enqueued_job.on_queue('route_videos')
  end
end
