# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::DestroyOrphanedTracksJob do
  describe '#perform' do
    let(:user) { create(:user) }

    it 'destroys tracks that have no points' do
      orphan = create(:track, user: user)

      expect { described_class.new.perform }
        .to change { Track.exists?(orphan.id) }.from(true).to(false)
    end

    it 'removes track_segments belonging to orphaned tracks' do
      orphan = create(:track, user: user)
      create(:track_segment, track: orphan)

      described_class.new.perform

      expect(TrackSegment.where(track_id: orphan.id)).to be_empty
    end

    it 'keeps tracks that still have points' do
      track = create(:track, user: user)
      create(:point, user: user, track: track)

      expect { described_class.new.perform }
        .not_to(change { Track.exists?(track.id) })
    end

    it 'broadcasts a destroyed event for each removed track' do
      orphan = create(:track, user: user)

      expect { described_class.new.perform }
        .to(have_broadcasted_to(user).from_channel(TracksChannel)
        .with { |data| expect(data).to include('action' => 'destroyed', 'track_id' => orphan.id) })
    end
  end
end
