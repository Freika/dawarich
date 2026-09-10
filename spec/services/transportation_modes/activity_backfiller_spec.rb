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
    attach_payload(
      'rawSignals' => [{
        'activityRecord' => {
          'timestamp' => Time.at(timestamp).utc.iso8601,
          'probableActivities' => [{ 'type' => 'CYCLING', 'confidence' => 0.9 }]
        }
      }]
    )

    described_class.new(import).call

    expect(TransportationModes::HintScorer.call(point.reload.motion_data).keys).to eq([:cycling])
    expect(point.motion_data).to include('motion' => ['walking'])
  end

  context 'when source is google_phone_takeout' do
    let(:pt_import) { create(:import, source: :google_phone_takeout, skip_background_processing: true) }
    let(:base_ts) { Time.utc(2025, 1, 1, 12).to_i }
    let(:activities) { [{ 'type' => 'CYCLING', 'confidence' => 0.9 }] }

    def point_at(timestamp, motion = {})
      create(:point, import: pt_import, user: pt_import.user, timestamp: timestamp, motion_data: motion)
    end

    def activity_signal(timestamp, probable = activities)
      {
        'activityRecord' => {
          'timestamp' => Time.at(timestamp).utc.iso8601,
          'probableActivities' => probable
        }
      }
    end

    def attach_raw_signals(signals, shape: :object)
      payload = shape == :array ? signals : { 'rawSignals' => signals }
      pt_import.file.attach(
        io: StringIO.new(payload.to_json),
        filename: 'phone-takeout.json',
        content_type: 'application/json'
      )
    end

    it 'does not read the google_records-shaped `locations` key' do
      p = point_at(base_ts)
      pt_import.file.attach(
        io: StringIO.new({ 'locations' => [{
          'timestamp' => Time.at(base_ts).utc.iso8601,
          'activityRecord' => { 'probableActivities' => activities }
        }] }.to_json),
        filename: 'phone-takeout.json',
        content_type: 'application/json'
      )

      described_class.new(pt_import).call

      expect(p.reload.motion_data).to eq({})
    end

    it 'joins an activityRecord to the nearest of two surrounding points within the window' do
      earlier = point_at(base_ts - 5)
      later = point_at(base_ts + 3)
      attach_raw_signals([activity_signal(base_ts)])

      described_class.new(pt_import).call

      expect(earlier.reload.motion_data).to eq({})
      expect(later.reload.motion_data['activityRecord']['probableActivities']).to eq(activities)
    end

    it 'keeps the closest activityRecord when several land in one point window, regardless of file order' do
      p = point_at(base_ts)
      near = [{ 'type' => 'STILL', 'confidence' => 0.8 }]
      far = [{ 'type' => 'WALKING', 'confidence' => 0.6 }]
      attach_raw_signals([activity_signal(base_ts + 2, near), activity_signal(base_ts + 20, far)])

      described_class.new(pt_import).call

      expect(p.reload.motion_data['activityRecord']['probableActivities']).to eq(near)
    end

    it 'does not attach when the nearest point is outside the join window' do
      p = point_at(base_ts)
      attach_raw_signals([activity_signal(base_ts + 600)]) # 10 minutes away

      described_class.new(pt_import).call

      expect(p.reload.motion_data).to eq({})
    end

    it 'handles the bare-array phone-takeout variant and backfills activityRecord entries' do
      p = point_at(base_ts)
      attach_raw_signals([activity_signal(base_ts)], shape: :array)

      expect(described_class.new(pt_import).call).to be(true)

      expect(p.reload.motion_data['activityRecord']['probableActivities']).to eq(activities)
    end

    it 'does not touch points that belong to another import sharing the same timestamp' do
      own = point_at(base_ts)
      other = create(:point, user: pt_import.user, timestamp: base_ts, motion_data: {})
      attach_raw_signals([activity_signal(base_ts)])

      described_class.new(pt_import).call

      expect(own.reload.motion_data['activityRecord']['probableActivities']).to eq(activities)
      expect(other.reload.motion_data).to eq({})
    end

    it 'preserves the existing motion_data when backfilling activityRecord' do
      p = point_at(base_ts, { 'motion' => ['walking'], 'activityType' => 'WALKING' })
      attach_raw_signals([activity_signal(base_ts)])

      described_class.new(pt_import).call

      expect(p.reload.motion_data).to include('motion' => ['walking'], 'activityType' => 'WALKING')
      expect(p.reload.motion_data).to include('activityRecord')
    end

    it 'is idempotent when run multiple times' do
      p = point_at(base_ts)
      attach_raw_signals([activity_signal(base_ts)])
      backfiller = described_class.new(pt_import)

      backfiller.call
      first = p.reload.motion_data
      backfiller.call

      expect(p.reload.motion_data).to eq(first)
    end

    describe 'end-to-end with the real importer and a co-located fixture' do
      let(:co_located_fixture) do
        Rails.root.join('spec/fixtures/files/google/phone_takeout_w_activity_record.json')
      end

      it 'backfills the activityRecord onto the imported position point' do
        import = create(:import, source: :google_phone_takeout, user: create(:user),
                              skip_background_processing: true)
        import.file.attach(io: File.open(co_located_fixture), filename: 'phone-takeout.json',
                           content_type: 'application/json')
        GoogleMaps::PhoneTakeoutImporter.new(import, import.user_id).call

        position_ts = DateTime.parse('2024-06-15T09:05:00.000Z').utc.to_i
        point = import.points.find_by(timestamp: position_ts)
        expect(point).to be_present
        expect(point.motion_data).not_to have_key('activityRecord')

        expect(described_class.new(import).call).to be(true)

        point.reload
        expect(point.motion_data['activityRecord']['probableActivities']).to be_an(Array)
        expect(TransportationModes::HintScorer.call(point.motion_data).keys).to eq([:stationary])
      end
    end
  end
end
