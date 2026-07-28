# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::TrackerIdBackfiller do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user) }

  it 'derives google-records-device-* from raw_data deviceTag' do
    point = create(:point, user: user, tracker_id: nil, raw_data: { 'deviceTag' => 1_111_111_111 })

    described_class.new(user).call

    expect(point.reload.tracker_id).to eq('google-records-device-1111111111')
  end

  it 'uses raw_data tid for OwnTracks-style legacy points' do
    point = create(:point, user: user, tracker_id: nil, raw_data: { 'tid' => 'ph' })

    described_class.new(user).call

    expect(point.reload.tracker_id).to eq('ph')
  end

  it 'falls back to legacy-import-<import_id> when raw_data has no device info' do
    point = create(:point, user: user, tracker_id: nil, raw_data: {}, import: import)

    described_class.new(user).call

    expect(point.reload.tracker_id).to eq("legacy-import-#{import.id}")
  end

  it 'prefers deviceTag over tid when both present' do
    point = create(
      :point,
      user: user,
      tracker_id: nil,
      raw_data: { 'deviceTag' => 2_222_222_222, 'tid' => 'ph' },
      import: import
    )

    described_class.new(user).call

    expect(point.reload.tracker_id).to eq('google-records-device-2222222222')
  end

  it 'leaves tracker_id NULL when no device info AND no import_id' do
    point = create(:point, user: user, tracker_id: nil, raw_data: {}, import: nil)

    described_class.new(user).call

    expect(point.reload.tracker_id).to be_nil
  end

  it 'does not touch points that already have tracker_id set' do
    point = create(:point, user: user, tracker_id: 'iphone', raw_data: { 'deviceTag' => 1 })

    described_class.new(user).call

    expect(point.reload.tracker_id).to eq('iphone')
  end

  it 'rewrites the legacy semantic-import constant to the per-import value' do
    import = create(:import, user: user)
    point = create(:point, user: user, tracker_id: 'google-maps-timeline-export', raw_data: {}, import: import)

    described_class.new(user).call

    expect(point.reload.tracker_id).to eq("legacy-import-#{import.id}")
  end

  it 'upgrades a legacy-constant point to its deviceTag when raw_data still has one' do
    import = create(:import, user: user)
    point = create(:point, user: user, tracker_id: 'google-maps-timeline-export',
                           raw_data: { 'deviceTag' => 3_333_333_333 }, import: import)

    described_class.new(user).call

    expect(point.reload.tracker_id).to eq('google-records-device-3333333333')
  end

  it 'rewrites the legacy phone-takeout constant to the per-import value' do
    import = create(:import, user: user)
    point = create(:point, user: user, tracker_id: 'google-maps-phone-timeline-export', raw_data: {}, import: import)

    described_class.new(user).call

    expect(point.reload.tracker_id).to eq("legacy-import-#{import.id}")
  end

  it 'leaves per-device records tracker ids untouched' do
    point = create(:point, user: user, tracker_id: 'google-records-device-123', raw_data: {})

    described_class.new(user).call

    expect(point.reload.tracker_id).to eq('google-records-device-123')
  end

  it 'only updates points belonging to the passed user' do
    other_user = create(:user)
    other_point = create(:point, user: other_user, tracker_id: nil, raw_data: { 'tid' => 'wt' })

    described_class.new(user).call

    expect(other_point.reload.tracker_id).to be_nil
  end

  it 'returns the count of rows actually backfilled' do
    create(:point, user: user, tracker_id: nil, raw_data: { 'tid' => 'a' })
    create(:point, user: user, tracker_id: nil, raw_data: { 'deviceTag' => 1 })
    create(:point, user: user, tracker_id: 'already-set', raw_data: {})

    expect(described_class.new(user).call).to eq(2)
  end

  it 'is idempotent: a second call backfills nothing more' do
    create(:point, user: user, tracker_id: nil, raw_data: { 'tid' => 'wt' })

    described_class.new(user).call
    expect(described_class.new(user).call).to eq(0)
  end

  it 'treats blank/whitespace-only tid and deviceTag as missing, falling through to legacy-import-*' do
    point_blank_tid = create(:point, user: user, tracker_id: nil, raw_data: { 'tid' => '' }, import: import)
    point_ws_device = create(:point, user: user, tracker_id: nil, raw_data: { 'deviceTag' => '   ' }, import: import)

    described_class.new(user).call

    expect(point_blank_tid.reload.tracker_id).to eq("legacy-import-#{import.id}")
    expect(point_ws_device.reload.tracker_id).to eq("legacy-import-#{import.id}")
  end

  it 'btrims whitespace around tid/deviceTag values so " ph " becomes "ph"' do
    point = create(:point, user: user, tracker_id: nil, raw_data: { 'tid' => '  ph  ' })

    described_class.new(user).call

    expect(point.reload.tracker_id).to eq('ph')
  end
end
