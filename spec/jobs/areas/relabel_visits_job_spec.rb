# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Areas::RelabelVisitsJob do
  let(:user) { create(:user) }
  let(:lat0) { 51.3402 }
  let(:lon0) { 12.3712 }
  let(:area) { create(:area, user: user, latitude: lat0, longitude: lon0, radius: 200) }

  def north(meters) = meters / 111_320.0

  def visit_at(lat, lon, **attrs)
    place = create(:place, user: user, latitude: lat, longitude: lon)
    create(:visit, { user: user, place: place, area: nil,
                     started_at: Time.zone.now - 2.days, ended_at: Time.zone.now - 2.days + 1.hour,
                     duration: 60 }.merge(attrs))
  end

  it 'labels historical visits whose center lies inside the area' do
    inside = visit_at(lat0 + north(50), lon0)
    outside = visit_at(lat0 + north(900), lon0)

    described_class.perform_now(area.id)

    expect(inside.reload.area_id).to eq(area.id)
    expect(outside.reload.area_id).to be_nil
  end

  it 'labels point-backed visits without a place' do
    visit = create(:visit, user: user, place: nil, area: nil,
                           started_at: Time.zone.now - 1.day, ended_at: Time.zone.now - 1.day + 1.hour,
                           duration: 60)
    create(:point, user: user, visit_id: visit.id, latitude: lat0, longitude: lon0,
                   lonlat: "POINT(#{lon0} #{lat0})")

    described_class.perform_now(area.id)

    expect(visit.reload.area_id).to eq(area.id)
  end

  it 'leaves a visit with no place and no points alone' do
    bare = create(:visit, user: user, place: nil, area: nil,
                          started_at: Time.zone.now - 1.day, ended_at: Time.zone.now - 1.day + 1.hour,
                          duration: 60)

    expect { described_class.perform_now(area.id) }.not_to raise_error
    expect(bare.reload.area_id).to be_nil
  end

  it 'resolves point-backed centers in one grouped query, not one per visit' do
    2.times do |i|
      visit = create(:visit, user: user, place: nil, area: nil,
                             started_at: Time.zone.now - (i + 1).days,
                             ended_at: Time.zone.now - (i + 1).days + 1.hour, duration: 60)
      create(:point, user: user, visit_id: visit.id, latitude: lat0, longitude: lon0,
                     lonlat: "POINT(#{lon0} #{lat0})")
    end

    point_queries = []
    listener = lambda do |_name, _start, _finish, _id, payload|
      point_queries << payload[:sql] if payload[:sql].to_s.match?(/SELECT.*FROM "points"/m)
    end

    ActiveSupport::Notifications.subscribed(listener, 'sql.active_record') do
      described_class.perform_now(area.id)
    end

    expect(user.visits.where(area_id: area.id).count).to eq(2)
    expect(point_queries.length).to eq(1)
  end

  it 'never relabels visits already attributed to an area, tombstoned or declined' do
    other_area = create(:area, user: user, latitude: lat0, longitude: lon0, radius: 300)
    claimed = visit_at(lat0, lon0, area: other_area)
    tombstoned = visit_at(lat0, lon0 + north(10), deleted_at: Time.zone.now)
    declined = visit_at(lat0 + north(20), lon0, status: :declined)

    described_class.perform_now(area.id)

    expect(claimed.reload.area_id).to eq(other_area.id)
    expect(tombstoned.reload.area_id).to be_nil
    expect(declined.reload.area_id).to be_nil
  end

  it 'quietly skips a deleted area' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  describe 'enqueueing from Area lifecycle' do
    it 'enqueues on create and on geometry changes, but not on rename' do
      new_area = nil
      expect { new_area = create(:area, user: user, latitude: lat0, longitude: lon0, radius: 100) }
        .to have_enqueued_job(described_class)

      expect { new_area.update!(radius: 250) }.to have_enqueued_job(described_class).with(new_area.id)
      expect { new_area.update!(name: 'Renamed') }.not_to have_enqueued_job(described_class)
    end
  end
end
