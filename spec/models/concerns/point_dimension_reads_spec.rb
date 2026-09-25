# frozen_string_literal: true

require 'rails_helper'

# Since Release D the point_sources dimension is the ONLY home of the
# device/importer combo: the legacy columns are gone from points, and a row
# without a resolvable source reads every combo attribute as nil.
RSpec.describe PointDimensionReads do
  let(:user) { create(:user) }

  let(:source) do
    create(:point_source, tracker_id: 'pixel-8', topic: 'owntracks/eugene/pixel',
                          ssid: nil, bssid: nil, connection: 'wifi', trigger: 'manual_event',
                          battery_status: 'unplugged', inrids: %w[home], in_regions: %w[berlin])
  end

  it 'serves a stamped row from the dimension' do
    point = create(:point, user: user, source: source)

    expect(point.tracker_id).to eq('pixel-8')
    expect(point.topic).to eq('owntracks/eugene/pixel')
    expect(point.inrids).to eq(%w[home])
    expect(point.in_regions).to eq(%w[berlin])
  end

  it 'serves enum labels through the dimension mirrors' do
    point = create(:point, user: user, source: source)

    expect(point.battery_status).to eq('unplugged')
    expect(point.trigger).to eq('manual_event')
    expect(point.connection).to eq('wifi')
  end

  it "serves the dimension's NULLs as nil" do
    point = create(:point, user: user, source: source)

    expect(point.ssid).to be_nil
    expect(point.bssid).to be_nil
  end

  it 'reads every combo attribute as nil on an unstamped row' do
    point = create(:point, user: user)

    described_class::DIMENSION_ATTRIBUTES.each do |attribute|
      expect(point.public_send(attribute)).to be_nil
    end
  end

  it 'survives partial selects that did not load source_id' do
    create(:point, user: user, source: source)

    slim = Point.where(user_id: user.id).select(:id, :timestamp).first

    expect(slim.tracker_id).to be_nil
  end

  it 'serves the combo from source_id alone (the D end state)' do
    point = create(:point, user: user, source: source)

    slim = Point.where(id: point.id).select(:id, :source_id).preload(:source).first

    expect(slim.tracker_id).to eq('pixel-8')
    expect(slim.battery_status).to eq('unplugged')
  end

  it 'reads a dangling source_id as NULLs, exactly like the SQL paths' do
    point = create(:point, user: user, source: source)
    source_id = source.id
    point.update_columns(source_id: source_id)
    PointSource.where(id: source_id).delete_all

    reloaded = Point.find(point.id)
    expect(reloaded.tracker_id).to be_nil
    expect(reloaded.battery_status).to be_nil
  end

  it 'keeps the PointSource enum mappings identical to the retired Point ones' do
    expect(PointSource.battery_statuses).to eq(
      'unknown' => 0, 'unplugged' => 1, 'charging' => 2, 'full' => 3,
      'connected_not_charging' => 4, 'discharging' => 5
    )
    expect(PointSource.triggers).to eq(
      'unknown' => 0, 'background_event' => 1, 'circular_region_event' => 2,
      'beacon_event' => 3, 'report_location_message_event' => 4, 'manual_event' => 5,
      'timer_based_event' => 6, 'settings_monitoring_event' => 7
    )
    expect(PointSource.connections).to eq('mobile' => 0, 'wifi' => 1, 'offline' => 2, 'unknown' => 4)
  end
end
