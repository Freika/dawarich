# frozen_string_literal: true

require 'rails_helper'

# The re-import contract for the points slice: what export writes, import must
# restore to an equivalent row — including the device/importer combo, which
# export now reads through point_sources on stamped rows.
RSpec.describe 'points export/import round trip' do
  let(:user) { create(:user) }
  let(:combo_columns) { PointSource::COMBO_COLUMNS.map(&:to_sym) }

  def effective_combo(point)
    combo_columns.index_with { |attribute| point.public_send(attribute) }
  end

  def stamp!(point, attrs)
    source = PointSource.create!(digest: SecureRandom.hex(16), **attrs)
    point.update_columns(source_id: source.id)
  end

  it 'restores stamped and unstamped points to the same effective values' do
    stamped = create(:point, user: user, timestamp: 1_700_000_000)
    stamped.update_columns(tracker_id: 'legacy-divergent', topic: nil, battery_status: 0)
    # bssid stays NULL on the dimension while the legacy column carries a
    # value: the round trip must preserve the dimension's NULL.
    stamp!(stamped, tracker_id: 'pixel-8', topic: 'owntracks/eugene/pixel', bssid: nil,
                    battery_status: 'unplugged', inrids: %w[home], in_regions: %w[berlin])
    unstamped = create(:point, user: user, timestamp: 1_700_000_060)
    unstamped.update_columns(source_id: nil, tracker_id: 'legacy-device', connection: 1)

    exported = Users::ExportData::Points.new(user).call
    expected = [effective_combo(stamped.reload), effective_combo(unstamped.reload)]

    Point.where(user_id: user.id).delete_all
    Users::ImportData::Points.new(user, exported).call

    restored = user.points.order(:timestamp).to_a
    expect(restored.size).to eq(2)
    expect(restored.map { |point| effective_combo(point) }).to eq(expected)
  end

  # Divergence proves which side the export SQL actually reads; the
  # round-trip example above passes under either side and so cannot.
  it 'exports the device combo of a stamped row from the dimension' do
    point = create(:point, user: user)
    point.update_columns(tracker_id: 'legacy-divergent')
    stamp!(point, tracker_id: 'pixel-8')

    exported = Users::ExportData::Points.new(user).call.first

    expect(exported['tracker_id']).to eq('pixel-8')
  end

  # Byte-compatibility of the payload itself: dual-write keeps both sides
  # equal on every real row, so two rows with identical combos must export
  # identically whether the values were read from the dimension or from the
  # legacy columns.
  it 'exports identical payloads for a parity row regardless of the read side' do
    legacy_values = { tracker_id: 'pixel-8', topic: 'owntracks/eugene/pixel', ssid: 'home-wifi',
                      bssid: 'aa:bb', battery_status: 1, connection: 1, trigger: 5,
                      inrids: '{home}', in_regions: '{berlin}' }
    stamped = create(:point, user: user, timestamp: 1_700_000_000)
    stamped.update_columns(**legacy_values)
    stamp!(stamped, tracker_id: 'pixel-8', topic: 'owntracks/eugene/pixel', ssid: 'home-wifi',
                    bssid: 'aa:bb', battery_status: 'unplugged', connection: 'wifi',
                    trigger: 'manual_event', inrids: %w[home], in_regions: %w[berlin])
    unstamped = create(:point, user: user, timestamp: 1_700_000_060)
    unstamped.update_columns(source_id: nil, **legacy_values)

    from_dimension, from_legacy = Users::ExportData::Points.new(user).call

    expect(from_dimension.slice(*PointSource::COMBO_COLUMNS))
      .to eq(from_legacy.slice(*PointSource::COMBO_COLUMNS))
  end
end
