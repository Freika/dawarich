# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Bulk point insertion rejects records with blank lonlat' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user:) }

  let(:inserter_class) do
    Class.new do
      include Imports::BulkInsertable

      attr_reader :import

      def initialize(import)
        @import = import
      end

      def insert(batch)
        bulk_insert_points(batch)
      end

      def importer_name
        'Test'
      end
    end
  end

  let(:inserter) { inserter_class.new(import) }

  let(:valid_record) do
    { lonlat: 'POINT(13.4 52.5)', timestamp: 1_700_000_000, user_id: user.id }
  end

  let(:nil_lonlat_record) do
    { lonlat: nil, timestamp: 1_700_000_001, user_id: user.id }
  end

  it 'does not persist points with nil lonlat' do
    inserter.insert([valid_record, nil_lonlat_record])

    expect(Point.where(user_id: user.id).count).to eq(1)
    expect(Point.where(user_id: user.id, lonlat: nil)).to be_empty
  end

  it 'returns the count of inserted valid points only' do
    expect(inserter.insert([valid_record, nil_lonlat_record])).to eq(1)
  end

  it 'returns 0 when every record has a blank lonlat' do
    expect(inserter.insert([nil_lonlat_record, { lonlat: '', timestamp: 1, user_id: user.id }])).to eq(0)
  end
end
