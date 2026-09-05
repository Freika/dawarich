# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Geocoded historical statistics' do
  it 'schedules a historical month again after country data arrives' do
    user = create(:user, stats_swept_at: Time.current, settings: { 'timezone' => 'Etc/UTC' })
    point = create(:point, user:, timestamp: Time.utc(2014, 6, 15, 12).to_i)
    stat = create(:stat, user:, year: 2014, month: 6, toponyms: [],
                         calculation_version: Stats::CalculateMonth::CALCULATION_VERSION)
    country = create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU')
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    allow(Geocoder).to receive(:search).and_return([
                                                     double(city: 'Berlin', country: country.name, country_code: 'DE',
                                                            data: {})
                                                   ])
    clear_enqueued_jobs

    ReverseGeocoding::Points::FetchData.new(point.id).call

    expect(point.reload.country_id).to eq(country.id)
    expect(point.city).to eq('Berlin')
    expect(stat.reload.toponyms).to eq([])
    Stats::BulkCalculator.new(user.id).call

    expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, 2014, 6, notify_on_failure: false)
  end
end
