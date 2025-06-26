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
      let!(:place1) { create(:place, name: 'Home', longitude: -74.0059, latitude: 40.7128) }
      let!(:place2) { create(:place, name: 'Office', longitude: -73.9851, latitude: 40.7589) }
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
end
