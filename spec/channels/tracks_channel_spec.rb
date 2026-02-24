# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TracksChannel, type: :channel do
  let(:user) { create(:user) }

  describe '#subscribed' do
    it 'successfully subscribes to the channel' do
      stub_connection current_user: user

      subscribe

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_for(user)
    end
  end

  describe 'track broadcasting' do
    let!(:track) { create(:track, user: user) }

    before do
      stub_connection current_user: user
      subscribe
    end

    it 'broadcasts track creation' do
      expect do
        TracksChannel.broadcast_to(user, {
                                     action: 'created',
          track: {
            id: track.id,
            start_at: track.start_at.iso8601,
            end_at: track.end_at.iso8601,
            distance: track.distance,
            avg_speed: track.avg_speed,
            duration: track.duration,
            elevation_gain: track.elevation_gain,
            elevation_loss: track.elevation_loss,
            elevation_max: track.elevation_max,
            elevation_min: track.elevation_min,
            original_path: track.original_path.to_s
          }
                                   })
      end.to have_broadcasted_to(user)
    end

    it 'broadcasts track updates' do
      expect do
        TracksChannel.broadcast_to(user, {
                                     action: 'updated',
          track: {
            id: track.id,
            start_at: track.start_at.iso8601,
            end_at: track.end_at.iso8601,
            distance: track.distance,
            avg_speed: track.avg_speed,
            duration: track.duration,
            elevation_gain: track.elevation_gain,
            elevation_loss: track.elevation_loss,
            elevation_max: track.elevation_max,
            elevation_min: track.elevation_min,
            original_path: track.original_path.to_s
          }
                                   })
      end.to have_broadcasted_to(user)
    end

    it 'broadcasts track destruction' do
      expect do
        TracksChannel.broadcast_to(user, {
                                     action: 'destroyed',
          track_id: track.id
                                   })
      end.to have_broadcasted_to(user)
    end
  end
end
