require 'rails_helper'

RSpec.describe Track, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:points).dependent(:nullify) }
  end

  describe 'validations' do
    subject { build(:track) }

    it { is_expected.to validate_presence_of(:start_at) }
    it { is_expected.to validate_presence_of(:end_at) }
    it { is_expected.to validate_presence_of(:original_path) }
    it { is_expected.to validate_numericality_of(:distance).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:avg_speed).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:duration).is_greater_than_or_equal_to(0) }
  end

  describe '.last_for_day' do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }
    let(:target_day) { Date.current }

    context 'when user has tracks on the target day' do
      let!(:early_track) do
        create(:track, user: user,
               start_at: target_day.beginning_of_day + 1.hour,
               end_at: target_day.beginning_of_day + 2.hours)
      end

      let!(:late_track) do
        create(:track, user: user,
               start_at: target_day.beginning_of_day + 3.hours,
               end_at: target_day.beginning_of_day + 4.hours)
      end

      let!(:other_user_track) do
        create(:track, user: other_user,
               start_at: target_day.beginning_of_day + 5.hours,
               end_at: target_day.beginning_of_day + 6.hours)
      end

      it 'returns the track that ends latest on that day for the user' do
        result = Track.last_for_day(user, target_day)
        expect(result).to eq(late_track)
      end

      it 'does not return tracks from other users' do
        result = Track.last_for_day(user, target_day)
        expect(result).not_to eq(other_user_track)
      end
    end

    context 'when user has tracks on different days' do
      let!(:yesterday_track) do
        create(:track, user: user,
               start_at: target_day.yesterday.beginning_of_day + 1.hour,
               end_at: target_day.yesterday.beginning_of_day + 2.hours)
      end

      let!(:tomorrow_track) do
        create(:track, user: user,
               start_at: target_day.tomorrow.beginning_of_day + 1.hour,
               end_at: target_day.tomorrow.beginning_of_day + 2.hours)
      end

      let!(:target_day_track) do
        create(:track, user: user,
               start_at: target_day.beginning_of_day + 1.hour,
               end_at: target_day.beginning_of_day + 2.hours)
      end

      it 'returns only the track from the target day' do
        result = Track.last_for_day(user, target_day)
        expect(result).to eq(target_day_track)
      end
    end

    context 'when user has no tracks on the target day' do
      let!(:yesterday_track) do
        create(:track, user: user,
               start_at: target_day.yesterday.beginning_of_day + 1.hour,
               end_at: target_day.yesterday.beginning_of_day + 2.hours)
      end

      it 'returns nil' do
        result = Track.last_for_day(user, target_day)
        expect(result).to be_nil
      end
    end

    context 'when passing a Time object instead of Date' do
      let!(:track) do
        create(:track, user: user,
               start_at: target_day.beginning_of_day + 1.hour,
               end_at: target_day.beginning_of_day + 2.hours)
      end

      it 'correctly handles Time objects' do
        result = Track.last_for_day(user, target_day.to_time)
        expect(result).to eq(track)
      end
    end

    context 'when track spans midnight' do
      let!(:spanning_track) do
        create(:track, user: user,
               start_at: target_day.beginning_of_day - 1.hour,
               end_at: target_day.beginning_of_day + 1.hour)
      end

      it 'includes tracks that end on the target day' do
        result = Track.last_for_day(user, target_day)
        expect(result).to eq(spanning_track)
      end
    end
  end

  describe 'Calculateable concern' do
    let(:user) { create(:user) }
    let(:track) { create(:track, user: user, distance: 1000, avg_speed: 25, duration: 3600) }
    let!(:points) do
      [
        create(:point, user: user, track: track, lonlat: 'POINT(13.404954 52.520008)', timestamp: 1.hour.ago.to_i),
        create(:point, user: user, track: track, lonlat: 'POINT(13.405954 52.521008)', timestamp: 30.minutes.ago.to_i),
        create(:point, user: user, track: track, lonlat: 'POINT(13.406954 52.522008)', timestamp: Time.current.to_i)
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
        expect(track.distance).to be_a(Numeric)
      end

      it 'stores distance in user preferred unit for Track model' do
        allow(user).to receive(:safe_settings).and_return(double(distance_unit: 'km'))
        allow(Point).to receive(:total_distance).and_return(1.5) # 1.5 km

        track.calculate_distance

        expect(track.distance).to eq(1.5) # Should be 1.5 km with 2 decimal places precision
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
