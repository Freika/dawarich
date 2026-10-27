# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportData::Places, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  subject { service.call }

  describe '#call' do
    context 'when user has no places' do
      it 'returns an empty array' do
        expect(subject).to eq([])
      end
    end

    context 'when user has places' do
      let!(:place1) { create(:place, user: user, name: 'Home', longitude: -74.0059, latitude: 40.7128) }
      let!(:place2) { create(:place, user: user, name: 'Office', longitude: -73.9851, latitude: 40.7589) }
      let!(:visit1) { create(:visit, user: user, place: place1) }
      let!(:visit2) { create(:visit, user: user, place: place2) }

      it 'returns all places' do
        expect(subject.size).to eq(2)
      end

      it 'excludes id field' do
        subject.each do |place_data|
          expect(place_data).not_to have_key('id')
        end
      end

      it 'includes expected place attributes' do
        place_data = subject.find { |p| p['name'] == 'Office' }

        expect(place_data).to include(
          'name' => 'Office',
          'longitude' => '-73.9851',
          'latitude' => '40.7589'
        )
        expect(place_data).to have_key('created_at')
        expect(place_data).to have_key('updated_at')
      end
    end
  end

  it 'round trips archive timestamps and active Places through user data export and import', :archive do
    timestamp = Time.zone.parse('2026-10-27 12:00:00')
    create(:place, user:, name: 'Old Home', archived_at: timestamp)
    create(:place, user:, name: 'New Home')
    destination = create(:user)
    data = JSON.parse(described_class.new(user).call.to_json)

    Users::ImportData::Places.new(destination, data).call

    expect(destination.places.find_by!(name: 'Old Home').archived_at).to eq(timestamp)
    expect(destination.places.find_by!(name: 'New Home').archived_at).to be_nil
    expect(data.find { |place| place['name'] == 'Old Home' }['archived_at']).to be_present
  end
end
