# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleMaps::SemanticHistoryParser do
  describe '#call' do
    subject(:parser) { described_class.new(import, user.id).call }

    let(:user) { create(:user) }
    let(:time) { Time.zone.now }

    context 'when activitySegment is present' do
      context 'when startLocation is blank' do
        let(:import) { create(:import, raw_data: { 'timelineObjects' => [activity_segment] }) }
        let(:activity_segment) do
          {
            'activitySegment' => {
              'waypointPath' => {
                'waypoints' => [
                  { 'latE7' => 123_456_789, 'lngE7' => 123_456_789 }
                ]
              },
              'duration' => { 'startTimestamp' => time.to_s }
            }
          }
        end

        it 'creates a point' do
          expect { parser }.to change(Point, :count).by(1)
        end

        context 'when waypointPath is blank' do
          let(:activity_segment) do
            {
              'activitySegment' => {
                'duration' => { 'startTimestamp' => time.to_s }
              }
            }
          end

          it 'does not create a point' do
            expect { parser }.not_to change(Point, :count)
          end
        end
      end

      context 'when startLocation is present' do
        let(:import) { create(:import, raw_data: { 'timelineObjects' => [activity_segment] }) }
        let(:activity_segment) do
          {
            'activitySegment' => {
              'startLocation' => { 'latitudeE7' => 123_456_789, 'longitudeE7' => 123_456_789 },
              'duration' => { 'startTimestamp' => time.to_s }
            }
          }
        end

        it 'creates a point' do
          expect { parser }.to change(Point, :count).by(1)
        end

        context 'with different timestamp formats' do
          context 'when timestamp is in ISO format' do
            let(:activity_segment) do
              {
                'activitySegment' => {
                  'startLocation' => { 'latitudeE7' => 123_456_789, 'longitudeE7' => 123_456_789 },
                  'duration' => { 'startTimestamp' => time.iso8601 }
                }
              }
            end

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
            end
          end

          context 'when timestamp is in seconds format' do
            let(:activity_segment) do
              {
                'activitySegment' => {
                  'startLocation' => { 'latitudeE7' => 123_456_789, 'longitudeE7' => 123_456_789 },
                  'duration' => { 'startTimestamp' => time.to_i.to_s }
                }
              }
            end

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
            end
          end

          context 'when timestamp is in milliseconds format' do
            let(:activity_segment) do
              {
                'activitySegment' => {
                  'startLocation' => { 'latitudeE7' => 123_456_789, 'longitudeE7' => 123_456_789 },
                  'duration' => { 'startTimestamp' => (time.to_f * 1000).to_i.to_s }
                }
              }
            end

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
            end
          end

          context 'when timestampMs is used' do
            let(:activity_segment) do
              {
                'activitySegment' => {
                  'startLocation' => { 'latitudeE7' => 123_456_789, 'longitudeE7' => 123_456_789 },
                  'duration' => { 'timestampMs' => (time.to_f * 1000).to_i.to_s }
                }
              }
            end

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
            end
          end
        end
      end
    end

    context 'when placeVisit is present' do
      context 'when location with coordinates is present' do
        let(:import) { create(:import, raw_data: { 'timelineObjects' => [place_visit] }) }
        let(:place_visit) do
          {
            'placeVisit' => {
              'location' => { 'latitudeE7' => 123_456_789, 'longitudeE7' => 123_456_789 },
              'duration' => { 'startTimestamp' => time.to_s }
            }
          }
        end

        it 'creates a point' do
          expect { parser }.to change(Point, :count).by(1)
        end

        context 'with different timestamp formats' do
          context 'when timestamp is in ISO format' do
            let(:place_visit) do
              {
                'placeVisit' => {
                  'location' => { 'latitudeE7' => 123_456_789, 'longitudeE7' => 123_456_789 },
                  'duration' => { 'startTimestamp' => time.iso8601 }
                }
              }
            end

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
            end
          end

          context 'when timestamp is in seconds format' do
            let(:place_visit) do
              {
                'placeVisit' => {
                  'location' => { 'latitudeE7' => 123_456_789, 'longitudeE7' => 123_456_789 },
                  'duration' => { 'startTimestamp' => time.to_i.to_s }
                }
              }
            end

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
            end
          end

          context 'when timestamp is in milliseconds format' do
            let(:place_visit) do
              {
                'placeVisit' => {
                  'location' => { 'latitudeE7' => 123_456_789, 'longitudeE7' => 123_456_789 },
                  'duration' => { 'startTimestamp' => (time.to_f * 1000).to_i.to_s }
                }
              }
            end

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
            end
          end

          context 'when timestampMs is used' do
            let(:place_visit) do
              {
                'placeVisit' => {
                  'location' => { 'latitudeE7' => 123_456_789, 'longitudeE7' => 123_456_789 },
                  'duration' => { 'timestampMs' => (time.to_f * 1000).to_i.to_s }
                }
              }
            end

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
            end
          end
        end
      end

      context 'when location with coordinates is blank' do
        let(:import) { create(:import, raw_data: { 'timelineObjects' => [place_visit] }) }
        let(:place_visit) do
          {
            'placeVisit' => {
              'location' => {},
              'duration' => { 'startTimestamp' => time.to_s }
            }
          }
        end

        it 'does not create a point' do
          expect { parser }.not_to change(Point, :count)
        end

        context 'when otherCandidateLocations is present' do
          let(:place_visit) do
            {
              'placeVisit' => {
                'otherCandidateLocations' => [{ 'latitudeE7' => 123_456_789, 'longitudeE7' => 123_456_789 }],
                'duration' => { 'startTimestamp' => time.to_s }
              }
            }
          end

          it 'creates a point' do
            expect { parser }.to change(Point, :count).by(1)
          end
        end
      end
    end
  end
end
