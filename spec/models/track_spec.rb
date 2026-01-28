require 'rails_helper'

RSpec.describe Track, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:points).dependent(:nullify) }
    it { is_expected.to have_many(:track_segments).dependent(:destroy) }
  end

  describe 'enums' do
    it do
      is_expected.to define_enum_for(:dominant_mode)
        .with_values(
          unknown: 0,
          stationary: 1,
          walking: 2,
          running: 3,
          cycling: 4,
          driving: 5,
          bus: 6,
          train: 7,
          flying: 8,
          boat: 9,
          motorcycle: 10
        )
        .with_prefix(true)
    end
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

  describe 'scopes' do
    let(:user) { create(:user) }

    describe '.by_mode' do
      let!(:walking_track) { create(:track, user: user, dominant_mode: :walking) }
      let!(:driving_track) { create(:track, user: user, dominant_mode: :driving) }

      it 'returns tracks with the specified mode' do
        expect(Track.by_mode(:walking)).to include(walking_track)
        expect(Track.by_mode(:walking)).not_to include(driving_track)
      end
    end

    describe '.with_unknown_mode' do
      let!(:unknown_track) { create(:track, user: user, dominant_mode: :unknown) }
      let!(:walking_track) { create(:track, user: user, dominant_mode: :walking) }

      it 'returns only tracks with unknown mode' do
        expect(Track.with_unknown_mode).to include(unknown_track)
        expect(Track.with_unknown_mode).not_to include(walking_track)
      end
    end

    describe '.with_detected_mode' do
      let!(:unknown_track) { create(:track, user: user, dominant_mode: :unknown) }
      let!(:walking_track) { create(:track, user: user, dominant_mode: :walking) }

      it 'returns only tracks with detected mode' do
        expect(Track.with_detected_mode).to include(walking_track)
        expect(Track.with_detected_mode).not_to include(unknown_track)
      end
    end
  end

  describe '#activity_breakdown' do
    let(:user) { create(:user) }
    let(:track) { create(:track, user: user) }

    context 'when track has no segments' do
      it 'returns empty hash' do
        expect(track.activity_breakdown).to eq({})
      end
    end

    context 'when track has segments' do
      before do
        create(:track_segment, track: track, transportation_mode: :walking, duration: 600)
        create(:track_segment, track: track, transportation_mode: :driving, duration: 1200)
        create(:track_segment, track: track, transportation_mode: :walking, duration: 300)
      end

      it 'returns duration grouped by mode' do
        breakdown = track.activity_breakdown
        expect(breakdown['walking']).to eq(900)
        expect(breakdown['driving']).to eq(1200)
      end
    end
  end

  describe '#update_dominant_mode!' do
    let(:user) { create(:user) }
    let(:track) { create(:track, user: user, dominant_mode: :unknown) }

    context 'when track has no segments' do
      it 'sets dominant_mode to unknown' do
        track.update_dominant_mode!
        expect(track.reload.dominant_mode).to eq('unknown')
      end
    end

    context 'when track has segments' do
      before do
        create(:track_segment, track: track, transportation_mode: :walking, duration: 600)
        create(:track_segment, track: track, transportation_mode: :driving, duration: 1200)
      end

      it 'sets dominant_mode to the mode with longest duration' do
        track.update_dominant_mode!
        expect(track.reload.dominant_mode).to eq('driving')
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

      it 'stores distance in meters consistently' do
        allow(Point).to receive(:total_distance).and_return(1500) # 1500 meters

        track.calculate_distance

        expect(track.distance).to eq(1500) # Should be stored as meters regardless of user unit preference
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
