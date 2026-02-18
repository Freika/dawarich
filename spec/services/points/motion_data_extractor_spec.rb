# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::MotionDataExtractor do
  describe '.from_overland_properties' do
    it 'extracts motion, activity, action with string keys' do
      properties = { motion: ['driving'], activity: 'other_navigation', action: 'moving' }
      result = described_class.from_overland_properties(properties)

      expect(result).to eq({ 'motion' => ['driving'], 'activity' => 'other_navigation', 'action' => 'moving' })
    end

    it 'handles string-keyed input' do
      properties = { 'motion' => ['walking'], 'activity' => 'stationary' }
      result = described_class.from_overland_properties(properties)

      expect(result).to eq({ 'motion' => ['walking'], 'activity' => 'stationary' })
    end

    it 'omits nil values' do
      properties = { motion: ['driving'], activity: nil }
      result = described_class.from_overland_properties(properties)

      expect(result).to eq({ 'motion' => ['driving'] })
    end

    it 'returns empty hash for nil input' do
      expect(described_class.from_overland_properties(nil)).to eq({})
    end

    it 'returns empty hash when no relevant keys present' do
      expect(described_class.from_overland_properties({ speed: 5 })).to eq({})
    end
  end

  describe '.from_google_phone_takeout' do
    it 'extracts activityRecord with probableActivities' do
      raw = { 'activityRecord' => { 'probableActivities' => [{ 'type' => 'WALKING' }] } }
      result = described_class.from_google_phone_takeout(raw)

      expect(result).to eq({ 'activityRecord' => { 'probableActivities' => [{ 'type' => 'WALKING' }] } })
    end

    it 'extracts activity field' do
      raw = { 'activity' => [{ 'type' => 'STILL' }] }
      result = described_class.from_google_phone_takeout(raw)

      expect(result).to eq({ 'activity' => [{ 'type' => 'STILL' }] })
    end

    it 'returns empty hash for nil input' do
      expect(described_class.from_google_phone_takeout(nil)).to eq({})
    end
  end

  describe '.from_google_records' do
    it 'wraps activity under activity key' do
      location = { 'activity' => [{ 'type' => 'WALKING' }] }
      result = described_class.from_google_records(location)

      expect(result).to eq({ 'activity' => [{ 'type' => 'WALKING' }] })
    end

    it 'falls back to activityRecord' do
      location = { 'activityRecord' => { 'type' => 'DRIVING' } }
      result = described_class.from_google_records(location)

      expect(result).to eq({ 'activity' => { 'type' => 'DRIVING' } })
    end

    it 'returns empty hash when no activity data' do
      expect(described_class.from_google_records({ 'speed' => 5 })).to eq({})
    end
  end

  describe '.from_google_semantic_history' do
    it 'extracts activities and activityType' do
      raw = { 'activities' => [{ 'activityType' => 'WALKING' }], 'activityType' => 'WALKING' }
      result = described_class.from_google_semantic_history(raw)

      expect(result).to eq({
                             'activities' => [{ 'activityType' => 'WALKING' }],
        'activityType' => 'WALKING'
                           })
    end

    it 'extracts travelMode from waypointPath' do
      raw = { 'waypointPath' => { 'travelMode' => 'DRIVE' } }
      result = described_class.from_google_semantic_history(raw)

      expect(result).to eq({ 'travelMode' => 'DRIVE' })
    end

    it 'returns empty hash for nil input' do
      expect(described_class.from_google_semantic_history(nil)).to eq({})
    end
  end

  describe '.from_owntracks' do
    it 'extracts m and _type with string keys' do
      params = { m: 1, _type: 'location' }
      result = described_class.from_owntracks(params)

      expect(result).to eq({ 'm' => 1, '_type' => 'location' })
    end

    it 'handles string-keyed input' do
      params = { 'm' => 2, '_type' => 'location' }
      result = described_class.from_owntracks(params)

      expect(result).to eq({ 'm' => 2, '_type' => 'location' })
    end

    it 'returns empty hash when m is absent' do
      expect(described_class.from_owntracks({ _type: 'location' })).to eq({})
    end

    it 'returns empty hash for nil input' do
      expect(described_class.from_owntracks(nil)).to eq({})
    end
  end

  describe '.from_raw_data' do
    it 'detects Overland data from properties' do
      raw = { 'properties' => { 'motion' => ['driving'], 'activity' => 'other_navigation' } }
      result = described_class.from_raw_data(raw)

      expect(result).to eq({ 'motion' => ['driving'], 'activity' => 'other_navigation' })
    end

    it 'detects Google data with activityRecord' do
      raw = { 'activityRecord' => { 'probableActivities' => [{ 'type' => 'WALKING' }] } }
      result = described_class.from_raw_data(raw)

      expect(result).to eq({ 'activityRecord' => { 'probableActivities' => [{ 'type' => 'WALKING' }] } })
    end

    it 'detects Google Semantic History data' do
      raw = { 'activityType' => 'WALKING', 'activities' => [{ 'activityType' => 'WALKING' }] }
      result = described_class.from_raw_data(raw)

      expect(result).to eq({ 'activityType' => 'WALKING', 'activities' => [{ 'activityType' => 'WALKING' }] })
    end

    it 'detects OwnTracks data' do
      raw = { 'm' => 1, '_type' => 'location', 'lat' => 52.0, 'lon' => 13.0 }
      result = described_class.from_raw_data(raw)

      expect(result).to eq({ 'm' => 1, '_type' => 'location' })
    end

    it 'returns empty hash for empty input' do
      expect(described_class.from_raw_data({})).to eq({})
    end

    it 'returns empty hash for nil input' do
      expect(described_class.from_raw_data(nil)).to eq({})
    end

    it 'returns empty hash for non-hash input' do
      expect(described_class.from_raw_data('string')).to eq({})
    end
  end
end
