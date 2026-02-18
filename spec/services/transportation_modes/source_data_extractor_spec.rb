# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::SourceDataExtractor do
  let(:user) { create(:user) }

  describe '#call' do
    context 'when points have no activity data' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000, raw_data: {}),
          build(:point, user: user, timestamp: 1060, raw_data: {})
        ]
      end

      it 'returns empty array' do
        extractor = described_class.new(points)
        expect(extractor.call).to eq([])
      end
    end

    context 'with Overland motion data' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000, raw_data: {
                  'properties' => { 'motion' => ['driving'] }
                }),
          build(:point, user: user, timestamp: 1060, raw_data: {
                  'properties' => { 'motion' => ['driving'] }
                }),
          build(:point, user: user, timestamp: 1120, raw_data: {
                  'properties' => { 'motion' => ['walking'] }
                })
        ]
      end

      it 'extracts segments based on motion changes' do
        extractor = described_class.new(points)
        segments = extractor.call

        expect(segments.length).to eq(2)
        expect(segments[0][:mode]).to eq(:driving)
        expect(segments[0][:source]).to eq('overland')
        expect(segments[1][:mode]).to eq(:walking)
      end
    end

    context 'with Overland activity data' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000, raw_data: {
                  'properties' => { 'activity' => 'automotive_navigation' }
                }),
          build(:point, user: user, timestamp: 1060, raw_data: {
                  'properties' => { 'activity' => 'automotive_navigation' }
                })
        ]
      end

      it 'maps activity to transportation mode' do
        extractor = described_class.new(points)
        segments = extractor.call

        expect(segments.length).to eq(1)
        expect(segments[0][:mode]).to eq(:driving)
      end
    end

    context 'with Google activity data' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000, raw_data: {
                  'activityRecord' => {
                    'probableActivities' => [
                      { 'activityType' => 'WALKING', 'probability' => 0.8 },
                      { 'activityType' => 'STILL', 'probability' => 0.2 }
                    ]
                  }
                }),
          build(:point, user: user, timestamp: 1060, raw_data: {
                  'activityRecord' => {
                    'probableActivities' => [
                      { 'activityType' => 'IN_VEHICLE', 'probability' => 0.9 }
                    ]
                  }
                })
        ]
      end

      it 'extracts the most probable activity' do
        extractor = described_class.new(points)
        segments = extractor.call

        expect(segments.length).to eq(2)
        expect(segments[0][:mode]).to eq(:walking)
        expect(segments[0][:source]).to eq('google')
        expect(segments[1][:mode]).to eq(:driving)
      end
    end

    context 'with Google semantic history format' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000, raw_data: {
                  'activities' => [
                    { 'activityType' => 'IN_RAIL_VEHICLE', 'probability' => 0.9 }
                  ]
                })
        ]
      end

      it 'maps rail vehicle to train' do
        extractor = described_class.new(points)
        segments = extractor.call

        expect(segments.length).to eq(1)
        expect(segments[0][:mode]).to eq(:train)
      end
    end

    context 'with mixed data sources' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000, raw_data: {
                  'properties' => { 'motion' => ['cycling'] }
                }),
          build(:point, user: user, timestamp: 1060, raw_data: {}),
          build(:point, user: user, timestamp: 1120, raw_data: {
                  'activityRecord' => {
                    'probableActivities' => [{ 'activityType' => 'WALKING', 'probability' => 0.9 }]
                  }
                })
        ]
      end

      it 'handles transitions between sources' do
        extractor = described_class.new(points)
        segments = extractor.call

        modes = segments.map { |s| s[:mode] }
        expect(modes).to include(:cycling)
        expect(modes).to include(:walking)
      end
    end

    context 'with confidence levels' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000, raw_data: {
                  'properties' => { 'motion' => ['driving'] }
                })
        ]
      end

      it 'sets high confidence for source data' do
        extractor = described_class.new(points)
        segments = extractor.call

        expect(segments[0][:confidence]).to eq(:high)
      end
    end

    context 'with Overland visit action' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000, raw_data: {
                  'properties' => { 'motion' => ['driving'] }
                }),
          build(:point, user: user, timestamp: 1060, raw_data: {
                  'properties' => { 'action' => 'visit' }
                }),
          build(:point, user: user, timestamp: 1120, raw_data: {
                  'properties' => { 'motion' => ['driving'] }
                })
        ]
      end

      it 'treats visit action as stationary mode' do
        extractor = described_class.new(points)
        segments = extractor.call

        modes = segments.map { |s| s[:mode] }
        expect(modes).to include(:stationary)
      end

      it 'detects source as overland for visit points' do
        extractor = described_class.new(points)
        segments = extractor.call

        visit_segment = segments.find { |s| s[:mode] == :stationary }
        expect(visit_segment[:source]).to eq('overland')
      end
    end

    context 'with unknown points between known segments' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000, raw_data: {
                  'properties' => { 'motion' => ['driving'] }
                }),
          build(:point, user: user, timestamp: 1060, raw_data: {
                  'properties' => { 'motion' => ['driving'] }
                }),
          build(:point, user: user, timestamp: 1120, raw_data: {}), # Unknown point
          build(:point, user: user, timestamp: 1180, raw_data: {
                  'properties' => { 'motion' => ['driving'] }
                }),
          build(:point, user: user, timestamp: 1240, raw_data: {
                  'properties' => { 'motion' => ['driving'] }
                })
        ]
      end

      it 'merges unknown points into previous segment' do
        extractor = described_class.new(points)
        segments = extractor.call

        # Should have 1 driving segment covering all 5 points (0-4)
        expect(segments.length).to eq(1)
        expect(segments[0][:mode]).to eq(:driving)
        expect(segments[0][:start_index]).to eq(0)
        expect(segments[0][:end_index]).to eq(4)
      end

      it 'downgrades confidence when merging unknown points' do
        extractor = described_class.new(points)
        segments = extractor.call

        expect(segments[0][:confidence]).to eq(:medium)
      end
    end

    context 'with unknown point at start' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000, raw_data: {}), # Unknown at start
          build(:point, user: user, timestamp: 1060, raw_data: {
                  'properties' => { 'motion' => ['walking'] }
                }),
          build(:point, user: user, timestamp: 1120, raw_data: {
                  'properties' => { 'motion' => ['walking'] }
                })
        ]
      end

      it 'merges leading unknown point into next segment' do
        extractor = described_class.new(points)
        segments = extractor.call

        expect(segments.length).to eq(1)
        expect(segments[0][:mode]).to eq(:walking)
        expect(segments[0][:start_index]).to eq(0)
        expect(segments[0][:end_index]).to eq(2)
      end

      it 'downgrades confidence for segment with leading unknown' do
        extractor = described_class.new(points)
        segments = extractor.call

        expect(segments[0][:confidence]).to eq(:medium)
      end
    end

    context 'with unknown point between different modes' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000, raw_data: {
                  'properties' => { 'motion' => ['driving'] }
                }),
          build(:point, user: user, timestamp: 1060, raw_data: {
                  'properties' => { 'motion' => ['driving'] }
                }),
          build(:point, user: user, timestamp: 1120, raw_data: {}), # Unknown between modes
          build(:point, user: user, timestamp: 1180, raw_data: {
                  'properties' => { 'motion' => ['walking'] }
                }),
          build(:point, user: user, timestamp: 1240, raw_data: {
                  'properties' => { 'motion' => ['walking'] }
                })
        ]
      end

      it 'merges unknown into previous segment (driving)' do
        extractor = described_class.new(points)
        segments = extractor.call

        expect(segments.length).to eq(2)
        expect(segments[0][:mode]).to eq(:driving)
        expect(segments[0][:end_index]).to eq(2) # Includes the unknown point
        expect(segments[1][:mode]).to eq(:walking)
        expect(segments[1][:start_index]).to eq(3)
      end
    end

    context 'when motion_data is present' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000,
                        motion_data: { 'properties' => { 'motion' => ['walking'] } },
                        raw_data: { 'properties' => { 'motion' => ['driving'] } }),
          build(:point, user: user, timestamp: 1060,
                        motion_data: { 'properties' => { 'motion' => ['walking'] } },
                        raw_data: { 'properties' => { 'motion' => ['driving'] } })
        ]
      end

      it 'prefers motion_data over raw_data' do
        extractor = described_class.new(points)
        segments = extractor.call

        expect(segments.length).to eq(1)
        expect(segments[0][:mode]).to eq(:walking)
      end
    end

    context 'when motion_data is empty and raw_data has data' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000,
                        motion_data: {},
                        raw_data: { 'properties' => { 'motion' => ['cycling'] } }),
          build(:point, user: user, timestamp: 1060,
                        motion_data: {},
                        raw_data: { 'properties' => { 'motion' => ['cycling'] } })
        ]
      end

      it 'falls back to raw_data' do
        extractor = described_class.new(points)
        segments = extractor.call

        expect(segments.length).to eq(1)
        expect(segments[0][:mode]).to eq(:cycling)
      end
    end

    context 'with contiguous segments ensuring no gaps' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000, raw_data: {
                  'properties' => { 'motion' => ['driving'] }
                }),
          build(:point, user: user, timestamp: 1060, raw_data: {}), # Unknown
          build(:point, user: user, timestamp: 1120, raw_data: {
                  'properties' => { 'motion' => ['walking'] }
                }),
          build(:point, user: user, timestamp: 1180, raw_data: {}), # Unknown
          build(:point, user: user, timestamp: 1240, raw_data: {
                  'properties' => { 'motion' => ['walking'] }
                })
        ]
      end

      it 'produces contiguous segments with no index gaps' do
        extractor = described_class.new(points)
        segments = extractor.call

        # Verify segments are contiguous
        segments.each_cons(2) do |seg1, seg2|
          expect(seg2[:start_index]).to eq(seg1[:end_index] + 1),
                                        "Gap between segments: #{seg1[:end_index]} -> #{seg2[:start_index]}"
        end

        # First segment should start at 0, last should end at last point
        expect(segments.first[:start_index]).to eq(0)
        expect(segments.last[:end_index]).to eq(4)
      end
    end
  end
end
