# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Italy achievement regions' do
  before { Achievements::Registry.reset! }
  after { Achievements::Registry.reset! }

  it 'includes Aosta Valley among all twenty regions' do
    italy = Achievements::Registry.find('country_it')

    expect(italy.region_codes).to match_array(%w[
                                                IT-21 IT-23 IT-25 IT-32 IT-34 IT-36 IT-42 IT-45 IT-52 IT-55
                                                IT-57 IT-62 IT-65 IT-67 IT-72 IT-75 IT-77 IT-78 IT-82 IT-88
                                              ])
  end

  it 'credits a point in Aosta to Aosta Valley alone' do
    create(:country)
    Achievements::LoadRegions.new.call

    covering = Region.where('ST_Covers(geom, ST_SetSRID(ST_MakePoint(7.32, 45.74), 4326))').pluck(:code)

    expect(covering).to eq(['IT-23'])
  end
end
