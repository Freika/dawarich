# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Tags, type: :service do
  let(:user) { create(:user) }

  describe '#call' do
    context 'when tags_data is not an array' do
      it 'returns 0 for nil' do
        service = described_class.new(user, nil)
        expect(service.call).to eq(0)
      end

      it 'returns 0 for a hash' do
        service = described_class.new(user, { 'name' => 'test' })
        expect(service.call).to eq(0)
      end
    end

    context 'when tags_data is empty' do
      it 'returns 0' do
        service = described_class.new(user, [])
        expect(service.call).to eq(0)
      end
    end

    context 'with valid tags data' do
      let(:tags_data) do
        [
          { 'name' => 'Home', 'icon' => '🏠', 'color' => '#4CAF50' },
          { 'name' => 'Work', 'icon' => '🏢', 'color' => '#2196F3' }
        ]
      end

      it 'creates the tags' do
        service = described_class.new(user, tags_data)

        expect { service.call }.to change { user.tags.count }.by(2)
      end

      it 'returns the count of created tags' do
        service = described_class.new(user, tags_data)

        expect(service.call).to eq(2)
      end

      it 'sets the correct attributes' do
        service = described_class.new(user, tags_data)
        service.call

        tag = user.tags.find_by(name: 'Home')
        expect(tag).to be_present
        expect(tag.icon).to eq('🏠')
        expect(tag.color).to eq('#4CAF50')
      end
    end

    context 'with tags missing name' do
      let(:tags_data) do
        [
          { 'name' => '', 'icon' => '🏠' },
          { 'icon' => '🏢' },
          { 'name' => 'Valid', 'icon' => '✅' }
        ]
      end

      it 'skips tags without name and imports valid ones' do
        service = described_class.new(user, tags_data)

        expect(service.call).to eq(1)
        expect(user.tags.find_by(name: 'Valid')).to be_present
      end
    end

    context 'with duplicate tags' do
      let(:tags_data) do
        [{ 'name' => 'Duplicate', 'icon' => '📍' }]
      end

      let!(:existing_tag) { create(:tag, user: user, name: 'Duplicate') }

      it 'skips the duplicate tag' do
        service = described_class.new(user, tags_data)

        expect { service.call }.not_to(change { user.tags.count })
      end

      it 'returns 0 for skipped tags' do
        service = described_class.new(user, tags_data)

        expect(service.call).to eq(0)
      end
    end

    context 'with multiple users' do
      let(:other_user) { create(:user) }
      let!(:other_tag) { create(:tag, user: other_user, name: 'SharedName') }

      let(:tags_data) do
        [{ 'name' => 'SharedName', 'icon' => '📍' }]
      end

      it 'creates the tag for the target user (not a duplicate across users)' do
        service = described_class.new(user, tags_data)

        expect { service.call }.to change { user.tags.count }.by(1)
      end
    end
  end
end
