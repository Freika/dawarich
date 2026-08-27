# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PointDimensionReads do
  let(:user) { create(:user) }

  # Dual-write keeps the legacy columns and the dimension identical, so a
  # deliberately diverged row is the only way to see which side a reader
  # actually serves.
  def stamped_point(source_attrs, legacy_attrs)
    source = PointSource.create!(digest: SecureRandom.hex(16), **source_attrs)
    create(:point, user: user).tap do |point|
      point.update_columns(source_id: source.id, **legacy_attrs)
    end.reload
  end

  it 'serves a stamped row from the dimension, not the legacy columns' do
    point = stamped_point(
      { tracker_id: 'dimension-device', topic: 'owntracks/dim', battery_status: 'unplugged',
        inrids: %w[home] },
      { tracker_id: 'legacy-device', topic: 'owntracks/legacy', battery_status: 2, inrids: [] }
    )

    expect(point.tracker_id).to eq('dimension-device')
    expect(point.topic).to eq('owntracks/dim')
    expect(point.battery_status).to eq('unplugged')
    expect(point.inrids).to eq(%w[home])
  end

  it "serves the dimension's NULLs too, rather than resurrecting legacy values" do
    point = stamped_point({ tracker_id: nil, ssid: nil }, { tracker_id: 'legacy-device', ssid: 'home-wifi' })

    expect(point.tracker_id).to be_nil
    expect(point.ssid).to be_nil
  end

  it 'keeps reading legacy columns on an unstamped row' do
    point = create(:point, user: user)
    point.update_columns(source_id: nil, tracker_id: 'legacy-only', battery_status: 1)

    expect(point.reload.tracker_id).to eq('legacy-only')
    expect(point.reload.battery_status).to eq('unplugged')
  end

  # Several jobs select narrow column lists (id, timestamp, tracker_id, ...)
  # without source_id; those readers must not raise MissingAttributeError.
  it 'survives partial selects that did not load source_id' do
    point = stamped_point({ tracker_id: 'dimension-device' }, { tracker_id: 'legacy-device' })

    narrow = Point.select(:id, :tracker_id).find(point.id)

    expect(narrow.tracker_id).to eq('legacy-device')
  end

  it 'returns the same enum labels from both sides' do
    stamped = stamped_point({ trigger: 'manual_event', connection: 'wifi' }, { trigger: 5, connection: 1 })
    legacy = create(:point, user: user).tap { |p| p.update_columns(source_id: nil, trigger: 5, connection: 1) }

    expect(stamped.trigger).to eq(legacy.reload.trigger)
    expect(stamped.connection).to eq(legacy.reload.connection)
  end
end
