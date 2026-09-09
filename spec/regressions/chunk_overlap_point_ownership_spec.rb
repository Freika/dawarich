# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chunk overlap point ownership' do
  let(:user) { create(:user, settings: { 'minutes_between_routes' => 60 }) }
  let(:day_start) { Time.utc(2026, 1, 14) }
  let(:session) { Tracks::SessionManager.new(user.id) }
  let(:hours) { 22..34 }
  let!(:points) do
    hours.map do |hour|
      create(:point, user: user, timestamp: (day_start + hour.hours).to_i,
                     latitude: 40.0 + hour * 0.01, longitude: 0, altitude: 100)
    end
  end

  before do
    session.create_session
    session.mark_started(2)
  end

  after { session.cleanup_session }

  def chunk(index)
    start_at = day_start + index.days
    end_at = start_at + 1.day
    {
      chunk_id: index,
      start_timestamp: start_at.to_i,
      end_timestamp: end_at.to_i,
      buffer_start_timestamp: (start_at - 6.hours).to_i,
      buffer_end_timestamp: (end_at + 6.hours).to_i,
      untracked_only: false
    }
  end

  [[0, 1], [1, 0]].each do |order|
    it "keeps ownership and metadata consistent with chunk order #{order}" do
      Tracks::TimeChunkProcessorJob.new.perform(user.id, session.session_id, chunk(order.first))
      first_track = user.tracks.sole
      owned_ids = first_track.points.pluck(:id)
      expect(owned_ids.size).to be >= 2

      Tracks::TimeChunkProcessorJob.new.perform(user.id, session.session_id, chunk(order.last))

      expect(first_track.reload.points.pluck(:id)).to match_array(owned_ids)
      expect(user.tracks.reload.all? { |track| track.points.count >= 2 }).to be(true)

      Tracks::BoundaryResolverJob.new.perform(user.id, session.session_id)

      expect(session.get_session_data['status']).to eq('completed')
      expect(user.tracks.reload.all? { |track| track.points.count >= 2 }).to be(true)
      expect(user.points.where(track_id: nil)).not_to exist
      user.tracks.each do |track|
        timestamps = track.points.order(:timestamp).pluck(:timestamp)
        expect(track.start_at.to_i).to eq(timestamps.first)
        expect(track.end_at.to_i).to eq(timestamps.last)
      end
    end
  end
  [22..31, 17..26].each do |range|
    context "when a single endpoint remains in hours #{range}" do
      let(:hours) { range }

      [[0, 1], [1, 0]].each do |order|
        it "includes the terminal point with chunk order #{order}" do
          order.each do |index|
            Tracks::TimeChunkProcessorJob.new.perform(user.id, session.session_id, chunk(index))
          end
          Tracks::BoundaryResolverJob.new.perform(user.id, session.session_id)

          expect(user.points.where(track_id: nil)).not_to exist
          expect(user.tracks.sum { |track| track.points.count }).to eq(points.size)
          expect(user.tracks.maximum(:end_at).to_i).to eq(points.last.timestamp)
        end
      end
    end
  end
end
