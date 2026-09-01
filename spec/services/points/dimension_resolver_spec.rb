# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::DimensionResolver do
  subject(:resolver) { described_class.new }

  let(:user) { create(:user) }

  # The attribute hash ingest would hand to upsert_all for `point`: enum labels
  # rather than integers, exactly as Points::Params produces them.
  let(:combo_attrs) do
    {
      tracker_id: 'pixel-8',
      topic: 'owntracks/eugene/pixel',
      ssid: 'home-wifi',
      bssid: 'aa:bb:cc:dd:ee:ff',
      connection: 'wifi',
      trigger: 'manual_event',
      battery_status: 'unplugged',
      inrids: %w[home office],
      in_regions: %w[berlin],
      motion_data: { 'activity' => 'walking' }
    }
  end

  describe 'digest stability' do
    it 'resolves the same combo to one dimension row across resolver instances' do
      first = resolver.stamp([combo_attrs.dup]).first[:source_id]

      second = nil
      expect { second = described_class.new.stamp([combo_attrs.dup]).first[:source_id] }
        .not_to change(PointSource, :count)
      expect(second).to eq(first)
    end
  end

  describe 'value normalisation' do
    it 'stores enum labels as their integers' do
      resolved = resolver.stamp([combo_attrs.dup]).first[:source_id]

      expect(PointSource.find(resolved).battery_status_before_type_cast).to eq(1)
    end

    it 'treats a missing array key as the empty array the column defaults to' do
      omitted = resolver.stamp([{ tracker_id: 'bare-device' }]).first[:source_id]
      explicit = resolver.stamp([{ tracker_id: 'bare-device', inrids: [], in_regions: [] }])
                         .first[:source_id]

      expect(omitted).to eq(explicit)
    end

    # jsonb_build_object renders nil and [] as `null` and `[]` — different
    # digests. Flattening nil into [] forked the dimension on ~0.5% of a
    # 1.6M-row dataset before this was fixed.
    it 'keeps a NULL array distinct from an empty one' do
      resolved_null = resolver.stamp([{ tracker_id: 'null-arrays', inrids: nil, in_regions: nil }])
                              .first[:source_id]
      resolved_empty = resolver.stamp([{ tracker_id: 'null-arrays', inrids: [], in_regions: [] }])
                               .first[:source_id]

      expect(resolved_null).not_to eq(resolved_empty)
    end
  end

  describe 'combo key stripping' do
    it 'removes the combo keys from the row hash once source_id is resolved' do
      row = { user_id: 1, timestamp: 1_700_000_000, tracker_id: 'pixel-8',
              topic: 't', ssid: 's', bssid: 'b', connection: 1, trigger: 5,
              battery_status: 1, inrids: %w[home], in_regions: %w[berlin],
              battery: 80, velocity: 12.5 }

      resolver.stamp([row])

      expect(row[:source_id]).to be_present
      PointSource::COMBO_COLUMNS.each do |column|
        expect(row).not_to have_key(column.to_sym), "expected #{column} to be stripped"
      end
      expect(row[:battery]).to eq(80)
      expect(row[:velocity]).to eq(12.5)
    end
  end

  describe 'reuse' do
    it 'inserts one row for a combo seen many times' do
      rows = Array.new(5) { combo_attrs.dup }

      expect { resolver.stamp(rows) }.to change(PointSource, :count).by(1)
      expect(rows.map { |r| r[:source_id] }.uniq.size).to eq(1)
    end

    # nextval fires before ON CONFLICT is evaluated, so a blind upsert would
    # consume an id every time ingest saw a combo it already stored.
    it 'does not burn sequence values on a combo that already exists' do
      resolver.stamp([combo_attrs.dup])
      last_id = PointSource.maximum(:id)

      described_class.new.stamp([combo_attrs.dup])

      expect(PointSource.maximum(:id)).to eq(last_id)
      expect(ActiveRecord::Base.connection.select_value('SELECT last_value FROM point_sources_id_seq'))
        .to eq(last_id)
    end
  end

  describe 'failed resolutions' do
    # The resolver lives for a whole import; remembering one lost race as
    # "this combo has no id" would leave every later point of the same device
    # unstamped.
    it 'retries a combo whose resolution failed instead of caching the nil' do
      failing = true
      allow(ActiveRecord::Base.connection).to receive(:select_value).and_wrap_original do |m, *args|
        failing && args.first.to_s.include?('point_sources') ? nil : m.call(*args)
      end

      expect(resolver.stamp([combo_attrs.dup]).first[:source_id]).to be_nil

      failing = false
      expect(resolver.stamp([combo_attrs.dup]).first[:source_id]).to be_present
    end
  end

  describe 'when the columns are not there yet' do
    include ActiveSupport::Testing::TimeHelpers

    it 'leaves rows untouched so ingest survives a deferred ALTER' do
      connection = ActiveRecord::Base.connection
      connection.execute('ALTER TABLE points DROP COLUMN source_id')
      Point.reset_column_information
      described_class.reset_column_availability!
      rows = [combo_attrs.dup]

      stamped = resolver.stamp(rows).first
      expect(stamped).not_to have_key(:source_id)
      expect(stamped[:tracker_id]).to eq('pixel-8')
    ensure
      Point.reset_column_information
      described_class.reset_column_availability!
    end

    # Production semantics (memoisation + recheck throttle are bypassed in the
    # test env): a "no" must expire once DataMigrations::AddPointDimensionColumnsJob
    # lands the deferred ALTER in another process, or ingest here stays
    # unstamped until a restart.
    it 'starts stamping without a restart once the deferred ALTER lands' do
      allow(Rails.env).to receive(:test?).and_return(false)
      described_class.reset_column_availability!
      connection = ActiveRecord::Base.connection
      connection.execute('ALTER TABLE points DROP COLUMN source_id')
      Point.reset_column_information

      expect(described_class.columns_available?).to be false

      connection.execute('ALTER TABLE points ADD COLUMN source_id integer')

      # Inside the throttle window the cached answer stands...
      expect(described_class.columns_available?).to be false

      # ...and past it the recheck sees the column and refreshes the model's
      # column cache, so stamping resumes in this process.
      travel(described_class::COLUMN_RECHECK_INTERVAL + 1) do
        expect(described_class.columns_available?).to be true
      end
      expect(Point.column_names).to include('source_id')
    ensure
      Point.reset_column_information
      described_class.reset_column_availability!
    end
  end
end
