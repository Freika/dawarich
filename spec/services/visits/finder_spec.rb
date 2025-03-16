# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Finder do
  let(:user) { create(:user) }

  describe '#call' do
    context 'when area selection parameters are provided' do
      let(:area_params) do
        {
          selection: 'true',
          sw_lat: '48.8534',
          sw_lng: '2.3380',
          ne_lat: '48.8667',
          ne_lng: '2.3580'
        }
      end

      it 'delegates to FindWithinBoundingBox service' do
        bounding_box_finder = instance_double(Visits::FindWithinBoundingBox)
        expect(Visits::FindWithinBoundingBox).to receive(:new)
          .with(user, area_params)
          .and_return(bounding_box_finder)

        expect(bounding_box_finder).to receive(:call)

        described_class.new(user, area_params).call
      end

      it 'does not call FindInTime service' do
        expect(Visits::FindWithinBoundingBox).to receive(:new).and_call_original
        expect(Visits::FindInTime).not_to receive(:new)

        described_class.new(user, area_params).call
      end
    end

    context 'when time-based parameters are provided' do
      let(:time_params) do
        {
          start_at: Time.zone.now.beginning_of_day.iso8601,
          end_at: Time.zone.now.end_of_day.iso8601
        }
      end

      it 'delegates to FindInTime service' do
        time_finder = instance_double(Visits::FindInTime)
        expect(Visits::FindInTime).to receive(:new)
          .with(user, time_params)
          .and_return(time_finder)

        expect(time_finder).to receive(:call)

        described_class.new(user, time_params).call
      end

      it 'does not call FindWithinBoundingBox service' do
        expect(Visits::FindInTime).to receive(:new).and_call_original
        expect(Visits::FindWithinBoundingBox).not_to receive(:new)

        described_class.new(user, time_params).call
      end
    end

    context 'when selection is true but coordinates are missing' do
      let(:incomplete_params) do
        {
          selection: 'true',
          sw_lat: '48.8534'
          # Missing other coordinates
        }
      end

      it 'falls back to FindInTime service' do
        time_finder = instance_double(Visits::FindInTime)
        expect(Visits::FindInTime).to receive(:new)
          .with(user, incomplete_params)
          .and_return(time_finder)

        expect(time_finder).to receive(:call)

        described_class.new(user, incomplete_params).call
      end
    end

    context 'when both area and time parameters are provided' do
      let(:combined_params) do
        {
          selection: 'true',
          sw_lat: '48.8534',
          sw_lng: '2.3380',
          ne_lat: '48.8667',
          ne_lng: '2.3580',
          start_at: Time.zone.now.beginning_of_day.iso8601,
          end_at: Time.zone.now.end_of_day.iso8601
        }
      end

      it 'prioritizes area search over time search' do
        bounding_box_finder = instance_double(Visits::FindWithinBoundingBox)
        expect(Visits::FindWithinBoundingBox).to receive(:new)
          .with(user, combined_params)
          .and_return(bounding_box_finder)

        expect(bounding_box_finder).to receive(:call)
        expect(Visits::FindInTime).not_to receive(:new)

        described_class.new(user, combined_params).call
      end
    end

    context 'when selection is not "true"' do
      let(:params) do
        {
          selection: 'false', # explicitly not true
          sw_lat: '48.8534',
          sw_lng: '2.3380',
          ne_lat: '48.8667',
          ne_lng: '2.3580',
          start_at: Time.zone.now.beginning_of_day.iso8601,
          end_at: Time.zone.now.end_of_day.iso8601
        }
      end

      it 'uses FindInTime service' do
        expect(Visits::FindInTime).to receive(:new).and_call_original
        expect(Visits::FindWithinBoundingBox).not_to receive(:new)

        described_class.new(user, params).call
      end
    end

    context 'edge cases' do
      context 'with empty params' do
        let(:empty_params) { {} }

        it 'uses FindInTime service' do
          # We need to handle the ArgumentError from FindInTime when params are empty
          expect(Visits::FindInTime).to receive(:new).and_raise(ArgumentError)
          expect(Visits::FindWithinBoundingBox).not_to receive(:new)

          expect { described_class.new(user, empty_params).call }.to raise_error(ArgumentError)
        end
      end

      context 'with nil params' do
        let(:nil_params) { nil }

        it 'raises an error' do
          expect { described_class.new(user, nil_params).call }.to raise_error(NoMethodError)
        end
      end
    end
  end
end
