# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Exact cached point summaries' do
  let(:user) { create(:user) }
  let!(:point) { create(:point, user: user, timestamp: Time.utc(2020, 6, 15).to_i) }

  def summary(scope = user.points)
    Points::ReadSummary.new(scope, user_id: user.id).call
  end

  def aggregates(&block)
    statements = []
    ActiveSupport::Notifications.subscribed(->(*args) { statements << args.last[:sql] }, 'sql.active_record', &block)
    statements.grep(/SELECT.*COUNT\(\*\).*FROM "points"/i)
  end

  it 'reuses exact aggregates without scanning points again' do
    expect(summary).to eq([1, point.timestamp, point.updated_at])
    expect(aggregates { expect(summary.first).to eq(1) }).to be_empty
  end

  it 'invalidates after bulk inserts, updates, timestamp moves and deletions' do
    expect(summary.first).to eq(1)
    Point.transaction(requires_new: true) do
      Point.insert_all!([{ user_id: user.id, timestamp: point.timestamp + 1000, lonlat: 'POINT(2 2)' }])
      expect(summary[1]).to eq(point.timestamp + 1000)
      raise ActiveRecord::Rollback
    end
    Point.insert_all!([{ user_id: user.id, timestamp: point.timestamp + 1, lonlat: 'POINT(1 1)' }])
    expect(summary.first(2)).to eq([2, point.timestamp + 1])
    later = point.updated_at + 1.day
    user.points.update_all(updated_at: later)
    expect(summary.last).to eq(later)
    user.points.update_all(timestamp: Time.utc(2021, 1, 1).to_i)
    expect(summary[1]).to eq(Time.utc(2021, 1, 1).to_i)
    user.points.delete_all
    expect(summary).to eq([0, nil, nil])
  end

  it 'separates users, imports, anomaly filters and bounding boxes' do
    other = create(:user)
    create(:point, user: other, timestamp: point.timestamp)
    imported = create(:import, user: user)
    create(:point, user: user, import: imported, timestamp: point.timestamp + 2, anomaly: true)
    expect(summary.first).to eq(2)
    expect(summary(user.points.not_anomaly).first).to eq(1)
    expect(summary(user.points.where(import_id: imported.id)).first).to eq(1)
    expect(summary(user.points.where('ST_X(lonlat::geometry) > 179')).first).to eq(0)
  end

  it 'invalidates both owners when a point is reassigned' do
    other = create(:user)
    expect(summary.first).to eq(1)
    expect(Points::ReadSummary.new(other.points, user_id: other.id).call.first).to eq(0)
    point.update_columns(user_id: other.id)
    expect(summary.first).to eq(0)
    expect(Points::ReadSummary.new(other.points, user_id: other.id).call.first).to eq(1)
  end
end

RSpec.describe 'Point revision schema portability' do
  it 'preserves revision functions and statement triggers in Ruby schema dumps' do
    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
    %w[insert update delete truncate].each do |event|
      expect(stream.string).to include("CREATE OR REPLACE FUNCTION public.points_revision_#{event}()")
      expect(stream.string).to include("CREATE TRIGGER points_revision_#{event}")
    end
  end
end
