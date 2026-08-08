# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Photo search covers the whole end date' do
  let(:immich_user) do
    create(:user, settings: { 'immich_url' => 'http://immich.app', 'immich_api_key' => '123456' })
  end
  let(:photoprism_user) do
    create(:user, settings: { 'photoprism_url' => 'http://photoprism.app', 'photoprism_api_key' => '123456' })
  end

  # A photo taken just after midnight on the last requested day must be inside
  # a range whose end is written as a bare date.
  let(:late_night_photo_utc) { '2026-06-11T01:02:00.000Z' }

  describe 'Immich' do
    def stub_immich_page(items)
      json_headers = { 'content-type' => 'application/json' }
      responses = [
        instance_double(HTTParty::Response, success?: true, code: 200, headers: json_headers,
                                            body: { assets: { items: items } }.to_json),
        instance_double(HTTParty::Response, success?: true, code: 200, headers: json_headers,
                                            body: { assets: { items: [] } }.to_json)
      ]
      allow(HTTParty).to receive(:post) { responses.shift || responses.last }
    end

    let(:asset) do
      {
        'id' => 'abc',
        'type' => 'IMAGE',
        'fileCreatedAt' => late_night_photo_utc,
        'localDateTime' => late_night_photo_utc,
        'exifInfo' => { 'latitude' => 52.0, 'longitude' => 13.0 }
      }
    end

    it 'includes a photo taken after midnight on the end date' do
      stub_immich_page([asset])

      result = described_immich_call

      expect(result.map { |photo| photo['id'] }).to include('abc')
    end

    it 'asks Immich for an end bound past the last instant of the end date' do
      stub_immich_page([])

      described_immich_call

      taken_before = nil
      expect(HTTParty).to have_received(:post) { |_url, options|
        taken_before = JSON.parse(options[:body])['takenBefore']
      }.at_least(:once)

      expect(Time.zone.parse(taken_before)).to be > Time.zone.parse(late_night_photo_utc)
    end

    it 'still honours an explicit time on the end bound' do
      stub_immich_page([asset])

      result = Immich::RequestPhotos.new(
        immich_user, start_date: '2026-06-10', end_date: '2026-06-11T00:30:00Z'
      ).call

      expect(result).to be_empty
    end

    def described_immich_call
      Immich::RequestPhotos.new(immich_user, start_date: '2026-06-10', end_date: '2026-06-11').call
    end
  end

  describe 'Photoprism' do
    it 'includes a photo taken after midnight on the end date' do
      json_headers = { 'content-type' => 'application/json' }
      responses = [
        instance_double(HTTParty::Response, success?: true, code: 200, headers: json_headers,
                                            body: [{ 'UID' => 'p1', 'Type' => 'image',
                                                     'TakenAtLocal' => '2026-06-11T01:02:00Z' }].to_json),
        instance_double(HTTParty::Response, success?: true, code: 200, headers: json_headers, body: [].to_json)
      ]
      allow(HTTParty).to receive(:get) { responses.shift || responses.last }

      result = Photoprism::RequestPhotos.new(
        photoprism_user, start_date: '2026-06-10', end_date: '2026-06-11'
      ).call

      expect(result.map { |photo| photo['UID'] }).to include('p1')
    end
  end
end
