# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrackSerializer do
  describe '#call' do
    let(:user) { create(:user) }

    context 'when serializing user tracks without date range restrictions' do
      subject(:serializer) { described_class.new(user, 1.year.ago.to_i, 1.year.from_now.to_i).call }

      let!(:track1) { create(:track, user: user, start_at: 2.hours.ago, end_at: 1.hour.ago) }
      let!(:track2) { create(:track, user: user, start_at: 4.hours.ago, end_at: 3.hours.ago) }

      it 'returns an array of serialized tracks' do
        expect(serializer).to be_an(Array)
        expect(serializer.length).to eq(2)
      end

      it 'serializes each track correctly' do
        serialized_ids = serializer.map { |track| track[:id] }
        expect(serialized_ids).to contain_exactly(track1.id, track2.id)
      end

      it 'formats timestamps as ISO8601 for all tracks' do
        serializer.each do |track|
          expect(track[:start_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
          expect(track[:end_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        end
      end

      it 'includes all required fields for each track' do
        serializer.each do |track|
          expect(track.keys).to contain_exactly(
            :id, :start_at, :end_at, :distance, :avg_speed, :duration,
            :elevation_gain, :elevation_loss, :elevation_max, :elevation_min, :original_path
          )
        end
      end

      it 'handles numeric values correctly' do
        serializer.each do |track|
          expect(track[:distance]).to be_a(Numeric)
          expect(track[:avg_speed]).to be_a(Numeric)
          expect(track[:duration]).to be_a(Numeric)
          expect(track[:elevation_gain]).to be_a(Numeric)
          expect(track[:elevation_loss]).to be_a(Numeric)
          expect(track[:elevation_max]).to be_a(Numeric)
          expect(track[:elevation_min]).to be_a(Numeric)
        end
      end
    end

    context 'when serializing user tracks with date range' do
      subject(:serializer) { described_class.new(user, start_at.to_i, end_at.to_i).call }

      let(:start_at) { 6.hours.ago }
      let(:end_at) { 30.minutes.ago }
      let!(:track_in_range) { create(:track, user: user, start_at: 2.hours.ago, end_at: 1.hour.ago) }
      let!(:track_out_of_range) { create(:track, user: user, start_at: 10.hours.ago, end_at: 9.hours.ago) }

      it 'returns an array of serialized tracks' do
        expect(serializer).to be_an(Array)
        expect(serializer.length).to eq(1)
      end

      it 'only includes tracks within the date range' do
        serialized_ids = serializer.map { |track| track[:id] }
        expect(serialized_ids).to contain_exactly(track_in_range.id)
        expect(serialized_ids).not_to include(track_out_of_range.id)
      end

      it 'formats timestamps as ISO8601' do
        serializer.each do |track|
          expect(track[:start_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
          expect(track[:end_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        end
      end
    end

    context 'when user has no tracks' do
      subject(:serializer) { described_class.new(user, 1.day.ago.to_i, Time.current.to_i).call }

      it 'returns an empty array' do
        expect(serializer).to eq([])
      end
    end
  end
end
