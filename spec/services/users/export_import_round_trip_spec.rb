# frozen_string_literal: true

require 'rails_helper'

# The re-import contract for the points slice: what export writes, import must
# restore to an equivalent row. Since Release D the device/importer combo
# lives on point_sources; the exported payload still carries the combo keys
# and the importer resolves them back into the dimension.
RSpec.describe 'points export/import round trip' do
  let(:user) { create(:user) }
  let(:combo_columns) { PointSource::COMBO_COLUMNS.map(&:to_sym) }

  def effective_combo(point)
    combo_columns.index_with { |attribute| point.public_send(attribute) }
  end

  it 'restores stamped and unstamped points to the same effective values' do
    source = create(:point_source, tracker_id: 'pixel-8', topic: 'owntracks/eugene/pixel',
                                   bssid: nil, battery_status: 'unplugged',
                                   inrids: %w[home], in_regions: %w[berlin])
    stamped = create(:point, user: user, timestamp: 1_700_000_000, source: source)
    unstamped = create(:point, user: user, timestamp: 1_700_000_060)

    exported = Users::ExportData::Points.new(user).call
    expected = [effective_combo(stamped.reload), effective_combo(unstamped.reload)]

    Point.where(user_id: user.id).delete_all
    Users::ImportData::Points.new(user, exported).call

    restored = user.points.order(:timestamp).to_a
    expect(restored.size).to eq(2)
    expect(restored.map { |point| effective_combo(point) }).to eq(expected)
  end

  it 'preserves a dimension NULL (bssid) across the round trip' do
    source = create(:point_source, tracker_id: 'pixel-8', bssid: nil)
    create(:point, user: user, timestamp: 1_700_000_000, source: source)

    exported = Users::ExportData::Points.new(user).call
    Point.where(user_id: user.id).delete_all
    Users::ImportData::Points.new(user, exported).call

    expect(user.points.first.bssid).to be_nil
    expect(user.points.first.tracker_id).to eq('pixel-8')
  end

  # Pre-D exports carry the combo as plain per-point keys; restoring one on a
  # v2 schema must stamp the combo into the dimension rather than dropping it.
  it 'restores a v1-era payload by resolving its combo into the dimension' do
    legacy_payload = [{
      'lonlat' => 'POINT(12.3712 51.3402)',
      'timestamp' => 1_650_000_000,
      'battery' => 80,
      'battery_status' => 2,
      'tracker_id' => 'old-phone',
      'topic' => 'owntracks/eugene/old-phone',
      'ssid' => 'home-wifi',
      'inrids' => %w[home],
      'in_regions' => %w[berlin],
      'mode' => 1,
      'ping' => 'stale',
      'external_track_id' => 'ext-1',
      'country' => 'Germany',
      'altitude' => 100,
      'altitude_decimal' => 101.25
    }]

    Users::ImportData::Points.new(user, legacy_payload).call

    point = user.points.first
    expect(point).to be_present
    expect(point.tracker_id).to eq('old-phone')
    expect(point.battery_status).to eq('charging')
    expect(point.ssid).to eq('home-wifi')
    expect(point.inrids).to eq(%w[home])
    expect(point.altitude).to eq(100.0)
  end
end
