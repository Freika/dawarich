# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixture: ISO codes and flags of Countries::IsoCodeMapper' do
  it 'writes priv/country_codes.json in COUNTRIES order' do
    countries = Countries::IsoCodeMapper::COUNTRIES
    expect(countries.all? { |key, data| key == data[:iso2] }).to be(true)

    path = Rails.root.join('app-phoenix/priv/country_codes.json')
    rows = countries.values.map { |data| [data[:name], data[:iso2], data[:iso3], data[:flag]] }
    File.write(path, "#{Oj.dump({ 'countries' => rows }, mode: :strict, indent: 2)}\n")

    expect(JSON.parse(path.read)['countries'].size).to eq(countries.size)
    expect(Countries::IsoCodeMapper.iso_codes_from_country_name('Russia')).to eq(%w[RU RUS])
    expect(Countries::IsoCodeMapper.iso_codes_from_country_name('germany')).to eq(%w[DE DEU])
    expect(Countries::IsoCodeMapper.iso_codes_from_country_name('Atlantis')).to eq([nil, nil])
  end
end
