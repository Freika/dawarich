# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnhancedImport::Writers::PlaceWriter do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :gpx, name: 'favourites.gpx') }

  subject(:writer) { described_class.new(user, import, source: :gpx_waypoint) }

  def next_run
    described_class.new(user, import, source: :gpx_waypoint)
  end

  def extracted(name: 'Cafe Riquet', tag_name: 'Food', identity: 'gpx:abc123')
    EnhancedImport::Extracted::Place.new(
      external_place_id: identity,
      name: name,
      latitude: 51.3402,
      longitude: 12.3712,
      semantic_type: tag_name,
      geodata_extras: {},
      tag_name: tag_name,
      tag_color: '#10c0f0'
    )
  end

  describe 'a name longer than the column allows' do
    it 'stores a truncated name instead of aborting the extraction' do
      place, created = writer.upsert(extracted(name: 'A' * 400))

      expect(created).to be true
      expect(place.name.length).to eq(255)
    end
  end

  describe 'a place matched by proximity rather than identity' do
    let!(:existing) do
      create(:place, user: user, name: 'Cafe Riquet', latitude: 51.3402, longitude: 12.3712,
                     lonlat: 'POINT(12.3712 51.3402)', source: :photon, geodata: {})
    end

    it 'stamps the extracted identity onto the matched place' do
      writer.upsert(extracted)

      expect(existing.reload.geodata['external_place_id']).to eq('gpx:abc123')
    end

    it 'lets the next run find it by identity when position matching no longer could' do
      writer.upsert(extracted)
      existing.update_columns(name: 'Renamed by hand', lonlat: 'POINT(13.4050 52.5200)',
                              latitude: 52.52, longitude: 13.405)

      place, created = described_class.new(user, import, source: :gpx_waypoint).upsert(extracted)

      expect(created).to be false
      expect(place.id).to eq(existing.id)
    end

    it 'does not overwrite an identity the place already carries' do
      existing.update!(geodata: { 'external_place_id' => 'photon:kept' })

      writer.upsert(extracted(identity: 'gpx:other'))

      expect(existing.reload.geodata['external_place_id']).to eq('photon:kept')
    end
  end

  describe 'a place whose name the user edited in Dawarich' do
    it 'adopts the new identity without repainting the locked name' do
      writer.upsert(extracted(name: 'Cafe Riquet'))
      place = Place.where(user_id: user.id).sole
      place.update!(name: 'My favourite cafe')
      expect(place.reload).to be_name_locked

      next_run.upsert(extracted(name: 'Riquet Kaffeehaus', identity: 'gpx:renamed'))

      expect(place.reload.name).to eq('My favourite cafe')
      expect(place.geodata['external_place_id']).to eq('gpx:renamed')
      expect(Place.where(user_id: user.id).count).to eq(1)
    end

    it 'still renames a place the user never touched' do
      writer.upsert(extracted(name: 'Cafe Riquet'))

      next_run.upsert(extracted(name: 'Riquet Kaffeehaus', identity: 'gpx:renamed'))

      expect(Place.where(user_id: user.id).pluck(:name)).to eq(['Riquet Kaffeehaus'])
    end
  end

  describe 'when a concurrent writer already inserted the place' do
    it 'still attaches the category tag to the row it falls back to' do
      allow(Place).to receive(:create!) do
        create(:place, user: user, name: 'Cafe Riquet', latitude: 51.3402, longitude: 12.3712,
                       lonlat: 'POINT(12.3712 51.3402)', source: :gpx_waypoint,
                       geodata: { 'external_place_id' => 'gpx:abc123' })
        raise ActiveRecord::RecordNotUnique, 'simulated concurrent insert'
      end

      place, created = writer.upsert(extracted)

      expect(created).to be false
      expect(place.geodata['external_place_id']).to eq('gpx:abc123')
      expect(place.tags.map(&:name)).to include('Food')
    end
  end

  describe 'tag resolution' do
    def racing_tags
      tags = user.tags
      allow(user).to receive(:tags).and_return(tags)
      allow(tags).to receive(:create!) do
        create(:tag, user: user, name: 'Food', privacy_radius_meters: 100)
        raise ActiveRecord::RecordNotUnique, 'tags name unique'
      end
      tags
    end

    it 'looks a shared tag up once for a run of waypoints' do
      create(:tag, user: user, name: 'Food')
      run = next_run

      lookups = 0
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        lookups += 1 if payload[:sql].to_s.include?('LOWER(tags.name)')
      end

      3.times { |i| run.upsert(extracted(identity: "gpx:shared#{i}", name: "Place #{i}")) }

      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(lookups).to eq(1)
    end

    it 'never attaches an existing privacy-zone tag' do
      create(:tag, user: user, name: 'Food', privacy_radius_meters: 100)

      place, = writer.upsert(extracted)

      expect(place.reload.tags).to be_empty
    end

    it 'never attaches a privacy-zone tag that appeared while the tag was being created' do
      racing_tags

      place, = writer.upsert(extracted)

      expect(user.tags.find_by(name: 'Food')).to be_privacy_zone
      expect(place.reload.tags).to be_empty
    end

    it 'keeps the tag the race revealed instead of retrying the create for later waypoints' do
      tags = racing_tags

      writer.upsert(extracted(identity: 'gpx:race1', name: 'One'))
      writer.upsert(extracted(identity: 'gpx:race2', name: 'Two'))

      expect(tags).to have_received(:create!).once
    end
  end
end
