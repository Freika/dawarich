# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Digests, type: :service do
  let(:user) { create(:user) }

  describe '#call' do
    context 'when digests_data is not an array' do
      it 'returns 0 for nil' do
        service = described_class.new(user, nil)
        expect(service.call).to eq(0)
      end

      it 'returns 0 for a hash' do
        service = described_class.new(user, { 'year' => 2024 })
        expect(service.call).to eq(0)
      end
    end

    context 'when digests_data is empty' do
      it 'returns 0' do
        service = described_class.new(user, [])
        expect(service.call).to eq(0)
      end
    end

    context 'with valid digests data' do
      let(:digests_data) do
        [
          {
            'year' => 2024,
            'month' => 1,
            'period_type' => 'monthly',
            'distance' => 50_000,
            'toponyms' => [{ 'country' => 'Germany' }],
            'monthly_distances' => [[1, 5000], [2, 3000]],
            'sharing_uuid' => 'old-uuid-should-be-replaced'
          },
          {
            'year' => 2024,
            'period_type' => 'yearly',
            'distance' => 500_000,
            'toponyms' => [{ 'country' => 'Germany' }],
            'sharing_uuid' => 'another-old-uuid'
          }
        ]
      end

      it 'creates the digests' do
        service = described_class.new(user, digests_data)

        expect { service.call }.to change { user.digests.count }.by(2)
      end

      it 'returns the count of created digests' do
        service = described_class.new(user, digests_data)

        expect(service.call).to eq(2)
      end

      it 'sets the correct attributes' do
        service = described_class.new(user, digests_data)
        service.call

        digest = user.digests.find_by(year: 2024, month: 1)
        expect(digest).to be_present
        expect(digest.period_type).to eq('monthly')
        expect(digest.distance).to eq(50_000)
        expect(digest.toponyms).to eq([{ 'country' => 'Germany' }])
      end

      it 'regenerates sharing_uuid' do
        service = described_class.new(user, digests_data)
        service.call

        digest = user.digests.find_by(year: 2024, month: 1)
        expect(digest.sharing_uuid).to be_present
        expect(digest.sharing_uuid).not_to eq('old-uuid-should-be-replaced')
      end
    end

    context 'with duplicate digests' do
      let(:digests_data) do
        [
          {
            'year' => 2024,
            'month' => 1,
            'period_type' => 'monthly',
            'distance' => 50_000
          }
        ]
      end

      let!(:existing_digest) do
        create(:users_digest, :monthly, user: user, year: 2024, month: 1)
      end

      it 'skips the duplicate digest' do
        service = described_class.new(user, digests_data)

        expect { service.call }.not_to(change { user.digests.count })
      end

      it 'returns 0 for skipped digests' do
        service = described_class.new(user, digests_data)

        expect(service.call).to eq(0)
      end
    end

    context 'with multiple users' do
      let(:other_user) { create(:user) }
      let!(:other_digest) { create(:users_digest, :monthly, user: other_user, year: 2024, month: 1) }

      let(:digests_data) do
        [
          {
            'year' => 2024,
            'month' => 1,
            'period_type' => 'monthly',
            'distance' => 50_000
          }
        ]
      end

      it 'creates the digest for the target user' do
        service = described_class.new(user, digests_data)

        expect { service.call }.to change { user.digests.count }.by(1)
      end
    end
  end
end
