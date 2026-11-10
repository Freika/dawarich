# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::Detection::AwayPeriods do
  subject(:periods) { described_class.new(user).call }

  let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }
  let(:place) { create(:place, user:, latitude: 52.52, longitude: 13.405) }

  def point_at(lon, lat, time, tracker_id: 'phone', **attrs)
    create(:point, user:, lonlat: "POINT(#{lon} #{lat})", timestamp: time.to_i, tracker_id:, **attrs)
  end

  context 'with an open-dated Home in Berlin' do
    before do
      create(:home, user:, place:)
      point_at(13.405, 52.52, Time.utc(2026, 1, 1, 12)) # the user has been recorded at home
    end

    it 'returns one run for a stay in Lisbon between two points at home' do
      home_before = point_at(13.405, 52.52, Time.utc(2026, 10, 10, 6))
      first_far = point_at(-9.1393, 38.7223, Time.utc(2026, 10, 10, 14))
      last_far = point_at(-9.1393, 38.7223, Time.utc(2026, 10, 14, 9))
      home_after = point_at(13.405, 52.52, Time.utc(2026, 10, 14, 18))

      expect(periods.size).to eq(1)
      expect(periods.first).to have_attributes(
        first_far_at: Time.zone.at(first_far.timestamp), last_far_at: Time.zone.at(last_far.timestamp),
        home_before_at: Time.zone.at(home_before.timestamp), home_after_at: Time.zone.at(home_after.timestamp),
        closed: true
      )
    end

    it 'returns nothing for points within 50 km' do
      point_at(13.06, 52.40, Time.utc(2026, 10, 10, 14))
      point_at(13.405, 52.52, Time.utc(2026, 10, 11, 9))
      expect(periods).to be_empty
    end

    it 'marks a run with no later point as not closed' do
      point_at(13.405, 52.52, Time.utc(2026, 10, 10, 6))
      point_at(-9.1393, 38.7223, Time.utc(2026, 10, 10, 14))
      expect(periods.first.closed).to be(false)
    end

    it 'ignores anomaly points' do
      point_at(-9.1393, 38.7223, Time.utc(2026, 10, 10, 14), anomaly: true)
      point_at(13.405, 52.52, Time.utc(2026, 10, 11, 9))
      expect(periods).to be_empty
    end

    # Review Focus 1
    it 'keeps live points, which have no import, and drops demo points' do
      demo = create(:import, user:, demo: true)
      point_at(-9.1393, 38.7223, Time.utc(2026, 10, 10, 14), import: nil)
      point_at(-9.1393, 38.7223, Time.utc(2026, 9, 1, 14), import: demo)
      point_at(13.405, 52.52, Time.utc(2026, 10, 11, 9), import: nil)

      expect(periods.map(&:first_far_at)).to eq([Time.utc(2026, 10, 10, 14)])
    end

    # Review Focus 2
    it 'is not interrupted by a second device that stayed at home' do
      point_at(-9.1393, 38.7223, Time.utc(2026, 10, 10, 14), tracker_id: 'phone')
      point_at(13.405, 52.52, Time.utc(2026, 10, 11, 12), tracker_id: 'tablet')
      point_at(-9.1393, 38.7223, Time.utc(2026, 10, 12, 9), tracker_id: 'phone')
      point_at(13.405, 52.52, Time.utc(2026, 10, 12, 20), tracker_id: 'phone')

      expect(user.points.where.not(source_id: nil)).to be_empty # the device comes from points.tracker_id
      expect(periods.size).to eq(1)
      expect(periods.first).to have_attributes(first_far_at: Time.utc(2026, 10, 10, 14),
                                               last_far_at: Time.utc(2026, 10, 12, 9))
    end

    it 'reads the device of a point stamped with a source from the source' do
      tablet = PointSource.create!(tracker_id: 'tablet', digest: 'tablet-digest')
      point_at(-9.1393, 38.7223, Time.utc(2026, 10, 10, 14), tracker_id: 'phone')
      point_at(13.405, 52.52, Time.utc(2026, 10, 11, 12), tracker_id: 'phone', source: tablet)
      point_at(-9.1393, 38.7223, Time.utc(2026, 10, 12, 9), tracker_id: 'phone')
      point_at(13.405, 52.52, Time.utc(2026, 10, 12, 20), tracker_id: 'phone')

      expect(periods.map(&:first_far_at)).to eq([Time.utc(2026, 10, 10, 14)])
    end

    it 'counts a Home at an archived place' do
      place.update!(archived_at: Time.current)
      point_at(-9.1393, 38.7223, Time.utc(2026, 10, 10, 14))
      expect(periods.size).to eq(1)
    end
  end

  it 'puts an open-dated Home in effect from the first point recorded there' do
    create(:home, user:, place:)
    point_at(-9.1393, 38.7223, Time.utc(2026, 8, 1, 12)) # before the user was ever seen at home
    point_at(-9.1393, 38.7223, Time.utc(2026, 8, 20, 12))
    point_at(13.405, 52.52, Time.utc(2026, 9, 1, 12))
    point_at(-9.1393, 38.7223, Time.utc(2026, 10, 10, 14))
    point_at(13.405, 52.52, Time.utc(2026, 10, 14, 9))
    expect(periods.map(&:first_far_at)).to eq([Time.utc(2026, 10, 10, 14)])
  end

  it 'ignores a Home the user was never recorded at' do
    create(:home, user:, place:)
    point_at(-9.1393, 38.7223, Time.utc(2026, 10, 10, 14))
    point_at(-9.1393, 38.7223, Time.utc(2026, 10, 12, 14))
    expect(periods).to be_empty
  end

  it 'treats dates with no Home in effect as unknown' do
    create(:home, user:, place:, started_on: Date.new(2026, 10, 12))
    point_at(-9.1393, 38.7223, Time.utc(2026, 10, 10, 14)) # before the Home began
    point_at(-9.1393, 38.7223, Time.utc(2026, 10, 13, 14))
    point_at(13.405, 52.52, Time.utc(2026, 10, 14, 9))
    expect(periods.map(&:first_far_at)).to eq([Time.utc(2026, 10, 13, 14)])
  end

  it 'ends a Home in effect on its end date, inclusive' do
    create(:home, user:, place:, started_on: Date.new(2026, 1, 1), ended_on: Date.new(2026, 10, 12))
    point_at(13.405, 52.52, Time.utc(2026, 10, 10, 6))
    on_end_date = point_at(-9.1393, 38.7223, Time.utc(2026, 10, 12, 14))
    point_at(-9.1393, 38.7223, Time.utc(2026, 10, 13, 14)) # after the Home ended: unknown
    point_at(13.405, 52.52, Time.utc(2026, 10, 14, 9))

    expect(periods.size).to eq(1)
    expect(periods.first).to have_attributes(first_far_at: Time.zone.at(on_end_date.timestamp),
                                             last_far_at: Time.zone.at(on_end_date.timestamp), closed: true)
  end

  it 'is near when any Home in effect is near' do
    create(:home, user:, place:)
    create(:home, user:, place: create(:place, user:, latitude: 38.7223, longitude: -9.1393))
    point_at(13.405, 52.52, Time.utc(2026, 10, 1, 12)) # puts the Berlin Home in effect too
    point_at(-9.1393, 38.7223, Time.utc(2026, 10, 10, 14))
    expect(periods).to be_empty
  end

  context 'with a Lite user' do
    let(:user) { create(:user, plan: :lite, skip_auto_trial: true, settings: { 'timezone' => 'Europe/Berlin' }) }

    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'reads only the Lite data window' do
      expect(user.plan_restricted?).to be(true)
      create(:home, user:, place:)
      point_at(13.405, 52.52, 25.months.ago)
      point_at(-9.1393, 38.7223, 24.months.ago)
      point_at(13.405, 52.52, 23.months.ago)
      point_at(13.405, 52.52, 3.months.ago)
      recent_far = point_at(-9.1393, 38.7223, 1.month.ago)
      point_at(13.405, 52.52, 25.days.ago)

      expect(periods.map(&:first_far_at)).to eq([Time.zone.at(recent_far.timestamp)])
    end
  end
end
