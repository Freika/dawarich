# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DemoData::TracksSeeder do
  let(:user)   { create(:user) }
  let(:anchor) { Time.zone.local(2026, 5, 28).beginning_of_day }

  def track_row(coords)
    {
      'starts_offset_seconds' => 0,
      'ends_offset_seconds' => 600,
      'mode' => 'walk',
      'avg_speed_kmh' => 5,
      'path_coordinates' => coords,
      'distance_meters' => 1000,
      'duration_seconds' => 600
    }
  end

  describe '#call' do
    it 'creates a track for a row with at least two coordinates' do
      described_class.new(user, anchor).call([track_row([[52.5, 13.4], [52.51, 13.41]])])

      expect(user.tracks.count).to eq(1)
    end

    it 'skips a row with a single coordinate instead of building an invalid geometry' do
      expect { described_class.new(user, anchor).call([track_row([[52.5, 13.4]])]) }
        .not_to change(Track, :count)
    end

    it 'skips a row with no coordinates' do
      expect { described_class.new(user, anchor).call([track_row([])]) }
        .not_to change(Track, :count)
    end
  end
end
