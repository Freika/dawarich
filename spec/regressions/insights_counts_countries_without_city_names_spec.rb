# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Insights counts imported countries without city names', :non_transactional do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, settings: { 'timezone' => 'Etc/UTC', 'min_minutes_spent_in_city' => 60 })
  end
  let(:import) { create(:import, user: user, name: 'Records.json') }

  before do
    existing_setting_ids = InstanceSetting.pluck(:id)
    configure_instance_geocoding
    @geocoding_setting_ids = InstanceSetting.pluck(:id) - existing_setting_ids
    allow(Geocoder).to receive(:search).and_return(
      [double(city: nil, country: 'Synthetic Republic', data: {})]
    )
    clear_geocoded_days
    clear_refresh_cursors
  end

  after do
    user.destroy!
    InstanceSetting.where(id: @geocoding_setting_ids).delete_all
    clear_enqueued_jobs
    clear_geocoded_days
    clear_refresh_cursors
  end

  def clear_refresh_cursors
    Sidekiq.redis do |redis|
      redis.del(Stats::ToponymsRefresh::CURSOR_KEY,
                Stats::ToponymsRefresh::DISCOVERY_KEY,
                Stats::ToponymsRefresh::TURN_KEY)
    end
  end

  it 'retains the country after nightly geocoding and the scheduled statistics refresh' do
    locations = Array.new(7) do |index|
      {
        latitudeE7: -500_000_000,
        longitudeE7: -1_400_000_000 + index * 100,
        timestamp: (Time.utc(2025, 4, 1, 10) + index * 15.minutes).iso8601
      }
    end
    import.file.attach(io: StringIO.new({ locations: locations }.to_json),
                       filename: 'Records.json', content_type: 'application/json')
    clear_enqueued_jobs

    perform_enqueued_jobs { Imports::Create.new(user, import).call }
    expect(import.reload).to be_completed
    expect(import.source).to eq('google_records')
    expect(user.stats.find_by(year: 2025, month: 4)).to be_present

    perform_enqueued_jobs { Points::NightlyReverseGeocodingJob.perform_now }
    perform_enqueued_jobs { Stats::ToponymsRefreshJob.perform_now }
    travel 65.minutes do
      perform_enqueued_jobs { Stats::ToponymsRefreshJob.perform_now }
    end

    expect(user.points.not_anomaly.where(country_name: 'Synthetic Republic', city: nil).count).to eq(7)
    expect(user.points.not_reverse_geocoded).to be_empty

    totals = Insights::YearTotalsCalculator.new(user.stats.where(year: 2025), distance_unit: 'km').call

    expect(totals.countries_count).to eq(1)
  end
end
