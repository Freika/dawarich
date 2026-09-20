# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TripSource, type: :model do
  before do
    allow(Resolv).to receive(:getaddress).with('trek.example.test').and_return('93.184.216.34')
  end

  it 'encrypts the TREK key and normalizes the base URL' do
    source = create(:trip_source, base_url: ' https://trek.example.test/ ')

    expect(source.base_url).to eq('https://trek.example.test')
    expect(source.reload.api_key).to eq('trek_test_key')
    expect(source.read_attribute_before_type_cast('api_key')).not_to include('trek_test_key')
  end

  it 'accepts only supported trip source providers' do
    source = build(:trip_source, provider: 'other')

    expect(source).not_to be_valid
    expect(source.errors[:provider]).to be_present
  end
end
