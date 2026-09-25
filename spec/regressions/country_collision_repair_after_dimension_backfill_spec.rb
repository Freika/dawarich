# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Country collision repair after dimension backfill' do
  it 'repairs historical links on points v2 using retained country names' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    wrong = create(:country, name: 'US Naval Base Guantanamo Bay', iso_a2: 'US', iso_a3: 'USA')
    correct = create(:country, name: 'United States', iso_a2: 'US', iso_a3: 'USA')
    point = create(:point)
    point.update_columns(country_id: wrong.id, country_name: 'United States',
                         country: 'United States', source_id: nil)
    unresolved = create(:point)
    unresolved.update_columns(country_id: nil, country_name: 'United States',
                              country: 'United States', source_id: nil)
    DataMigrations::BackfillPointCountryIdJob.perform_now(repair_collisions: true)

    expect(point.reload.country_id).to eq(correct.id)
    expect(unresolved.reload.country_id).to eq(correct.id)
  end
end
