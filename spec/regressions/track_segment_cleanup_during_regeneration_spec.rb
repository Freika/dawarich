# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Track segment cleanup during track regeneration' do
  let(:user) { create(:user) }
  let!(:track) { create(:track, user:) }
  let!(:points) { create_list(:point, 2, user:, track:) }
  let!(:segment) { create(:track_segment, track:) }
  let(:generator) { Tracks::ParallelGenerator.new(user, mode: :bulk) }

  it 'relies on the parent-first database cascade for segment cleanup' do
    expect(Track.reflect_on_association(:track_segments).options[:dependent]).to be_nil
  end

  it 'removes segments created while their track is being destroyed' do
    target_id = track.id
    callback = lambda do
      next unless id == target_id

      FactoryBot.create(:track_segment, track: self)
    end
    Track.set_callback(:destroy, :before, callback)

    expect { generator.send(:clean_existing_tracks) }.not_to raise_error
    expect(Track.exists?(track.id)).to be false
    expect(TrackSegment.where(track_id: track.id)).to be_empty
  ensure
    Track.skip_callback(:destroy, :before, callback) if callback
  end
end
