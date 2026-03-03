# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::CalculateCountriesJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }
    let(:trip) { create(:trip, user: user) }
    let(:distance_unit) { 'km' }
    let(:points) do
      [
        create(:point, user: user, country_name: 'Germany', timestamp: trip.started_at.to_i + 1.hour),
        create(:point, user: user, country_name: 'France', timestamp: trip.started_at.to_i + 2.hours),
        create(:point, user: user, country_name: 'Germany', timestamp: trip.started_at.to_i + 3.hours),
        create(:point, user: user, country_name: 'Italy', timestamp: trip.started_at.to_i + 4.hours)
      ]
    end

    before do
      points # Create the points
    end

    it 'finds the trip and calculates countries' do
      expect(Trip).to receive(:find).with(trip.id).and_return(trip)
      expect(trip).to receive(:calculate_countries)
      expect(trip).to receive(:save!)

      described_class.perform_now(trip.id, distance_unit)
    end

    it 'calculates unique countries from trip points' do
      described_class.perform_now(trip.id, distance_unit)

      trip.reload
      expect(trip.visited_countries).to contain_exactly('Germany', 'France', 'Italy')
    end

    it 'broadcasts the update with correct parameters' do
      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
        "trip_#{trip.id}",
        target: 'trip_countries',
        partial: 'trips/countries',
        locals: { trip: trip, distance_unit: distance_unit }
      )

      described_class.perform_now(trip.id, distance_unit)
    end

    context 'when trip has no points' do
      let(:trip_without_points) { create(:trip, user: user) }

      it 'sets visited_countries to empty array' do
        trip_without_points.points.destroy_all
        described_class.perform_now(trip_without_points.id, distance_unit)

        trip_without_points.reload

        expect(trip_without_points.visited_countries).to eq([])
      end
    end

    context 'when points have nil country names' do
      let(:points_with_nil_countries) do
        [
          create(:point, user: user, country_name: 'Germany', timestamp: trip.started_at.to_i + 1.hour),
          create(:point, user: user, country_name: nil, timestamp: trip.started_at.to_i + 2.hours),
          create(:point, user: user, country_name: 'France', timestamp: trip.started_at.to_i + 3.hours)
        ]
      end

      before do
        # Remove existing points and create new ones with nil countries
        Point.where(user: user).destroy_all
        points_with_nil_countries
      end

      it 'filters out nil country names' do
        described_class.perform_now(trip.id, distance_unit)

        trip.reload
        expect(trip.visited_countries).to contain_exactly('Germany', 'France')
      end
    end

    context 'when trip is not found' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect do
          described_class.perform_now(999_999, distance_unit)
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when distance_unit is different' do
      let(:distance_unit) { 'mi' }

      it 'passes the correct distance_unit to broadcast' do
        expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
          "trip_#{trip.id}",
          target: 'trip_countries',
          partial: 'trips/countries',
          locals: { trip: trip, distance_unit: 'mi' }
        )

        described_class.perform_now(trip.id, distance_unit)
      end
    end

    describe 'queue configuration' do
      it 'uses the trips queue' do
        expect(described_class.queue_name).to eq('trips')
      end
    end
  end
end
