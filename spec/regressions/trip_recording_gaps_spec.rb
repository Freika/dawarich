# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trip recordings across device gaps' do
  let(:user) { create(:user, settings: { 'minutes_between_routes' => 10 }) }
  let(:trip) { create(:trip, user:, started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 1, 5)) }

  def recording(device, seconds, longitude, track: nil)
    create(:point, user:, track:, tracker_id: device, timestamp: trip.started_at.to_i + seconds,
                   lonlat: "POINT(#{longitude} 52)")
  end

  shared_examples 'preserved recording sessions' do |tracked|
    it "keeps the intervening device and the resumed device with #{tracked ? 'tracked' : 'untracked'} points" do
      tracks = if tracked
                 [0, 1, 2].map do |day|
                   create(:track, user:, start_at: trip.started_at + day.days,
                                  end_at: trip.started_at + day.days + 10.minutes)
                 end
               else
                 [nil, nil, nil]
               end
      first = [recording('phone', 0, 13, track: tracks[0]),
               recording('phone', 300, 13.01, track: tracks[0]),
               recording('phone', 600, 13.02, track: tracks[0])]
      middle = [recording('watch', 1.day.to_i, 13.03, track: tracks[1]),
                recording('watch', 1.day.to_i + 300, 13.04, track: tracks[1])]
      last = [recording('phone', 2.days.to_i, 13.05, track: tracks[2]),
              recording('phone', 2.days.to_i + 300, 13.06, track: tracks[2]),
              recording('phone', 2.days.to_i + 600, 13.07, track: tracks[2])]
      expected = first + middle + last

      trip.calculate_path
      trip.calculate_distance

      expect(trip.primary_device_points.pluck(:id)).to eq(expected.map(&:id))
      expect(trip.path.points.map(&:x)).to eq(expected.map(&:lon))
      expect(trip.distance).to be_within(1).of(Point.total_distance(expected, :m))
      expect(trip.day_stats('UTC').keys).to contain_exactly(Date.new(2026, 1, 1), Date.new(2026, 1, 2),
                                                            Date.new(2026, 1, 3))
      expect(trip.primary_device_windows.pluck(:tracker_id)).to eq(%w[phone watch phone])
    end
  end

  include_examples 'preserved recording sessions', false
  include_examples 'preserved recording sessions', true

  it 'splits only gaps beyond the configured threshold and keeps overlapping device priorities' do
    phone = [recording('phone', 0, 13), recording('phone', 600, 13.01),
             recording('phone', 1201, 13.03), recording('phone', 1801, 13.04)]
    recording('watch', 300, 14)
    gap = recording('watch', 900, 13.02)
    recording('watch', 1500, 14.01)

    expect(trip.primary_device_points.pluck(:id)).to eq([phone[0].id, phone[1].id, gap.id, phone[2].id, phone[3].id])
    expected_windows = [
      { tracker_id: 'phone', start_at: phone[0].timestamp, end_at: phone[1].timestamp },
      { tracker_id: 'watch', start_at: phone[1].timestamp + 1, end_at: phone[2].timestamp - 1 },
      { tracker_id: 'phone', start_at: phone[2].timestamp, end_at: phone[3].timestamp }
    ]
    expect(trip.primary_device_windows).to eq(expected_windows)
  end

  it 'ranks overlapping sessions by the device total across the trip' do
    first = [recording('phone', 0, 13), recording('phone', 600, 13.01)]
    last = [recording('phone', 1.day.to_i, 13.02), recording('phone', 1.day.to_i + 300, 13.03)]
    [100, 200, 300].each { |seconds| recording('watch', seconds, 14) }

    expect(trip.primary_device_points.pluck(:id)).to eq((first + last).map(&:id))
  end

  it 'keeps every recording when only one device has points' do
    expected = [recording('phone', 0, 13), recording('phone', 1.day.to_i, 13.01)]

    expect(trip.primary_device_points.pluck(:id)).to eq(expected.map(&:id))
  end

  it 'selects recording sessions without instantiating points' do
    recording('phone', 0, 13)
    recording('phone', 2.days.to_i, 13.02)
    middle = recording('watch', 1.day.to_i, 13.01)
    loaded = []
    subscriber = ->(*, payload) { loaded << payload[:name] if payload[:name] == 'Point Load' }

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      expect(trip.primary_device_points.pluck(:id)).to include(middle.id)
    end

    expect(loaded).to be_empty
  end
end
