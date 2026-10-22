# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Photoprism sub-day trip photo bounds' do
  let(:user) do
    create(
      :user,
      settings: {
        'photoprism_url' => 'http://photoprism.local',
        'photoprism_api_key' => 'test_api_key'
      }
    )
  end

  # Photoprism reports TakenAt in UTC and TakenAtLocal as wall-clock time in the
  # photo's own zone, both serialized with a trailing Z. Munich in June is UTC+2,
  # so a photo taken at 14:45 UTC carries TakenAtLocal 16:45.
  let(:photo) do
    {
      'ID' => '5',
      'UID' => 'pthgne34x970u6d5',
      'Type' => 'image',
      'TakenAt' => '2026-06-22T14:45:00Z',
      'TakenAtLocal' => '2026-06-22T16:45:00Z',
      'TimeZone' => 'Europe/Berlin',
      'Lat' => 48.135125,
      'Lng' => 11.5819805555556
    }
  end

  around { |example| Time.use_zone('UTC') { example.run } }

  before do
    stub_request(:get, %r{http://photoprism\.local/api/v1/photos})
      .to_return(
        { status: 200, body: [photo].to_json, headers: { 'Content-Type' => 'application/json' } },
        { status: 200, body: [].to_json, headers: { 'Content-Type' => 'application/json' } }
      )
  end

  def photos_between(start_at, end_at)
    Photoprism::RequestPhotos.new(user, start_date: start_at.iso8601, end_date: end_at.iso8601).call.size
  end

  it 'excludes a photo taken before the trip started' do
    expect(photos_between(Time.utc(2026, 6, 22, 15, 0, 0), Time.utc(2026, 6, 22, 23, 59, 59))).to eq(0)
  end

  it 'includes a photo taken exactly at the trip end boundary' do
    expect(photos_between(Time.utc(2026, 6, 22, 0, 0, 0), Time.utc(2026, 6, 22, 14, 45, 0))).to eq(1)
  end

  it 'excludes a photo taken after the trip ended' do
    expect(photos_between(Time.utc(2026, 6, 22, 0, 0, 0), Time.utc(2026, 6, 22, 12, 0, 0))).to eq(0)
  end

  it 'includes a photo taken within a full-day trip' do
    expect(photos_between(Time.utc(2026, 6, 22, 0, 0, 0), Time.utc(2026, 6, 22, 23, 59, 59))).to eq(1)
  end

  it 'requests the window using the trip dates without extra start padding' do
    photos_between(Time.utc(2026, 6, 22, 0, 0, 0), Time.utc(2026, 6, 22, 23, 59, 59))

    expect(
      a_request(:get, %r{http://photoprism\.local/api/v1/photos})
        .with(query: hash_including('after' => '2026-06-22', 'before' => '2026-06-23'))
    ).to have_been_made.at_least_once
  end

  context 'when the trip bounds render in a non-UTC application zone' do
    # Photoprism's after/before filter on the UTC TakenAt date, so the requested
    # window has to be derived from the UTC instant rather than the local date.
    let(:photo) do
      {
        'ID' => '12',
        'Type' => 'image',
        'TakenAt' => '2026-06-25T23:30:00Z',
        'TakenAtLocal' => '2026-06-26T01:30:00Z',
        'TimeZone' => 'Europe/Berlin'
      }
    end

    around { |example| Time.use_zone('Europe/Berlin') { example.run } }

    def photos_between_local(start_at, end_at)
      Photoprism::RequestPhotos.new(
        user, start_date: start_at.in_time_zone.iso8601, end_date: end_at.in_time_zone.iso8601
      ).call.size
    end

    it 'requests the window using UTC dates, not the local ones' do
      photos_between_local(Time.utc(2026, 6, 25, 23, 0, 0), Time.utc(2026, 6, 25, 23, 59, 59))

      expect(
        a_request(:get, %r{http://photoprism\.local/api/v1/photos})
          .with(query: hash_including('after' => '2026-06-25', 'before' => '2026-06-26'))
      ).to have_been_made.at_least_once
    end

    it 'still returns a photo that falls inside the trip' do
      expect(photos_between_local(Time.utc(2026, 6, 25, 23, 0, 0), Time.utc(2026, 6, 25, 23, 59, 59))).to eq(1)
    end
  end

  context 'with a photo from a negative UTC offset zone' do
    # Los Angeles in June is UTC-7, so local wall-clock runs behind UTC and the
    # old comparison skewed the window in the opposite direction.
    let(:photo) do
      {
        'ID' => '9',
        'Type' => 'image',
        'TakenAt' => '2026-06-22T02:00:00Z',
        'TakenAtLocal' => '2026-06-21T19:00:00Z',
        'TimeZone' => 'America/Los_Angeles',
        'Lat' => 34.0522,
        'Lng' => -118.2437
      }
    end

    it 'includes a photo whose UTC instant falls inside the trip' do
      expect(photos_between(Time.utc(2026, 6, 22, 0, 0, 0), Time.utc(2026, 6, 22, 23, 59, 59))).to eq(1)
    end

    it 'excludes a photo whose UTC instant falls before the trip' do
      expect(photos_between(Time.utc(2026, 6, 22, 6, 0, 0), Time.utc(2026, 6, 22, 23, 59, 59))).to eq(0)
    end
  end

  context 'when Photoprism omits TakenAt' do
    let(:photo) { { 'ID' => '7', 'Type' => 'image', 'TakenAtLocal' => '2026-06-22T16:45:00Z' } }

    it 'falls back to TakenAtLocal' do
      expect(photos_between(Time.utc(2026, 6, 22, 0, 0, 0), Time.utc(2026, 6, 22, 23, 59, 59))).to eq(1)
    end
  end

  context 'when Photoprism sends a blank TakenAt' do
    let(:photo) do
      { 'ID' => '8', 'Type' => 'image', 'TakenAt' => '', 'TakenAtLocal' => '2026-06-22T16:45:00Z' }
    end

    it 'falls back to TakenAtLocal' do
      expect(photos_between(Time.utc(2026, 6, 22, 0, 0, 0), Time.utc(2026, 6, 22, 23, 59, 59))).to eq(1)
    end
  end

  context 'when a photo carries no usable timestamp' do
    let(:photo) { { 'ID' => '10', 'Type' => 'image' } }

    it 'skips the photo instead of aborting the whole fetch' do
      expect(photos_between(Time.utc(2026, 6, 22, 0, 0, 0), Time.utc(2026, 6, 22, 23, 59, 59))).to eq(0)
    end
  end

  context 'when a photo carries a malformed timestamp' do
    let(:photo) { { 'ID' => '11', 'Type' => 'image', 'TakenAt' => 'not-a-date' } }

    it 'skips the photo instead of aborting the whole fetch' do
      expect(photos_between(Time.utc(2026, 6, 22, 0, 0, 0), Time.utc(2026, 6, 22, 23, 59, 59))).to eq(0)
    end
  end
end
