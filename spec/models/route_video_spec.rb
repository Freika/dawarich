# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RouteVideo, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:status).with_values(stored: 0, expired: 1).with_prefix(:status) }
  end

  describe '#playable?' do
    it 'is true for a stored video with its file' do
      expect(create(:route_video, :with_file)).to be_playable
    end

    it 'is false when the file was purged but the row remains' do
      expect(create(:route_video, :expired)).not_to be_playable
    end

    it 'is false for a stored video whose blob never arrived' do
      expect(create(:route_video)).not_to be_playable
    end
  end

  describe '#expire!' do
    subject(:route_video) { create(:route_video, :with_file) }

    it 'drops the file but keeps the recipe so the video can be made again' do
      settings = route_video.settings

      perform_enqueued_jobs { route_video.expire! }

      expect(route_video.reload).to have_attributes(status: 'expired', settings: settings)
      expect(route_video.file).not_to be_attached
    end

    it 'stamps when the file went away' do
      freeze_time do
        route_video.expire!

        expect(route_video.expired_at).to eq(Time.current)
      end
    end

    it 'is safe to run twice' do
      route_video.expire!

      expect { route_video.expire! }.not_to raise_error
      expect(route_video.reload).to be_status_expired
    end
  end

  describe 'destruction' do
    it 'purges the attached file' do
      route_video = create(:route_video, :with_file)
      blob = route_video.file.blob

      perform_enqueued_jobs { route_video.destroy }

      expect(ActiveStorage::Blob.exists?(blob.id)).to be false
    end
  end

  describe '.newest_first' do
    it 'returns the most recent video first' do
      user = create(:user)
      older = create(:route_video, user: user, created_at: 2.days.ago)
      newer = create(:route_video, user: user, created_at: 1.hour.ago)

      expect(user.route_videos.newest_first).to eq([newer, older])
    end
  end

  describe '.expire_over_cap' do
    let(:user) { create(:user) }

    it 'keeps the newest up to the cap and expires the rest' do
      allow(DawarichSettings).to receive(:video_max_per_user).and_return(2)
      oldest = create(:route_video, :with_file, user: user, created_at: 3.days.ago)
      middle = create(:route_video, :with_file, user: user, created_at: 2.days.ago)
      newest = create(:route_video, :with_file, user: user, created_at: 1.day.ago)

      described_class.expire_over_cap(user.id)

      expect([newest.reload.status, middle.reload.status, oldest.reload.status])
        .to eq(%w[stored stored expired])
    end

    it 'leaves a user sitting exactly at the cap alone' do
      allow(DawarichSettings).to receive(:video_max_per_user).and_return(2)
      videos = create_list(:route_video, 2, :with_file, user: user)

      described_class.expire_over_cap(user.id)

      expect(videos.map { |video| video.reload.status }).to all(eq('stored'))
    end

    it 'leaves other users alone' do
      allow(DawarichSettings).to receive(:video_max_per_user).and_return(1)
      theirs = create(:route_video, :with_file, user: create(:user), created_at: 3.days.ago)
      create_list(:route_video, 2, :with_file, user: user)

      described_class.expire_over_cap(user.id)

      expect(theirs.reload).to be_status_stored
    end

    it 'does nothing when the cap is switched off' do
      allow(DawarichSettings).to receive(:video_max_per_user).and_return(0)
      videos = create_list(:route_video, 3, :with_file, user: user)

      described_class.expire_over_cap(user.id)

      expect(videos.map { |video| video.reload.status }).to all(eq('stored'))
    end
  end
end
