# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261102000000_repair_optional_altitude_invalidation.rb')

RSpec.describe 'Optional altitude invalidation' do
  let(:connection) { ActiveRecord::Base.connection }

  before { RepairOptionalAltitudeInvalidation.new.up }

  it 'completes partial execution and retains point data and revision side effects' do
    point = create(:point)
    connection.execute(File.read(Rails.root.join('db/exploration_invalidation.sql')))
    revisions = connection.select_all('SELECT * FROM achievement_collection_states').to_a
    2.times { RepairOptionalAltitudeInvalidation.new.up }
    RepairOptionalAltitudeInvalidation.new.down
    expect(Point.exists?(point.id)).to be(true)
    expect(connection.select_all('SELECT * FROM achievement_collection_states').to_a).to eq(revisions)
  end

  [false, true].each do |decimal|
    context "with altitude_decimal present: #{decimal}" do
      before do
        unless decimal
          # Loads Point while the column exists; the model caches column support once per process.
          allow(Point).to receive(:altitude_decimal_supported?).and_return(false)
          connection.execute('ALTER TABLE points DROP COLUMN IF EXISTS altitude_decimal')
        end
        Point.reset_column_information
      end

      after do
        unless connection.column_exists?(:points, :altitude_decimal)
          connection.add_column(:points, :altitude_decimal, :decimal, precision: 10, scale: 2)
        end
        Point.reset_column_information
      end

      it 'supports inserts, upserts and meaningful updates while ignoring unchanged rows' do
        user = create(:user)
        point = create(:point, user: user)
        expect { Point.where(id: point.id).update_all(altitude: 123) }.not_to raise_error
        revision = lambda {
          connection.select_value("SELECT revision FROM achievement_collection_states WHERE user_id = #{user.id}")
        }
        before_repeat = revision.call
        Point.where(id: point.id).update_all(altitude: 123)
        expect(revision.call).to eq(before_repeat)
        row = { id: point.id, user_id: user.id, timestamp: point.timestamp, lonlat: point.lonlat, altitude: 124 }
        expect { Point.upsert_all([row], unique_by: :id) }.not_to raise_error
      end
    end
  end
end
