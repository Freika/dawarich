# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillAreasIntoPlacesJob, type: :job do
  ['x' * 255, 'x' * 256, 'x' * 300, '東京🏠' * 100].each do |name|
    it "migrates a #{name.length}-character, #{name.bytesize}-byte Area name without losing its associations" do
      area = create(:area, name: name, latitude: -48.123456, longitude: -123.654321)
      visit = create(:visit, user: area.user, area: area, place: nil, status: :confirmed, name: name)
      note = create(:note, user: area.user, attachable: area, body: 'Legacy note')

      expect { described_class.perform_now }.not_to raise_error

      mapping = LegacyAreaPlaceMapping.find_by!(area: area)
      expect(mapping.place).to have_attributes(
        name: name.first(255), user_id: area.user_id, geofence: true, source: 'manual',
        latitude: area.latitude, longitude: area.longitude, visit_radius: area.visit_radius
      )
      expect(mapping.place).to be_name_locked
      expect(mapping.place.name).to be_valid_encoding
      expect(area.reload.name).to eq(name)
      expect(visit.reload).to have_attributes(area_id: nil, place_id: mapping.place_id, location_label: name)
      expect(note.reload).to have_attributes(attachable: mapping.place, body: 'Legacy note')

      expect { described_class.perform_now }.not_to(change { [Place.count, LegacyAreaPlaceMapping.count] })
      expect(visit.reload.place_id).to eq(mapping.place_id)
      expect(note.reload.attachable).to eq(mapping.place)
    end
  end

  it 'keeps long names with a shared prefix separate from each other and an existing prefix match' do
    user = create(:user)
    prefix = 'x' * 255
    existing = create(:place, user: user, name: prefix, latitude: 52.5, longitude: 13.4)
    first = create(:area, user: user, name: "#{prefix}a", latitude: 52.5, longitude: 13.4)
    second = create(:area, user: user, name: "#{prefix}b", latitude: 52.5, longitude: 13.4)
    ordinary = create(:area, user: user, name: 'Office', latitude: 52.5, longitude: 13.4)
    areas = [first, second, ordinary]
    visits = areas.map { |area| create(:visit, user: user, area: area, place: nil, status: :confirmed, name: nil) }
    notes = areas.map { |area| create(:note, user: user, attachable: area, body: area.name) }

    described_class.perform_now(batch_size: 1)

    places = areas.map { |area| LegacyAreaPlaceMapping.find_by!(area: area).place }
    expect(places.map(&:id).uniq.size).to eq(3)
    expect(places).not_to include(existing)
    expect(places.map(&:name)).to eq([prefix, prefix, 'Office'])
    areas.zip(places, visits, notes).each do |area, place, visit, note|
      expect(visit.reload).to have_attributes(area_id: nil, place_id: place.id, location_label: area.name)
      expect(note.reload).to have_attributes(attachable: place, body: area.name)
      expect(area.reload).to be_persisted
    end

    expect { described_class.perform_now }.not_to(change { [Place.count, LegacyAreaPlaceMapping.count] })
    expect(areas.map { |area| LegacyAreaPlaceMapping.find_by!(area: area).place_id }).to eq(places.map(&:id))
  end

  it 'bounds the copied name when promoting a Place matched by the full normalized Area name' do
    user = create(:user)
    name = 'x' * 255
    place = create(:place, user: user, name: name, source: :photon, latitude: 52.5, longitude: 13.4)
    area = create(:area, user: user, name: "#{name} ", latitude: place.lat, longitude: place.lon)

    described_class.perform_now

    expect(LegacyAreaPlaceMapping.find_by!(area: area).place).to eq(place)
    expect(place.reload).to have_attributes(name: name, source: 'manual', geofence: true)
    expect(place).to be_name_locked
    expect(area.reload.name).to eq("#{name} ")
    expect { described_class.perform_now }.not_to change(Place, :count)
  end

  [false, true].each do |existing_match|
    it "handles a blank prefix when #{existing_match ? 'promoting' : 'creating'} a Place" do
      area = create(:area, name: "#{' ' * 255}Home")
      if existing_match
        existing = create(:place, user: area.user, name: 'Home', latitude: area.lat, longitude: area.lon)
      end

      described_class.perform_now

      place = LegacyAreaPlaceMapping.find_by!(area: area).place
      expect(place.name).to eq('Home')
      expect(place).to eq(existing) if existing_match
      expect(area.reload.name).to eq("#{' ' * 255}Home")
    end
  end

  it 'keeps a nonblank name after a multibyte whitespace-only prefix' do
    area = create(:area, name: "#{'　' * 255}東京")

    described_class.perform_now

    expect(LegacyAreaPlaceMapping.find_by!(area: area).place.name).to eq('東京')
  end

  ['', ' '].each do |suffix|
    [false, true].each do |reverse|
      it "keeps original identities for a shared prefix, suffix=#{suffix.inspect}, reverse=#{reverse}" do
        user = create(:user)
        prefix = 'x' * 255
        names = ["#{prefix}a", "#{prefix}#{suffix}"]
        names.reverse! if reverse
        areas = names.map { |name| create(:area, user: user, name: name) }

        described_class.perform_now(batch_size: 1)

        places = areas.map { |area| LegacyAreaPlaceMapping.find_by!(area: area).place }
        expect(places.map(&:id).uniq.size).to eq(2)
        expect(places.map(&:name)).to eq([prefix, prefix])
        expect { described_class.perform_now }.not_to change(Place, :count)
      end
    end
  end

  it 'resolves a long-named legacy Area lazily through the same restartable backfill' do
    area = create(:area, name: '東京🏠' * 100)
    adapter = Places::LegacyAreaAdapter.new(user: area.user)

    place = adapter.resolve(area)

    expect(place.name).to eq(area.name.first(255))
    expect(adapter.resolve(area)).to eq(place)
    expect(LegacyAreaPlaceMapping.find_by!(area: area).place).to eq(place)
  end
end
