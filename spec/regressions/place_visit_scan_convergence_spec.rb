# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::Visits::Create do
  let(:user) { create(:user) }
  let!(:place) { create(:place, user: user, latitude: 54.2905245, longitude: 13.0948638) }
  let(:base_ts) { Time.utc(2024, 5, 1, 12, 0, 0).to_i }

  def run
    described_class.new(user, user.reload.places, throttle_seconds: 0).call
  end

  def near_point(timestamp, seq:, **attrs)
    lon = 13.0948638 + (seq * 0.00001)
    lat = 54.2905245 + (seq * 0.00001)
    create(:point, user: user, latitude: lat, longitude: lon,
                   lonlat: "POINT(#{lon} #{lat})", timestamp: timestamp, **attrs)
  end

  def count_point_load_queries
    count = 0
    sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
      sql = args.last[:sql].to_s.downcase
      count += 1 if sql.match?(/from "points".*order by "points"\."timestamp"/)
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  it 'does not reload month points for a place whose nearby points never formed a visit' do
    near_point(base_ts, seq: 1)
    near_point(base_ts + 5.minutes, seq: 2)
    run # points span only 5 minutes, so no visit is created and no point is visited

    expect(Point.where(user_id: user.id).where.not(visit_id: nil)).to be_empty

    queries = count_point_load_queries { run }

    expect(queries).to eq(0)
  end
end
