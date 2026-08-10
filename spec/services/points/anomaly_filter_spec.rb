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
  end
end
