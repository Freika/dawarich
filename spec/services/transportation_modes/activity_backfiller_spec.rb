# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::ActivityBackfiller do
  let(:import) { create(:import, source: :google_semantic_history, skip_background_processing: true) }
  let(:timestamp) { Time.utc(2025, 1, 1, 12).to_i }
  let!(:point) do
    create(:point, import: import, user: import.user, timestamp: timestamp, motion_data: { 'motion' => ['walking'] })
  end

  def attach_payload(payload)
    import.file.attach(io: StringIO.new(payload.to_json), filename: 'synthetic.json', content_type: 'application/json')
  end

  def backfill_segment(activity)
    segment = activity.merge('duration' => {
                               'startTimestamp' => Time.at(timestamp - 60).utc.iso8601,
                               'endTimestamp' => Time.at(timestamp + 60).utc.iso8601
                             })
    attach_payload('timelineObjects' => [{ 'activitySegment' => segment }])
    expect(described_class.new(import).call).to be(true)
  end

  [
    { 'activities' => [{ 'activityType' => 'CYCLING', 'probability' => 0.9 }] },
    { 'activityType' => 'CYCLING' },
    { 'waypointPath' => { 'travelMode' => 'CYCLING' } }
  ].each do |activity|
    it "makes #{activity.keys.first} hints consumable by the transportation detector" do
      backfill_segment(activity)

      expect(TransportationModes::HintScorer.call(point.reload.motion_data).keys).to eq([:cycling])
      expect(point.motion_data).to include('motion' => ['walking'])
    end
  end

  it 'only updates the current imports points within the segment time range' do
    outside = create(:point, import: import, user: import.user, timestamp: timestamp + 3600, motion_data: {})
    other = create(:point, user: import.user, timestamp: timestamp, motion_data: {})
    backfill_segment('activityType' => 'CYCLING')

    expect(outside.reload.motion_data).to eq({})
    expect(other.reload.motion_data).to eq({})
    expect(point.reload.motion_data).to include('activityType' => 'CYCLING')
  end

  it 'leaves motion data untouched when a segment has no activity information' do
    backfill_segment({})

    expect(point.reload.motion_data).to eq('motion' => ['walking'])
  end

  it 'preserves the phone takeout activityRecord shape' do
    import.update!(source: :google_phone_takeout)
    attach_payload('locations' => [{
                     'timestamp' => Time.at(timestamp).utc.iso8601,
                     'activityRecord' => { 'probableActivities' => [{ 'type' => 'CYCLING', 'confidence' => 0.9 }] }
                   }])

    described_class.new(import).call

    expect(TransportationModes::HintScorer.call(point.reload.motion_data).keys).to eq([:cycling])
    expect(point.motion_data).to include('motion' => ['walking'])
  end
end
