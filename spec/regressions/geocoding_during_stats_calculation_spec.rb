# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Geocoding during monthly calculation', :non_transactional, threads: 3 do
  it 'preserves invalidation when geocoding finishes after statistics read the points' do
    user = create(:user, settings: { 'timezone' => 'Etc/UTC' })
    point = create(:point, user:, timestamp: Time.utc(2014, 6, 15, 12).to_i)
    stat = create(:stat, user:, year: 2014, month: 6, toponyms: [], calculation_version: 0)
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    allow(Geocoder).to receive(:search).and_return([
                                                     double(city: 'Berlin', country: 'Germany', country_code: 'DE',
                                                            data: {})
                                                   ])
    read_points = Concurrent::CountDownLatch.new(1)
    release_calculation = Concurrent::CountDownLatch.new(1)
    geocoded = Concurrent::CountDownLatch.new(1)
    calculator = Stats::CalculateMonth.new(user.id, 2014, 6)
    allow(calculator).to receive(:toponyms).and_wrap_original do |method|
      result = method.call
      read_points.count_down
      raise 'calculation release timed out' unless release_calculation.wait(10)

      result
    end
    allow(Stats::InvalidateGeocodedMonth).to receive(:call).and_wrap_original do |method, record|
      geocoded.count_down
      method.call(record)
    end

    calculation = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { calculator.call }
    end
    expect(read_points.wait(10)).to be(true)
    geocoding = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ReverseGeocoding::Points::FetchData.new(point.id).call
      end
    end
    expect(geocoded.wait(10)).to be(true)
    release_calculation.count_down
    expect(calculation.join(10)).not_to be_nil
    expect(geocoding.join(10)).not_to be_nil
    calculation.value
    geocoding.value

    expect(point.reload.city).to eq('Berlin')
    expect(stat.reload.calculation_version).to eq(0)
    Stats::CalculateMonth.new(user.id, 2014, 6).call
    expect(stat.reload.calculation_version).to eq(Stats::CalculateMonth::CALCULATION_VERSION)
  ensure
    release_calculation&.count_down
    [calculation, geocoding].compact.each { |thread| thread.join(10) }
    Stat.where(user_id: user&.id).delete_all
  end
end
