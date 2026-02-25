# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Taggings, type: :service do
  let(:user) { create(:user) }

  describe '#call' do
    context 'when taggings_data is not an array' do
      it 'returns 0 for nil' do
        service = described_class.new(user, nil)
        expect(service.call).to eq(0)
      end
    end

    context 'when taggings_data is empty' do
      it 'returns 0' do
        service = described_class.new(user, [])
        expect(service.call).to eq(0)
      end
    end

    context 'with valid taggings data' do
      let!(:tag) { create(:tag, user: user, name: 'Home') }
      let!(:place) { create(:place, user: user, name: 'My House', latitude: 40.7128, longitude: -74.006) }

      let(:taggings_data) do
        [
          {
            'tag_name' => 'Home',
            'taggable_type' => 'Place',
            'taggable_name' => 'My House',
            'taggable_latitude' => '40.7128',
            'taggable_longitude' => '-74.006'
          }
        ]
      end

      it 'creates the tagging' do
        service = described_class.new(user, taggings_data)

        expect { service.call }.to change { Tagging.count }.by(1)
      end

      it 'returns the count of created taggings' do
        service = described_class.new(user, taggings_data)

        expect(service.call).to eq(1)
      end

      it 'associates the correct tag and place' do
        service = described_class.new(user, taggings_data)
        service.call

        tagging = Tagging.last
        expect(tagging.tag).to eq(tag)
        expect(tagging.taggable).to eq(place)
      end
    end

    context 'when tag does not exist' do
      let!(:place) { create(:place, user: user, name: 'My House', latitude: 40.7128, longitude: -74.006) }

      let(:taggings_data) do
        [
          {
            'tag_name' => 'NonExistent',
            'taggable_type' => 'Place',
            'taggable_name' => 'My House',
            'taggable_latitude' => '40.7128',
            'taggable_longitude' => '-74.006'
          }
        ]
      end

      it 'skips the tagging' do
        service = described_class.new(user, taggings_data)

        expect { service.call }.not_to(change { Tagging.count })
        expect(service.call).to eq(0)
      end
    end

    context 'when place does not exist' do
      let!(:tag) { create(:tag, user: user, name: 'Home') }

      let(:taggings_data) do
        [
          {
            'tag_name' => 'Home',
            'taggable_type' => 'Place',
            'taggable_name' => 'NonExistent',
            'taggable_latitude' => '99.9999',
            'taggable_longitude' => '99.9999'
          }
        ]
      end

      it 'skips the tagging' do
        service = described_class.new(user, taggings_data)

        expect { service.call }.not_to(change { Tagging.count })
      end
    end

    context 'with duplicate taggings' do
      let!(:tag) { create(:tag, user: user, name: 'Home') }
      let!(:place) { create(:place, user: user, name: 'My House', latitude: 40.7128, longitude: -74.006) }
      let!(:existing_tagging) { Tagging.create!(tag: tag, taggable: place) }

      let(:taggings_data) do
        [
          {
            'tag_name' => 'Home',
            'taggable_type' => 'Place',
            'taggable_name' => 'My House',
            'taggable_latitude' => '40.7128',
            'taggable_longitude' => '-74.006'
          }
        ]
      end

      it 'skips the duplicate tagging' do
        service = described_class.new(user, taggings_data)

        expect { service.call }.not_to(change { Tagging.count })
      end
    end
  end
end
