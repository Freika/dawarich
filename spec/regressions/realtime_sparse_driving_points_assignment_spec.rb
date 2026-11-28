# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Track assignment for sparsely sampled real-time driving points' do
  include ActiveSupport::Testing::TimeHelpers

  let(:base_time) { Time.zone.local(2026, 10, 14, 9) }
  let(:user) do
    create(:user, settings: {
             'minutes_between_routes' => 30,
             'meters_between_routes' => 500,
             'gps_filtering_enabled' => true
           })
  end
  let(:samples) do
    # Made-up coordinates in the South Pacific, far from residential locations.
    # A close starting pair, 33 driving samples about 1 km apart, and a close
    # ending pair. The ending pair starts 33m55s after the first track ends.
    [[0, -140.0], [54, -139.9987]] +
      33.times.map { |i| [274 + i * 55, -139.9974 + i * 0.0127] } +
      [[2089, -139.9974 + 33 * 0.0127], [2095, -139.995 + 33 * 0.0127]]
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    expect(ExceptionReporter).not_to receive(:call)

    samples.each_with_index do |(offset, longitude), index|
      travel_to(base_time + offset)
      payload = {
        timestamp: (base_time + offset).to_i,
        lonlat: "POINT(#{longitude} -45)",
        tracker_id: 'synthetic-sparse-drive', accuracy: 5, velocity: 65,
        anomaly: nil, raw_data: {}
      }
      Points::Intake.call(user_id: user.id, payloads: [payload])
      Points::AnomalyFilterJob.perform_now(user.id, (base_time + offset).to_i, (base_time + offset).to_i)

      # Run the real debounced job after each sample has had 45 seconds to
      # settle. The final pair arrives only six seconds apart, in one debounce.
      next if index == 0 || index == samples.size - 2

      travel_to(base_time + offset + 45.seconds)
      Tracks::RealtimeGenerationJob.perform_now(user.id)
    end

    expect(user.points.count).to eq(37)
    expect(user.points.where(anomaly: true)).not_to exist
    expect(user.points.order(:timestamp).first.track_id).to be_present
    expect(user.points.order(:timestamp).last.track_id).to be_present
  end

  after do
    travel_back
    Tracks::RealtimeDebouncer.new(user.id).clear
    Visits::RealtimeDebouncer.new(user.id).clear
  end

  it 'assigns valid driving samples even when consecutive distances exceed 500 metres' do
    expect(user.points.where(track_id: nil).count).to eq(0)
  end

  it 'keeps all driving samples assigned after catch-up and lookback expiry' do
    travel_to(base_time + 3.hours)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    perform_enqueued_jobs do
      Tracks::DailyGenerationJob.perform_now
    end

    travel_to(base_time + 9.hours)
    Tracks::RealtimeGenerationJob.perform_now(user.id)

    expect(user.points.where(track_id: nil).count).to eq(0)
  end
end
