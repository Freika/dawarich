require 'rails_helper'

RSpec.describe Track, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:points).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:start_at) }
    it { is_expected.to validate_presence_of(:end_at) }
    it { is_expected.to validate_presence_of(:original_path) }
    it { is_expected.to validate_numericality_of(:distance).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:avg_speed).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:duration).is_greater_than(0) }
  end

  describe 'Calculateable concern' do
    let(:user) { create(:user) }
    let(:track) { create(:track, user: user, distance: 1000, avg_speed: 25, duration: 3600) }
    let!(:points) do
      [
        create(:point, user: user, track: track, lonlat: 'POINT(13.404954 52.520008)', timestamp: 1.hour.ago.to_i),
        create(:point, user: user, track: track, lonlat: 'POINT(13.404955 52.520009)', timestamp: 30.minutes.ago.to_i),
        create(:point, user: user, track: track, lonlat: 'POINT(13.404956 52.520010)', timestamp: Time.current.to_i)
      ]
    end

    describe '#calculate_path' do
      it 'updates the original_path with calculated path' do
        original_path_before = track.original_path
        track.calculate_path

        expect(track.original_path).not_to eq(original_path_before)
        expect(track.original_path).to be_present
      end
    end

    describe '#calculate_distance' do
      it 'updates the distance based on points' do
        track.calculate_distance

        expect(track.distance).to be > 0
        expect(track.distance).to be_a(Float)
      end

      it 'stores distance in meters for Track model' do
        allow(user).to receive(:safe_settings).and_return(double(distance_unit: 'km'))
        allow(Point).to receive(:total_distance).and_return(1.5) # 1.5 km

        track.calculate_distance

        expect(track.distance).to eq(1500.0) # Should be in meters
      end
    end

        describe '#recalculate_distance!' do
      it 'recalculates and saves the distance' do
        original_distance = track.distance

        track.recalculate_distance!

        track.reload
        expect(track.distance).not_to eq(original_distance)
      end
    end

    describe '#recalculate_path!' do
      it 'recalculates and saves the path' do
        original_path = track.original_path

        track.recalculate_path!

        track.reload
        expect(track.original_path).not_to eq(original_path)
      end
    end

    describe '#recalculate_path_and_distance!' do
      it 'recalculates both path and distance and saves' do
        original_distance = track.distance
        original_path = track.original_path

        track.recalculate_path_and_distance!

        track.reload
        expect(track.distance).not_to eq(original_distance)
        expect(track.original_path).not_to eq(original_path)
      end
    end
  end
end
