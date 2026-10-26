# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillKmlVelocitiesJob, type: :job do
  let(:user) { create(:user) }
  let(:start_time) { Time.utc(2024, 1, 15) }
  # Invented South Pacific fixes: two moving legs of about 940 km/h between stops.
  let(:samples) do
    [[0, -142, 'Departureland'], [60, -142, 'Departureland'], [70, -140, 'Overflownland'],
     [80, -138, 'Overflownland'], [90, -136, 'Arrivalland'], [150, -136, 'Arrivalland']]
  end

  def kml_import(velocity: '0.0', source: 'kml', day: 0, fixes: samples)
    import = create(:import, user:, source:, skip_background_processing: true)
    fixes.each do |minute, longitude, country|
      create(:point, user:, import:, velocity:, timestamp: (start_time + day.days + minute.minutes).to_i,
                     lonlat: "POINT(#{longitude} -45)", country_name: country, city: "#{country} City",
                     reverse_geocoded_at: Time.current)
    end
    import
  end

  def countries(year, month)
    user.stats.find_by!(year:, month:).toponyms.map { |entry| entry['country'] }
  end

  def speeds_kmh(import)
    import.points.order(:timestamp).map { |point| (point.velocity.to_f * 3.6).round }
  end

  it 'queues one backfill per KML import' do
    kml = kml_import
    kml_import(source: 'gpx', day: 1)

    expect { described_class.perform_now }.to have_enqueued_job(described_class).with(kml.id).exactly(:once)
  end

  it 'derives airborne speeds for points stored without one' do
    import = kml_import

    described_class.perform_now(import.id)

    expect(speeds_kmh(import)).to match([0, 0, be > 500, be > 500, 0, 0])
  end

  it 'recalculates the affected month, existing digests and overlapping trips' do
    import = kml_import
    Stats::CalculateMonth.new(user.id, 2024, 1).call
    yearly = Users::Digests::CalculateYear.new(user.id, 2024).call
    trip = create(:trip, user:, started_at: start_time, ended_at: start_time + 4.hours,
                         skip_calculation_enqueue: true)
    trip.calculate_countries
    trip.save!

    described_class.perform_now(import.id)

    aggregate_failures do
      expect(trip.reload.visited_countries).to contain_exactly('Departureland', 'Arrivalland')
      expect(user.stats.find_by!(year: 2024, month: 1).toponyms.map { |entry| entry['country'] })
        .to contain_exactly('Departureland', 'Arrivalland')
      expect(yearly.reload.top_countries_by_time.map { |country| country['name'] })
        .to contain_exactly('Departureland', 'Arrivalland')
      expect(user.digests.monthly).to be_empty
      expect(Users::Digests::Yearly::EmailSendingJob).not_to have_been_enqueued
    end
  end

  it 'leaves recorded speeds untouched and recalculates nothing' do
    import = kml_import(velocity: '5.0')

    described_class.perform_now(import.id)

    expect(import.points.pluck(:velocity)).to all(eq('5.0'))
    expect(user.stats).to be_empty
  end

  it 'recalculates nothing when run again' do
    import = kml_import
    described_class.perform_now(import.id)

    expect { described_class.perform_now(import.id) }.not_to(change { user.stats.pick(:updated_at) })
  end

  it 'still backfills when an overlapping trip is invalid' do
    import = kml_import
    trip = create(:trip, user:, started_at: start_time, ended_at: start_time + 4.hours,
                         skip_calculation_enqueue: true)
    trip.update_columns(name: '')

    described_class.perform_now(import.id)

    expect(trip.reload.visited_countries).to contain_exactly('Departureland', 'Arrivalland')
  end

  it 'recalculates on a retry when the first recalculation failed' do
    import = kml_import
    attempts = 0
    allow(Stats::CalculateMonth).to receive(:new).and_wrap_original do |original, *args, **kwargs|
      attempts += 1
      raise ActiveRecord::QueryCanceled, 'statement timeout' if attempts == 1

      original.call(*args, **kwargs)
    end

    expect { described_class.perform_now(import.id) }.to raise_error(ActiveRecord::QueryCanceled)
    described_class.perform_now(import.id)

    expect(countries(2024, 1)).to contain_exactly('Departureland', 'Arrivalland')
  end

  context 'when the user lives ahead of UTC' do
    let(:user) { create(:user, settings: { 'timezone' => 'Asia/Tokyo' }) }
    let(:start_time) { Time.utc(2024, 1, 31, 16) }

    it 'recalculates the month in the user time zone' do
      import = kml_import

      described_class.perform_now(import.id)

      expect(countries(2024, 2)).to contain_exactly('Departureland', 'Arrivalland')
    end
  end

  it 'recalculates nothing for movement below flight speed' do
    walk = [[0, -142.0, 'Homeland'], [10, -142.01, 'Homeland'], [20, -142.02, 'Homeland']]
    import = kml_import(fixes: walk)

    described_class.perform_now(import.id)

    expect(speeds_kmh(import)[1]).to be_positive
    expect(user.stats).to be_empty
  end

  it 'leaves imports that recorded some speeds untouched' do
    import = kml_import
    import.points.order(:timestamp).first.update_columns(velocity: '5.0')

    described_class.perform_now(import.id)

    expect(speeds_kmh(import)).to eq([18, 0, 0, 0, 0, 0])
  end

  it 'refreshes cached map tiles' do
    import = kml_import
    range = [0, Time.utc(2100, 1, 1).to_i]
    before_component = Points::TileEpoch.etag_component(user.id, *range)

    described_class.perform_now(import.id)

    expect(Points::TileEpoch.etag_component(user.id, *range)).not_to eq(before_component)
  end
end
