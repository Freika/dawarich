# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::AnomalyFilter do
  let(:user) { create(:user) }
  let(:start_time) { 1.hour.ago.to_i }
  let(:end_time) { Time.current.to_i }

  describe '#call' do
    it 'bumps updated_at when flagging an anomaly so cached point reads invalidate' do
      point = create(:point, user: user, accuracy: 50_000, timestamp: 30.minutes.ago.to_i,
                             latitude: 52.52, longitude: 13.405, lonlat: 'POINT(13.405 52.52)')
      point.update_column(:updated_at, 2.days.ago)
      before_updated = point.reload.updated_at

      described_class.new(user.id, start_time, end_time).call

      expect(point.reload.anomaly).to be true
      expect(point.updated_at).to be > before_updated
    end

    # A reported accuracy radius is a confidence estimate, not evidence that the
    # position is wrong. Google Timeline routinely reports 1-4km while the point
    # still sits on the road, and deleting those points replaces real route
    # geometry with a straight line across the gap. Only absurd radii — larger
    # than any plausible positioning error — are treated as anomalies.
    context 'Pass 1: absurd accuracy filter' do
      # Use nearby coordinates so Pass 2 speed filter does not interfere
      let(:base_lat) { 52.52 }
      let(:base_lon) { 13.405 }

      let!(:good_point) do
        create(:point, user: user, accuracy: 15, timestamp: 30.minutes.ago.to_i,
               latitude: base_lat, longitude: base_lon,
               lonlat: "POINT(#{base_lon} #{base_lat})")
      end
      let!(:coarse_but_usable) do
        create(:point, user: user, accuracy: 3_000, timestamp: 29.minutes.ago.to_i,
               latitude: base_lat + 0.0001, longitude: base_lon + 0.0001,
               lonlat: "POINT(#{base_lon + 0.0001} #{base_lat + 0.0001})")
      end
      let!(:no_accuracy) do
        create(:point, user: user, accuracy: nil, timestamp: 28.minutes.ago.to_i,
               latitude: base_lat + 0.0002, longitude: base_lon + 0.0002,
               lonlat: "POINT(#{base_lon + 0.0002} #{base_lat + 0.0002})")
      end
      let!(:just_over_old_threshold) do
        create(:point, user: user, accuracy: 101, timestamp: 27.minutes.ago.to_i,
               latitude: base_lat + 0.0003, longitude: base_lon + 0.0003,
               lonlat: "POINT(#{base_lon + 0.0003} #{base_lat + 0.0003})")
      end
      let!(:absurd_accuracy) do
        create(:point, user: user, accuracy: 20_000, timestamp: 26.minutes.ago.to_i,
               latitude: base_lat + 0.0004, longitude: base_lon + 0.0004,
               lonlat: "POINT(#{base_lon + 0.0004} #{base_lat + 0.0004})")
      end

      before { described_class.new(user.id, start_time, end_time).call }

      it 'marks points whose accuracy radius is absurd' do
        expect(absurd_accuracy.reload.anomaly).to be true
      end

      it 'keeps coarse but usable points so route geometry survives' do
        expect(coarse_but_usable.reload.anomaly).not_to be true
        expect(just_over_old_threshold.reload.anomaly).not_to be true
      end

      it 'keeps precise points' do
        expect(good_point.reload.anomaly).not_to be true
      end

      it 'does not mark points with nil accuracy' do
        expect(no_accuracy.reload.anomaly).not_to be true
      end
    end

    # Regression for the real failure: a drive whose shape comes entirely from
    # coarse Google Timeline points. Dropping them left an 78km straight line
    # between the two precise endpoints.
    context 'Pass 1: a drive whose intermediate points are all coarse' do
      let(:base_time) { 40.minutes.ago.to_i }

      let!(:drive) do
        # ~0.05 degrees north per step, 5 minutes apart: roughly 65 km/h.
        (0..6).map do |i|
          create(:point, user: user, tracker_id: 'google-maps-timeline-export',
                         accuracy: i.zero? || i == 6 ? 20 : 3_000,
                         timestamp: base_time + (i * 300),
                         lonlat: "POINT(13.24 #{52.76 + (i * 0.05)})")
        end
      end

      before { described_class.new(user.id, 1.hour.ago.to_i, Time.current.to_i).call }

      it 'keeps every point of the drive so the route keeps its shape' do
        drive.each { |point| expect(point.reload.anomaly).not_to be true }
      end
    end

    context 'Pass 2: speed-based sandwich test' do
      let(:base_time) { 30.minutes.ago.to_i }
      let(:base_lat) { 52.52 }
      let(:base_lon) { 13.405 }

      # Normal walking points ~10m apart, 60s intervals
      let!(:p1) do
        create(:point, user: user, latitude: base_lat, longitude: base_lon,
               lonlat: "POINT(#{base_lon} #{base_lat})",
               timestamp: base_time, accuracy: 10)
      end
      let!(:p2) do
        create(:point, user: user, latitude: base_lat + 0.0001, longitude: base_lon + 0.0001,
               lonlat: "POINT(#{base_lon + 0.0001} #{base_lat + 0.0001})",
               timestamp: base_time + 60, accuracy: 10)
      end
      # Teleportation spike: 10 degrees away (>1000km) but only 60 seconds later
      let!(:spike) do
        create(:point, user: user, latitude: base_lat + 10.0, longitude: base_lon + 10.0,
               lonlat: "POINT(#{base_lon + 10.0} #{base_lat + 10.0})",
               timestamp: base_time + 120, accuracy: 10)
      end
      let!(:p4) do
        create(:point, user: user, latitude: base_lat + 0.0002, longitude: base_lon + 0.0002,
               lonlat: "POINT(#{base_lon + 0.0002} #{base_lat + 0.0002})",
               timestamp: base_time + 180, accuracy: 10)
      end
      let!(:p5) do
        create(:point, user: user, latitude: base_lat + 0.0003, longitude: base_lon + 0.0003,
               lonlat: "POINT(#{base_lon + 0.0003} #{base_lat + 0.0003})",
               timestamp: base_time + 240, accuracy: 10)
      end

      before { described_class.new(user.id, start_time, end_time).call }

      it 'marks the teleportation spike as anomaly' do
        expect(spike.reload.anomaly).to be true
      end

      it 'does not mark normal points as anomaly' do
        expect(p1.reload.anomaly).not_to be true
        expect(p2.reload.anomaly).not_to be true
        expect(p4.reload.anomaly).not_to be true
        expect(p5.reload.anomaly).not_to be true
      end
    end

    context 'Pass 2: outlier adjacent to a same-timestamp point from another device' do
      let(:base_time) { 30.minutes.ago.to_i }
      let(:base_lat) { 52.52 }
      let(:base_lon) { 13.405 }

      # Declared first so it sorts ahead of the outlier under (timestamp, id):
      # it becomes the outlier's predecessor in a globally ordered stream.
      let!(:other_device_point) do
        create(:point, user: user, tracker_id: 'phone', accuracy: 10,
                       timestamp: base_time + 120,
                       lonlat: "POINT(#{base_lon} #{base_lat})")
      end
      let!(:before_point) do
        create(:point, user: user, tracker_id: 'web', accuracy: 10,
                       timestamp: base_time,
                       lonlat: "POINT(#{base_lon} #{base_lat})")
      end
      let!(:spike) do
        create(:point, user: user, tracker_id: 'web', accuracy: 10,
                       timestamp: base_time + 120,
                       lonlat: "POINT(#{base_lon + 10.0} #{base_lat + 10.0})")
      end
      let!(:after_point) do
        create(:point, user: user, tracker_id: 'web', accuracy: 10,
                       timestamp: base_time + 240,
                       lonlat: "POINT(#{base_lon + 0.0002} #{base_lat + 0.0002})")
      end

      before { described_class.new(user.id, start_time, end_time).call }

      it 'still marks the spike even though its neighbour shares a timestamp' do
        expect(spike.reload.anomaly).to be true
      end

      it 'leaves the other device untouched' do
        expect(other_device_point.reload.anomaly).not_to be true
        expect(before_point.reload.anomaly).not_to be true
        expect(after_point.reload.anomaly).not_to be true
      end
    end

    context 'Pass 2: same-device outlier sharing a timestamp with a good point' do
      let(:base_time) { 30.minutes.ago.to_i }
      let(:base_lat) { 52.52 }
      let(:base_lon) { 13.405 }

      # The spike is declared first so it takes the LOWER id of the tied pair:
      # under (timestamp, id) it precedes the good point, the opposite tie
      # order from the cross-device context above. Both orders must resolve
      # the same way — only the spike is convicted.
      let!(:spike) do
        create(:point, user: user, tracker_id: 'phone', accuracy: 10,
                       timestamp: base_time + 120,
                       lonlat: "POINT(#{base_lon + 10.0} #{base_lat + 10.0})")
      end
      let!(:tied_good) do
        create(:point, user: user, tracker_id: 'phone', accuracy: 10,
                       timestamp: base_time + 120,
                       lonlat: "POINT(#{base_lon + 0.0001} #{base_lat + 0.0001})")
      end
      let!(:before_point) do
        create(:point, user: user, tracker_id: 'phone', accuracy: 10,
                       timestamp: base_time,
                       lonlat: "POINT(#{base_lon} #{base_lat})")
      end
      let!(:after_point) do
        create(:point, user: user, tracker_id: 'phone', accuracy: 10,
                       timestamp: base_time + 240,
                       lonlat: "POINT(#{base_lon + 0.0002} #{base_lat + 0.0002})")
      end

      before { described_class.new(user.id, start_time, end_time).call }

      it 'marks only the spike as anomaly' do
        expect(spike.reload.anomaly).to be true
      end

      it 'keeps the good point that shares the spike timestamp' do
        expect(tied_good.reload.anomaly).not_to be true
        expect(before_point.reload.anomaly).not_to be true
        expect(after_point.reload.anomaly).not_to be true
      end
    end

    context 'Pass 2: a run of consecutive displaced points' do
      let(:base_time) { 30.minutes.ago.to_i }
      let(:base_lat) { 52.52 }
      let(:base_lon) { 13.405 }

      let!(:p1) do
        create(:point, user: user, accuracy: 10, timestamp: base_time,
                       lonlat: "POINT(#{base_lon} #{base_lat})")
      end
      let!(:p2) do
        create(:point, user: user, accuracy: 10, timestamp: base_time + 60,
                       lonlat: "POINT(#{base_lon + 0.0001} #{base_lat + 0.0001})")
      end
      # Two displaced points close to each other: the speed *between* them is
      # normal, so neither has both an extreme incoming and outgoing speed.
      let!(:displaced_a) do
        create(:point, user: user, accuracy: 10, timestamp: base_time + 120,
                       lonlat: "POINT(#{base_lon + 10.0} #{base_lat + 10.0})")
      end
      let!(:displaced_b) do
        create(:point, user: user, accuracy: 10, timestamp: base_time + 180,
                       lonlat: "POINT(#{base_lon + 10.0001} #{base_lat + 10.0001})")
      end
      let!(:p5) do
        create(:point, user: user, accuracy: 10, timestamp: base_time + 240,
                       lonlat: "POINT(#{base_lon + 0.0002} #{base_lat + 0.0002})")
      end
      let!(:p6) do
        create(:point, user: user, accuracy: 10, timestamp: base_time + 300,
                       lonlat: "POINT(#{base_lon + 0.0003} #{base_lat + 0.0003})")
      end

      before { described_class.new(user.id, start_time, end_time).call }

      it 'marks every point in the displaced run' do
        expect(displaced_a.reload.anomaly).to be true
        expect(displaced_b.reload.anomaly).to be true
      end

      it 'leaves the surrounding real points alone' do
        [p1, p2, p5, p6].each { |point| expect(point.reload.anomaly).not_to be true }
      end
    end

    # A real stay can be bracketed by two impossible hops when the surrounding
    # data is sparse or a second device is interleaved. Convicting the whole run
    # on its boundaries alone would erase genuine history, so run length is
    # bounded: noise is a brief excursion, a stay is a long one.
    context 'Pass 2: a long genuine stay bracketed by impossible hops' do
      let(:start_time) { 8.hours.ago.to_i }
      let(:end_time) { Time.current.to_i }
      let(:base_time) { 7.hours.ago.to_i }
      let(:base_lat) { 52.52 }
      let(:base_lon) { 13.405 }

      let!(:home_before) do
        [0, 1].map do |i|
          create(:point, user: user, accuracy: 10, timestamp: base_time + (i * 60),
                         lonlat: "POINT(#{base_lon + (i * 0.0001)} #{base_lat + (i * 0.0001)})")
        end
      end
      # 12 points clustered ~800km away, minutes apart: an implausible jump to
      # get there, but unmistakably a real visit once there.
      let!(:stay) do
        (0..11).map do |i|
          create(:point, user: user, accuracy: 10, timestamp: base_time + 120 + (i * 60),
                         lonlat: "POINT(#{4.35 + (i * 0.0001)} #{50.85 + (i * 0.0001)})")
        end
      end
      let!(:home_after) do
        [0, 1].map do |i|
          create(:point, user: user, accuracy: 10, timestamp: base_time + 900 + (i * 60),
                         lonlat: "POINT(#{base_lon + (i * 0.0001)} #{base_lat + (i * 0.0001)})")
        end
      end

      before { described_class.new(user.id, start_time, end_time).call }

      it 'does not erase the stay' do
        stay.each { |point| expect(point.reload.anomaly).not_to be true }
      end

      it 'leaves the home points alone' do
        (home_before + home_after).each { |point| expect(point.reload.anomaly).not_to be true }
      end
    end

    # The real shape of a stale cached position: it jumps hundreds of km away
    # and comes straight back. Only the arrival is impossibly fast — the return
    # leg looks merely plane-like — so a test requiring both sides to be extreme
    # lets it through, and the round trip lands in the track as a phantom flight.
    context 'Pass 2: an out-and-back excursion with only one impossible leg' do
      let(:base_time) { 40.minutes.ago.to_i }
      # Two coast positions ~30km apart, with a stale Berlin fix wedged between.
      let(:coast_a) { 'POINT(12.247 54.176)' }
      let(:coast_b) { 'POINT(12.541 54.392)' }
      let(:stale_berlin) { 'POINT(13.517 52.532)' }

      let!(:before_a) do
        create(:point, user: user, accuracy: 5, timestamp: base_time, lonlat: coast_a)
      end
      let!(:before_b) do
        create(:point, user: user, accuracy: 5, timestamp: base_time + 60, lonlat: coast_a)
      end
      # 218km away in 300s -> ~2600 km/h arriving: impossible.
      let!(:spike) do
        create(:point, user: user, accuracy: 100, timestamp: base_time + 360, lonlat: stale_berlin)
      end
      # 217km back in 900s -> ~868 km/h leaving: plausible for a plane, so the
      # two-sided test never fires.
      let!(:after_a) do
        create(:point, user: user, accuracy: 20, timestamp: base_time + 1260, lonlat: coast_b)
      end
      let!(:after_b) do
        create(:point, user: user, accuracy: 20, timestamp: base_time + 1320, lonlat: coast_b)
      end

      before { described_class.new(user.id, 1.hour.ago.to_i, Time.current.to_i).call }

      it 'flags the excursion' do
        expect(spike.reload.anomaly).to be true
      end

      it 'leaves the surrounding real positions alone' do
        [before_a, before_b, after_a, after_b].each do |point|
          expect(point.reload.anomaly).not_to be true
        end
      end
    end

    # Google splices a stale fix from another device into a phone's timelinePath.
    # Each leg on its own looks like air travel, so nothing exceeds the raw speed
    # floor — but the round trip demands hundreds of km of travel that never
    # happened, which is what the detour test is for.
    context 'Pass 2: a detour no ground travel could cover' do
      let(:base_time) { 40.minutes.ago.to_i }

      let!(:before_a) do
        create(:point, user: user, accuracy: 5, timestamp: base_time, lonlat: 'POINT(10.5526 52.9697)')
      end
      let!(:before_b) do
        create(:point, user: user, accuracy: 5, timestamp: base_time + 480, lonlat: 'POINT(10.4417 52.9117)')
      end
      # 214km away in 27min (~476 km/h), then 257km on in 15min (~1028 km/h).
      let!(:spliced_home) do
        create(:point, user: user, accuracy: 5, timestamp: base_time + 2100, lonlat: 'POINT(13.5162 52.4546)')
      end
      let!(:after_a) do
        create(:point, user: user, accuracy: 5, timestamp: base_time + 3000, lonlat: 'POINT(9.7419 52.3775)')
      end
      let!(:after_b) do
        create(:point, user: user, accuracy: 5, timestamp: base_time + 3300, lonlat: 'POINT(9.7420 52.3776)')
      end

      before { described_class.new(user.id, 2.hours.ago.to_i, Time.current.to_i).call }

      it 'flags the spliced fix' do
        expect(spliced_home.reload.anomaly).to be true
      end

      it 'keeps the real journey either side' do
        [before_a, before_b, after_a, after_b].each do |point|
          expect(point.reload.anomaly).not_to be true
        end
      end
    end

    # A stale fix can land in the middle of a stay somewhere else, hours from any
    # other reading. Over a long enough gap the round trip is physically possible,
    # so no speed test can condemn it — but spending zero time at the far end and
    # returning to the same stay is not travel.
    context 'Pass 2: a fix that contradicts a stay' do
      let(:evening) { Time.zone.parse('2022-12-03 20:16').to_i }
      let(:hannover) { 'POINT(9.806 52.310)' }
      let(:home) { 'POINT(13.516 52.455)' }

      let!(:stay_before) do
        create(:point, user: user, accuracy: 5, timestamp: evening, lonlat: hannover)
      end
      let!(:stale_home) do
        create(:point, user: user, accuracy: 5, timestamp: evening + 45_540, lonlat: home)
      end
      let!(:stay_after) do
        create(:point, user: user, accuracy: 5, timestamp: evening + 48_420, lonlat: hannover)
      end
      let!(:stay_after_b) do
        create(:point, user: user, accuracy: 5, timestamp: evening + 48_480, lonlat: hannover)
      end

      before { described_class.new(user.id, evening - 3600, evening + 90_000).call }

      it 'flags the fix that interrupts the stay' do
        expect(stale_home.reload.anomaly).to be true
      end

      it 'keeps the stay itself' do
        [stay_before, stay_after, stay_after_b].each do |point|
          expect(point.reload.anomaly).not_to be true
        end
      end
    end

    context 'Pass 2: a real trip away from a stay and back' do
      let(:start) { Time.zone.parse('2022-12-03 08:00').to_i }
      let(:home) { 'POINT(13.405 52.520)' }
      let(:away) { 'POINT(11.576 48.137)' }

      let!(:home_before) do
        create(:point, user: user, accuracy: 5, timestamp: start, lonlat: home)
      end
      # Four hours of points at the destination: a real visit, not a stray fix.
      let!(:visit) do
        [0, 3600, 7200, 14_400].map do |offset|
          create(:point, user: user, accuracy: 5, timestamp: start + 7200 + offset, lonlat: away)
        end
      end
      let!(:home_after) do
        create(:point, user: user, accuracy: 5, timestamp: start + 36_000, lonlat: home)
      end

      before { described_class.new(user.id, start - 3600, start + 90_000).call }

      it 'keeps the whole trip' do
        ([home_before] + visit + [home_after]).each do |point|
          expect(point.reload.anomaly).not_to be true
        end
      end
    end

    context 'Pass 2: genuine long-distance travel' do
      let(:start_time) { 8.hours.ago.to_i }
      let(:end_time) { Time.current.to_i }
      let(:base_time) { 7.hours.ago.to_i }
      let(:base_lat) { 52.52 }
      let(:base_lon) { 13.405 }

      let!(:origin_a) do
        create(:point, user: user, accuracy: 10, timestamp: base_time,
                       lonlat: "POINT(#{base_lon} #{base_lat})")
      end
      let!(:origin_b) do
        create(:point, user: user, accuracy: 10, timestamp: base_time + 60,
                       lonlat: "POINT(#{base_lon + 0.0001} #{base_lat + 0.0001})")
      end
      # ~1650km south-west over 3 hours ≈ 550 km/h: a real flight, comfortably
      # under the 1000 km/h floor, and the traveller then stays put.
      let!(:arrival_a) do
        create(:point, user: user, accuracy: 10, timestamp: base_time + (3 * 3600),
                       lonlat: 'POINT(2.3522 48.8566)')
      end
      let!(:arrival_b) do
        create(:point, user: user, accuracy: 10, timestamp: base_time + (3 * 3600) + 600,
                       lonlat: 'POINT(2.3523 48.8567)')
      end
      let!(:arrival_c) do
        create(:point, user: user, accuracy: 10, timestamp: base_time + (4 * 3600),
                       lonlat: 'POINT(2.3524 48.8568)')
      end

      before { described_class.new(user.id, start_time, end_time).call }

      it 'does not flag the flight or the destination points' do
        [origin_a, origin_b, arrival_a, arrival_b, arrival_c].each do |point|
          expect(point.reload.anomaly).not_to be true
        end
      end
    end

    context 'Pass 2: same-timestamp points' do
      let!(:p1) do
        create(:point, user: user, latitude: 52.52, longitude: 13.405,
               lonlat: 'POINT(13.405 52.52)', timestamp: 30.minutes.ago.to_i)
      end
      let!(:p2) do
        create(:point, user: user, latitude: 52.521, longitude: 13.406,
               lonlat: 'POINT(13.406 52.521)', timestamp: 30.minutes.ago.to_i)
      end

      it 'does not raise on zero time difference' do
        expect { described_class.new(user.id, start_time, end_time).call }.not_to raise_error
      end
    end

    context 'with fewer than 3 points' do
      let!(:p1) do
        create(:point, user: user, latitude: 52.52, longitude: 13.405,
               lonlat: 'POINT(13.405 52.52)', timestamp: 30.minutes.ago.to_i)
      end

      it 'does not raise and returns 0' do
        result = described_class.new(user.id, start_time, end_time).call
        expect(result).to eq(0)
        expect(p1.reload.anomaly).not_to be true
      end
    end

    context 'returns count of marked anomalies' do
      let!(:bad) { create(:point, user: user, accuracy: 50_000, timestamp: 30.minutes.ago.to_i) }
      let!(:good) { create(:point, user: user, accuracy: 10, timestamp: 29.minutes.ago.to_i) }

      it 'returns the total count of anomalies marked' do
        result = described_class.new(user.id, start_time, end_time).call
        expect(result).to eq(1)
      end
    end

    context 'when user disables GPS filtering' do
      let(:user) { create(:user, settings: { 'gps_filtering_enabled' => false }) }
      let!(:terrible) { create(:point, user: user, accuracy: 5000, timestamp: 30.minutes.ago.to_i) }

      it 'returns 0 and leaves points untouched' do
        expect(described_class.new(user.id, start_time, end_time).call).to eq(0)
        expect(terrible.reload.anomaly).not_to be true
      end
    end

    # gps_accuracy_threshold no longer gates flagging: a coarse radius is not
    # evidence of a wrong position, and honouring a 100-1000m threshold deleted
    # the coarse points that carry route shape. The setting is still accepted by
    # the settings API but no longer affects which points are flagged.
    context 'when the user has set an accuracy threshold' do
      let(:user) { create(:user, settings: { 'gps_accuracy_threshold' => 500 }) }
      let!(:above_user_threshold) do
        create(:point, user: user, accuracy: 600, timestamp: 30.minutes.ago.to_i,
               latitude: 52.52, longitude: 13.405, lonlat: 'POINT(13.405 52.52)')
      end
      let!(:absurd) do
        create(:point, user: user, accuracy: 40_000, timestamp: 29.minutes.ago.to_i,
               latitude: 52.5201, longitude: 13.4051, lonlat: 'POINT(13.4051 52.5201)')
      end

      before { described_class.new(user.id, start_time, end_time).call }

      it 'keeps coarse points regardless of the threshold' do
        expect(above_user_threshold.reload.anomaly).not_to be true
      end

      it 'still flags absurd radii' do
        expect(absurd.reload.anomaly).to be true
      end
    end

    context 'Pass 2: narrow realtime window does not rescan the whole month' do
      let(:base_lat) { 52.52 }
      let(:base_lon) { 13.405 }
      let(:month_start) { Time.current.beginning_of_month }
      let(:early_base) { (month_start + 2.days).to_i }
      let(:late_base) { (month_start + 20.days).to_i }

      def normal_point(timestamp)
        create(:point, user: user, latitude: base_lat, longitude: base_lon,
               lonlat: "POINT(#{base_lon} #{base_lat})", timestamp: timestamp, accuracy: 10)
      end

      def spike_point(timestamp)
        create(:point, user: user, latitude: base_lat + 10.0, longitude: base_lon + 10.0,
               lonlat: "POINT(#{base_lon + 10.0} #{base_lat + 10.0})", timestamp: timestamp, accuracy: 10)
      end

      let!(:early_before) { normal_point(early_base) }
      let!(:early_spike)  { spike_point(early_base + 60) }
      let!(:early_after)  { normal_point(early_base + 120) }

      let!(:late_before) { normal_point(late_base) }
      let!(:late_spike)  { spike_point(late_base + 60) }
      let!(:late_after)  { normal_point(late_base + 120) }

      before { described_class.new(user.id, late_spike.timestamp, late_spike.timestamp).call }

      it 'flags the spike inside the window using context points' do
        expect(late_spike.reload.anomaly).to be true
      end

      it 'leaves an earlier spike outside the window untouched' do
        expect(early_spike.reload.anomaly).not_to be true
      end
    end

    context 'Pass 3: Null Island (0,0)' do
      let(:start_time) { 2.hours.ago.to_i }
      let(:end_time) { Time.current.to_i }

      let!(:before_zero) do
        create(:point, user: user, latitude: 52.5, longitude: 13.4,
                       lonlat: 'POINT(13.4 52.5)', accuracy: 10, timestamp: 90.minutes.ago.to_i)
      end
      let!(:zero_run) do
        3.times.map do |i|
          create(:point, user: user, latitude: 0.0, longitude: 0.0,
                         lonlat: 'POINT(0.0 0.0)', accuracy: 10,
                         timestamp: (80 - (i * 10)).minutes.ago.to_i)
        end
      end
      let!(:after_zero) do
        create(:point, user: user, latitude: 52.5001, longitude: 13.4001,
                       lonlat: 'POINT(13.4001 52.5001)', accuracy: 10, timestamp: 40.minutes.ago.to_i)
      end

      before { described_class.new(user.id, start_time, end_time).call }

      it 'flags every point of a sustained (0,0) run' do
        expect(zero_run.map { |p| p.reload.anomaly }).to all(be(true))
      end

      it 'does not flag the surrounding real points' do
        expect(before_zero.reload.anomaly).not_to be true
        expect(after_zero.reload.anomaly).not_to be true
      end
    end

    # iOS visit monitoring (Overland `action: visit`) reports a stay after it
    # ended: the payload carries the visit centroid plus arrival and departure
    # dates, but the point is stamped with its delivery time — minutes after
    # departure, while the device is already moving away. The coordinate is
    # right, its place in the timeline is not, so the track leaps to the
    # centroid and back. No accuracy or speed gate can catch that.
    context 'Pass 4: departed visit reports' do
      let(:base_time) { 1.hour.ago.to_i }

      def walk_point(offset, lat, lon)
        create(:point, user: user, accuracy: 5, timestamp: base_time + offset,
               latitude: lat, longitude: lon, lonlat: "POINT(#{lon} #{lat})")
      end

      let!(:walk) do
        [walk_point(0, 51.3404, 12.3754),
         walk_point(60, 51.3400, 12.3747),
         walk_point(120, 51.3396, 12.3740)]
      end

      let!(:departed_report) do
        create(:point, user: user, accuracy: 4, timestamp: base_time + 90,
               latitude: 51.3418, longitude: 12.3790, lonlat: 'POINT(12.3790 51.3418)',
               motion_data: { 'action' => 'visit' },
               raw_data: { 'properties' => { 'action' => 'visit',
                                             'arrival_date' => '2026-05-19T18:27:54Z',
                                             'departure_date' => '2026-05-19T18:34:25Z' } })
      end

      let!(:arrival_report) do
        create(:point, user: user, accuracy: 30, timestamp: base_time + 150,
               latitude: 51.3395, longitude: 12.3739, lonlat: 'POINT(12.3739 51.3395)',
               motion_data: { 'action' => 'visit' },
               raw_data: { 'properties' => { 'action' => 'visit',
                                             'arrival_date' => '2026-05-19T18:27:54Z',
                                             'departure_date' => nil } })
      end

      let!(:archived_report) do
        create(:point, user: user, accuracy: 10, timestamp: base_time + 180,
               latitude: 51.3394, longitude: 12.3738, lonlat: 'POINT(12.3738 51.3394)',
               motion_data: { 'action' => 'visit' },
               raw_data: {}, raw_data_archived: true)
      end

      let!(:distant_future_report) do
        create(:point, user: user, accuracy: 20, timestamp: base_time + 210,
               latitude: 51.3393, longitude: 12.3737, lonlat: 'POINT(12.3737 51.3393)',
               motion_data: { 'action' => 'visit' },
               raw_data: { 'properties' => { 'action' => 'visit',
                                             'arrival_date' => '2026-05-19T18:27:54Z',
                                             'departure_date' => '4001-01-01T00:00:00Z' } })
      end

      let!(:archived_departed_report) do
        create(:point, user: user, accuracy: 12, timestamp: base_time + 240,
               latitude: 51.3392, longitude: 12.3736, lonlat: 'POINT(12.3736 51.3392)',
               motion_data: { 'action' => 'visit', 'departure_date' => '2026-05-19T18:34:25Z' },
               raw_data: {}, raw_data_archived: true)
      end

      let!(:departed_non_visit) do
        create(:point, user: user, accuracy: 8, timestamp: base_time + 270,
               latitude: 51.3391, longitude: 12.3735, lonlat: 'POINT(12.3735 51.3391)',
               motion_data: { 'motion' => ['walking'] },
               raw_data: { 'properties' => { 'departure_date' => '2026-05-19T18:34:25Z' } })
      end

      before { described_class.new(user.id, 2.hours.ago.to_i, Time.current.to_i).call }

      it 'flags a departed visit report despite its perfect accuracy' do
        expect(departed_report.reload.anomaly).to be true
      end

      it 'keeps an arrival report, which is delivered while the device is still there' do
        expect(arrival_report.reload.anomaly).not_to be true
      end

      it 'keeps a visit report whose raw payload was archived, since it cannot be classified' do
        expect(archived_report.reload.anomaly).not_to be true
      end

      it 'keeps a report whose departure date is the distant-future placeholder' do
        expect(distant_future_report.reload.anomaly).not_to be true
      end

      it 'flags a departed report after archival when motion_data kept the departure date' do
        expect(archived_departed_report.reload.anomaly).to be true
      end

      it 'keeps a non-visit point that happens to carry a departure date' do
        expect(departed_non_visit.reload.anomaly).not_to be true
      end

      it 'persists the departure date into motion_data when flagging' do
        expect(departed_report.reload.motion_data['departure_date']).to eq('2026-05-19T18:34:25Z')
      end

      it 'keeps the surrounding walk' do
        walk.each { |point| expect(point.reload.anomaly).not_to be true }
      end
    end

    # After a tracking gap the first fix often comes from cell towers with
    # every CoreLocation sentinel set: speed -1, vertical accuracy -1 and a
    # kilometre-scale radius. It lands wherever the tower is — far below the
    # absurd-accuracy gate, yet nowhere near the route.
    context 'Pass 5: cold-start sentinel fixes' do
      let(:base_time) { 1.hour.ago.to_i }

      let!(:cold_start) do
        create(:point, user: user, accuracy: 1414, velocity: '-1', vertical_accuracy: -1,
               timestamp: base_time, latitude: 51.3336, longitude: 12.3777,
               lonlat: 'POINT(12.3777 51.3336)')
      end

      let!(:stationary_invalid_speed) do
        create(:point, user: user, accuracy: 15, velocity: '-1', vertical_accuracy: -1,
               timestamp: base_time + 60, latitude: 51.3355, longitude: 12.3742,
               lonlat: 'POINT(12.3742 51.3355)')
      end

      let!(:coarse_with_valid_motion) do
        create(:point, user: user, accuracy: 1500, velocity: '2', vertical_accuracy: 5,
               timestamp: base_time + 120, latitude: 51.3356, longitude: 12.3743,
               lonlat: 'POINT(12.3743 51.3356)')
      end

      let!(:at_the_gate) do
        create(:point, user: user, accuracy: 500, velocity: '-1', vertical_accuracy: -1,
               timestamp: base_time + 180, latitude: 51.3357, longitude: 12.3744,
               lonlat: 'POINT(12.3744 51.3357)')
      end

      let!(:wifi_tier_sentinel) do
        create(:point, user: user, accuracy: 165, velocity: '-1', vertical_accuracy: -1,
               timestamp: base_time + 210, latitude: 51.3365, longitude: 12.3752,
               lonlat: 'POINT(12.3752 51.3365)')
      end

      let!(:no_vertical_reading) do
        create(:point, user: user, accuracy: 1500, velocity: '-1', vertical_accuracy: nil,
               timestamp: base_time + 240, latitude: 51.3358, longitude: 12.3745,
               lonlat: 'POINT(12.3745 51.3358)')
      end

      let!(:tower_run) do
        3.times.map do |i|
          create(:point, user: user, accuracy: 2000, velocity: '-1', vertical_accuracy: -1,
                 timestamp: base_time + 300 + (i * 60),
                 latitude: 51.3359 + (i * 0.0001), longitude: 12.3746 + (i * 0.0001),
                 lonlat: "POINT(#{12.3746 + (i * 0.0001)} #{51.3359 + (i * 0.0001)})")
        end
      end

      let!(:sentinel_without_accuracy) do
        create(:point, user: user, accuracy: nil, velocity: '-1', vertical_accuracy: -1,
               timestamp: base_time + 480, latitude: 51.3363, longitude: 12.3750,
               lonlat: 'POINT(12.3750 51.3363)')
      end

      let!(:negative_speed_with_altitude) do
        create(:point, user: user, accuracy: 1500, velocity: '-1', vertical_accuracy: 5,
               timestamp: base_time + 540, latitude: 51.3364, longitude: 12.3751,
               lonlat: 'POINT(12.3751 51.3364)')
      end

      before { described_class.new(user.id, 2.hours.ago.to_i, Time.current.to_i).call }

      it 'flags the coarse fix whose motion fields are all sentinels' do
        expect(cold_start.reload.anomaly).to be true
      end

      it 'keeps a sentinel fix whose radius is still tight' do
        expect(stationary_invalid_speed.reload.anomaly).not_to be true
      end

      it 'keeps a coarse fix that carries valid motion data' do
        expect(coarse_with_valid_motion.reload.anomaly).not_to be true
      end

      it 'keeps a sentinel fix exactly at the accuracy gate' do
        expect(at_the_gate.reload.anomaly).not_to be true
      end

      it 'keeps a wifi-tier sentinel fix, which is positionally usable' do
        expect(wifi_tier_sentinel.reload.anomaly).not_to be true
      end

      it 'keeps a coarse fix with no vertical accuracy reading at all' do
        expect(no_vertical_reading.reload.anomaly).not_to be true
      end

      it 'flags an entire run of tower fixes, not only the first' do
        expect(tower_run.map { |point| point.reload.anomaly }).to all(be(true))
      end

      it 'keeps a sentinel-shaped fix with no accuracy reading at all' do
        expect(sentinel_without_accuracy.reload.anomaly).not_to be true
      end

      it 'keeps a coarse negative-speed fix whose vertical accuracy is valid' do
        expect(negative_speed_with_altitude.reload.anomaly).not_to be true
      end
    end

    # Reduced-accuracy permission and significant-change tracking produce
    # nothing but coarse sentinel fixes. There the tower position is the only
    # record there is, and a pass that erased it would blank the whole map.
    context 'Pass 5: a history that is coarse all the way through' do
      let(:base_time) { 1.hour.ago.to_i }

      let!(:coarse_stream) do
        5.times.map do |i|
          create(:point, user: user, accuracy: 1800, velocity: '-1', vertical_accuracy: -1,
                 timestamp: base_time + (i * 300),
                 latitude: 51.34 + (i * 0.001), longitude: 12.37 + (i * 0.001),
                 lonlat: "POINT(#{12.37 + (i * 0.001)} #{51.34 + (i * 0.001)})")
        end
      end

      before { described_class.new(user.id, 2.hours.ago.to_i, Time.current.to_i).call }

      it 'keeps every fix, since nothing better was ever available' do
        coarse_stream.each { |point| expect(point.reload.anomaly).not_to be true }
      end
    end

    # A second device on reduced-accuracy permission is coarse all the way
    # through even when the account's other device tracks precisely. Each
    # device is its own stream — the same rule the speed pass applies.
    context 'Pass 5: a coarse-only device next to a precise one' do
      let(:base_time) { 1.hour.ago.to_i }

      let!(:precise_phone) do
        3.times.map do |i|
          create(:point, user: user, accuracy: 5, velocity: '1', vertical_accuracy: 5,
                 tracker_id: 'iphone', timestamp: base_time + (i * 60),
                 latitude: 51.3402 + (i * 0.0001), longitude: 12.3712,
                 lonlat: "POINT(12.3712 #{51.3402 + (i * 0.0001)})")
        end
      end

      let!(:coarse_watch) do
        3.times.map do |i|
          create(:point, user: user, accuracy: 1500, velocity: '-1', vertical_accuracy: -1,
                 tracker_id: 'watch', timestamp: base_time + 30 + (i * 60),
                 latitude: 51.3412 + (i * 0.001), longitude: 12.3722,
                 lonlat: "POINT(12.3722 #{51.3412 + (i * 0.001)})")
        end
      end

      before { described_class.new(user.id, 2.hours.ago.to_i, Time.current.to_i).call }

      it 'keeps the coarse device intact' do
        coarse_watch.each { |point| expect(point.reload.anomaly).not_to be true }
      end

      it 'leaves the precise device alone too' do
        precise_phone.each { |point| expect(point.reload.anomaly).not_to be true }
      end
    end

    context 'Pass 5: the only precise neighbour is itself an anomaly' do
      let(:base_time) { 1.hour.ago.to_i }

      let!(:flagged_neighbor) do
        create(:point, user: user, accuracy: 10, velocity: '1', vertical_accuracy: 5,
               timestamp: base_time, latitude: 51.3370, longitude: 12.3760,
               lonlat: 'POINT(12.3760 51.3370)', anomaly: true)
      end

      let!(:orphan_sentinel) do
        create(:point, user: user, accuracy: 1500, velocity: '-1', vertical_accuracy: -1,
               timestamp: base_time + 60, latitude: 51.3380, longitude: 12.3770,
               lonlat: 'POINT(12.3770 51.3380)')
      end

      before { described_class.new(user.id, 2.hours.ago.to_i, Time.current.to_i).call }

      it 'keeps the sentinel fix, since flagged points cannot justify more flags' do
        expect(orphan_sentinel.reload.anomaly).not_to be true
      end
    end

    # A point can be flagged after realtime generation already baked it into a
    # track: stored geometry and monthly distance keep the leap until both are
    # rebuilt, and recalculation reads track.points, which a stale track_id
    # would keep feeding.
    context 'a departed visit report already baked into a track' do
      let(:base_time) { 1.hour.ago.to_i }

      let!(:walk) do
        2.times.map do |i|
          create(:point, user: user, accuracy: 5, timestamp: base_time + (i * 60),
                 latitude: 51.3421 + (i * 0.0001), longitude: 12.3761,
                 lonlat: "POINT(12.3761 #{51.3421 + (i * 0.0001)})")
        end
      end

      let!(:baked_report) do
        create(:point, user: user, accuracy: 6, timestamp: base_time + 90,
               latitude: 51.3428, longitude: 12.3768, lonlat: 'POINT(12.3768 51.3428)',
               motion_data: { 'action' => 'visit' },
               raw_data: { 'properties' => { 'action' => 'visit',
                                             'departure_date' => '2026-05-19T18:34:25Z' } })
      end

      let!(:track) do
        create(:track, user: user,
               start_at: Time.zone.at(base_time), end_at: Time.zone.at(base_time + 120)).tap do |t|
          Point.where(id: walk.map(&:id) + [baked_report.id]).update_all(track_id: t.id)
        end
      end

      def run_filter(**options)
        described_class.new(user.id, 2.hours.ago.to_i, Time.current.to_i, **options).call
      end

      it 'detaches the flagged point from its track' do
        run_filter
        expect(baked_report.reload.track_id).to be_nil
      end

      it 'leaves the clean points attached' do
        run_filter
        walk.each { |point| expect(point.reload.track_id).to eq(track.id) }
      end

      it 'enqueues a recalculation for the affected track' do
        expect { run_filter }.to have_enqueued_job(Tracks::RecalculateJob).with(track.id)
      end

      it 'enqueues a stats refresh for the affected month' do
        time = Time.zone.at(baked_report.timestamp)

        expect { run_filter }
          .to have_enqueued_job(Stats::CalculatingJob).with(user.id, time.year, time.month)
      end

      it 'skips the dependent rebuilds when the caller rebuilds wholesale' do
        expect { run_filter(invalidate_dependents: false) }
          .not_to have_enqueued_job(Tracks::RecalculateJob)
      end

      it 'still flags and detaches the point when the rebuilds are skipped' do
        run_filter(invalidate_dependents: false)

        expect(baked_report.reload.anomaly).to be true
        expect(baked_report.track_id).to be_nil
      end
    end

    context 'both passes flag points in the same month' do
      let(:base_time) { 1.hour.ago.to_i }

      let!(:precise_context) do
        3.times.map do |i|
          create(:point, user: user, accuracy: 5, velocity: '1', vertical_accuracy: 5,
                 timestamp: base_time + (i * 60),
                 latitude: 51.3431 + (i * 0.0001), longitude: 12.3781,
                 lonlat: "POINT(12.3781 #{51.3431 + (i * 0.0001)})")
        end
      end

      let!(:departed_report) do
        create(:point, user: user, accuracy: 6, timestamp: base_time + 30,
               latitude: 51.3438, longitude: 12.3788, lonlat: 'POINT(12.3788 51.3438)',
               motion_data: { 'action' => 'visit' },
               raw_data: { 'properties' => { 'action' => 'visit',
                                             'departure_date' => '2026-05-19T18:34:25Z' } })
      end

      let!(:tower_fix) do
        create(:point, user: user, accuracy: 1500, velocity: '-1', vertical_accuracy: -1,
               timestamp: base_time + 90, latitude: 51.3448, longitude: 12.3798,
               lonlat: 'POINT(12.3798 51.3448)')
      end

      it 'enqueues one stats refresh for the shared month, not one per pass' do
        time = Time.zone.at(departed_report.timestamp)

        expect { described_class.new(user.id, 2.hours.ago.to_i, Time.current.to_i).call }
          .to have_enqueued_job(Stats::CalculatingJob)
          .with(user.id, time.year, time.month).exactly(:once)
      end
    end

    # At ingest each batch is filtered alone, and a wake-up tower fix often
    # arrives in a batch of one — its precise context only exists a few
    # minutes later, in the next batch, whose window starts after it.
    context 'Pass 5: a cold start that arrived in an earlier batch' do
      let(:base_time) { 1.hour.ago.to_i }

      let!(:earlier_tower_fix) do
        create(:point, user: user, accuracy: 1500, velocity: '-1', vertical_accuracy: -1,
               timestamp: base_time, latitude: 51.3350, longitude: 12.3730,
               lonlat: 'POINT(12.3730 51.3350)')
      end

      let!(:later_precise) do
        3.times.map do |i|
          create(:point, user: user, accuracy: 8, velocity: '1', vertical_accuracy: 5,
                 timestamp: base_time + 300 + (i * 60),
                 latitude: 51.3352 + (i * 0.0001), longitude: 12.3732,
                 lonlat: "POINT(12.3732 #{51.3352 + (i * 0.0001)})")
        end
      end

      before { described_class.new(user.id, base_time + 300, Time.current.to_i).call }

      it 'flags the fix even though it predates the window' do
        expect(earlier_tower_fix.reload.anomaly).to be true
      end

      it 'leaves the precise batch alone' do
        later_precise.each { |point| expect(point.reload.anomaly).not_to be true }
      end
    end
  end
end
