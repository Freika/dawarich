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
        params = { lonlat: 'POINT(0 0)', timestamp: Time.now.to_i }
        expect(validator.point_exists?(params, user.id)).to be false
      end

      it 'returns false for longitude outside valid range' do
        params = { lonlat: 'POINT(181 45)', timestamp: Time.now.to_i }
        expect(validator.point_exists?(params, user.id)).to be false

        params = { lonlat: 'POINT(-181 45)', timestamp: Time.now.to_i }
        expect(validator.point_exists?(params, user.id)).to be false
      end

      it 'returns false for latitude outside valid range' do
        params = { lonlat: 'POINT(45 91)', timestamp: Time.now.to_i }
        expect(validator.point_exists?(params, user.id)).to be false

        params = { lonlat: 'POINT(45 -91)', timestamp: Time.now.to_i }
        expect(validator.point_exists?(params, user.id)).to be false
      end
    end

    context 'with valid coordinates' do
      let(:longitude) { 10.0 }
      let(:latitude) { 50.0 }
      let(:timestamp) { Time.now.to_i }
      let(:params) { { lonlat: "POINT(#{longitude} #{latitude})", timestamp: timestamp } }

      context 'when point does not exist' do
        before do
          allow(Point).to receive(:where).and_return(double(exists?: false))
        end

        it 'returns false' do
          expect(validator.point_exists?(params, user.id)).to be false
        end

        it 'queries the database with correct parameters' do
          expect(Point).to receive(:where).with(
            lonlat: "POINT(#{longitude} #{latitude})",
            timestamp: timestamp,
            user_id: user.id
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
        params = { lonlat: 'POINT(10.5 50.5)', timestamp: '1650000000' }

        expect(Point).to receive(:where).with(
          lonlat: 'POINT(10.5 50.5)',
          timestamp: 1_650_000_000,
          user_id: user.id
        ).and_return(double(exists?: false))

        validator.point_exists?(params, user.id)
      end
    end

    context 'with different boundary values' do
      it 'accepts maximum valid coordinate values' do
        params = { lonlat: 'POINT(180 90)', timestamp: Time.now.to_i }

        expect(Point).to receive(:where).and_return(double(exists?: false))
        expect(validator.point_exists?(params, user.id)).to be false
      end

      it 'accepts minimum valid coordinate values' do
        params = { lonlat: 'POINT(-180 -90)', timestamp: Time.now.to_i }

        expect(Point).to receive(:where).and_return(double(exists?: false))
        expect(validator.point_exists?(params, user.id)).to be false
      end
    end

    context 'with point existing in device scope' do
      let(:existing_point) do
        create(:point, lonlat: 'POINT(10.5 50.5)', timestamp: Time.now.to_i, tracker_id: '123', user_id: user.id)
      end

      it 'returns true' do
        expect(validator.point_exists?(existing_point, user.id)).to be true
      end
    end
  end
end
