# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PointValidation do
  # Create a test class that includes the concern
  let(:test_class) do
    Class.new do
      include PointValidation
    end
  end

  let(:validator) { test_class.new }
  let(:user) { create(:user) }

  describe '#point_exists?' do
    context 'with invalid coordinates' do
      it 'returns false for zero coordinates' do
        params = { longitude: '0', latitude: '0', timestamp: Time.now.to_i }
        expect(validator.point_exists?(params, user.id)).to be false
      end

      it 'returns false for longitude outside valid range' do
        params = { longitude: '181', latitude: '45', timestamp: Time.now.to_i }
        expect(validator.point_exists?(params, user.id)).to be false

        params = { longitude: '-181', latitude: '45', timestamp: Time.now.to_i }
        expect(validator.point_exists?(params, user.id)).to be false
      end

      it 'returns false for latitude outside valid range' do
        params = { longitude: '45', latitude: '91', timestamp: Time.now.to_i }
        expect(validator.point_exists?(params, user.id)).to be false

        params = { longitude: '45', latitude: '-91', timestamp: Time.now.to_i }
        expect(validator.point_exists?(params, user.id)).to be false
      end
    end

    context 'with valid coordinates' do
      let(:longitude) { 10.0 }
      let(:latitude) { 50.0 }
      let(:timestamp) { Time.now.to_i }
      let(:params) { { longitude: longitude.to_s, latitude: latitude.to_s, timestamp: timestamp } }

      context 'when point does not exist' do
        before do
          allow(Point).to receive(:where).and_return(double(exists?: false))
        end

        it 'returns false' do
          expect(validator.point_exists?(params, user.id)).to be false
        end

        it 'queries the database with correct parameters' do
          expect(Point).to receive(:where).with(
            'ST_SetSRID(ST_MakePoint(?, ?), 4326) = lonlat AND timestamp = ? AND user_id = ?',
            longitude, latitude, timestamp, user.id
          ).and_return(double(exists?: false))

          validator.point_exists?(params, user.id)
        end
      end

      context 'when point exists' do
        before do
          allow(Point).to receive(:where).and_return(double(exists?: true))
        end

        it 'returns true' do
          expect(validator.point_exists?(params, user.id)).to be true
        end
      end
    end

    context 'with string parameters' do
      it 'converts string coordinates to float values' do
        params = { longitude: '10.5', latitude: '50.5', timestamp: '1650000000' }

        expect(Point).to receive(:where).with(
          'ST_SetSRID(ST_MakePoint(?, ?), 4326) = lonlat AND timestamp = ? AND user_id = ?',
          10.5, 50.5, 1_650_000_000, user.id
        ).and_return(double(exists?: false))

        validator.point_exists?(params, user.id)
      end
    end

    context 'with different boundary values' do
      it 'accepts maximum valid coordinate values' do
        params = { longitude: '180', latitude: '90', timestamp: Time.now.to_i }

        expect(Point).to receive(:where).and_return(double(exists?: false))
        expect(validator.point_exists?(params, user.id)).to be false
      end

      it 'accepts minimum valid coordinate values' do
        params = { longitude: '-180', latitude: '-90', timestamp: Time.now.to_i }

        expect(Point).to receive(:where).and_return(double(exists?: false))
        expect(validator.point_exists?(params, user.id)).to be false
      end
    end

    context 'with integration tests', :db do
      # These tests require a database with PostGIS support
      # Only run them if using real database integration

      let(:existing_timestamp) { 1_650_000_000 }
      let(:existing_point_params) do
        {
          longitude: 10.5,
          latitude: 50.5,
          timestamp: existing_timestamp,
          user_id: user.id
        }
      end

      before do
        # Skip this context if not in integration mode
        skip 'Skipping integration tests' unless ENV['RUN_INTEGRATION_TESTS']

        # Create a point in the database
        existing_point = Point.create!(
          lonlat: "POINT(#{existing_point_params[:longitude]} #{existing_point_params[:latitude]})",
          timestamp: existing_timestamp,
          user_id: user.id
        )
      end

      it 'returns true when a point with same coordinates and timestamp exists' do
        params = {
          longitude: existing_point_params[:longitude].to_s,
          latitude: existing_point_params[:latitude].to_s,
          timestamp: existing_timestamp
        }

        expect(validator.point_exists?(params, user.id)).to be true
      end

      it 'returns false when a point with different coordinates exists' do
        params = {
          longitude: (existing_point_params[:longitude] + 0.1).to_s,
          latitude: existing_point_params[:latitude].to_s,
          timestamp: existing_timestamp
        }

        expect(validator.point_exists?(params, user.id)).to be false
      end

      it 'returns false when a point with different timestamp exists' do
        params = {
          longitude: existing_point_params[:longitude].to_s,
          latitude: existing_point_params[:latitude].to_s,
          timestamp: existing_timestamp + 1
        }

        expect(validator.point_exists?(params, user.id)).to be false
      end
    end
  end
end
