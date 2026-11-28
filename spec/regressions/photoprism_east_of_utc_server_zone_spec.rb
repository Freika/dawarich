# frozen_string_literal: true

require 'rails_helper'

# Photoprism running in a zone east of UTC (TZ=Europe/Berlin) reads a bare
# after/before date as local midnight and then compares on the UTC date, so
# both filters land one day earlier than requested (#3651).
RSpec.describe 'Photoprism served from a zone east of UTC' do
  let(:user) do
    create(
      :user,
      settings: {
        'photoprism_url' => 'http://photoprism.local',
        'photoprism_api_key' => 'test_api_key'
      }
    )
  end

  let(:photo) do
    { 'ID' => '1', 'Type' => 'image', 'TakenAt' => '2026-08-29T12:00:00Z', 'TakenAtLocal' => '2026-08-29T14:00:00Z' }
  end

  before do
    stub_request(:get, %r{http://photoprism\.local/api/v1/photos}).to_return do |request|
      query = request.uri.query_values
      taken_on = Date.parse(photo['TakenAt'])
      after = Date.parse(query['after']) - 1.day
      before = query['before'] ? Date.parse(query['before']) - 1.day : Date::Infinity.new
      matches = query['offset'].nil? && taken_on >= after && taken_on < before

      { status: 200, body: (matches ? [photo] : []).to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  it 'returns a photo taken on the single selected local day' do
    result = Photoprism::RequestPhotos.new(
      user, start_date: '2026-08-29T00:00:00+02:00', end_date: '2026-08-29T23:59:00+02:00'
    ).call

    expect(result.map { |p| p['ID'] }).to eq(['1'])
  end
end
