# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::BulkInsertable do
  let(:harness_class) do
    Class.new do
      include Imports::BulkInsertable

      attr_reader :import

      def initialize(import)
        @import = import
      end

      def importer_name = 'Test'

      def insert(batch)
        bulk_insert_points(batch)
      end

      def on_bulk_insert_error(error)
        raise error
      end
    end
  end

  let(:user) { create(:user) }
  let(:import) { create(:import, user: user) }

  def record(lon, lat, timestamp)
    {
      lonlat: "POINT(#{lon} #{lat})",
      timestamp: timestamp,
      user_id: user.id,
      import_id: import.id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  it 'skips records at exactly (0,0) and inserts the rest' do
    inserted = harness_class.new(import).insert(
      [record(0.0, 0.0, 1_700_000_000), record(13.5, 52.4, 1_700_000_060)]
    )

    expect(inserted).to eq(1)
    expect(user.points.count).to eq(1)
    expect(user.points.first.lon).to eq(13.5)
  end
end
