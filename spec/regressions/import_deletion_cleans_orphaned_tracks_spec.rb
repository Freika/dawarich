# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Import deletion cleans up tracks left without points' do
  let(:user) { create(:user) }

  def point_on(import:, track:, offset:)
    create(:point, user: user, import: import, track: track,
                   timestamp: 1.hour.ago.to_i + offset)
  end

  it 'destroys a track whose only points belonged to the deleted import' do
    import = create(:import, user: user)
    track = create(:track, user: user)
    3.times { |i| point_on(import: import, track: track, offset: i * 60) }

    Imports::Destroy.new(user, import).call

    expect(Track.exists?(track.id)).to be(false)
  end

  it 'removes the orphaned track_segments along with the track' do
    import = create(:import, user: user)
    track = create(:track, user: user)
    create(:track_segment, track: track)
    point_on(import: import, track: track, offset: 0)

    Imports::Destroy.new(user, import).call

    expect(TrackSegment.where(track_id: track.id)).to be_empty
  end

  it 'keeps a track that still has points from another import' do
    deleted_import = create(:import, user: user)
    kept_import = create(:import, user: user)
    shared_track = create(:track, user: user)

    point_on(import: deleted_import, track: shared_track, offset: 0)
    point_on(import: kept_import, track: shared_track, offset: 60)

    Imports::Destroy.new(user, deleted_import).call

    expect(Track.exists?(shared_track.id)).to be(true)
    expect(shared_track.reload.points.count).to eq(1)
  end
end
