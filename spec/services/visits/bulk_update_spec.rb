# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::BulkUpdate do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  let!(:visit1) { create(:visit, user: user, status: 'suggested') }
  let!(:visit2) { create(:visit, user: user, status: 'suggested') }
  let!(:visit3) { create(:visit, user: user, status: 'confirmed') }
  let!(:other_user_visit) { create(:visit, user: other_user, status: 'suggested') }

  describe '#call' do
    context 'when all parameters are valid' do
      let(:visit_ids) { [visit1.id, visit2.id] }
      let(:status) { 'confirmed' }

      subject(:service) { described_class.new(user, visit_ids, status) }

      it 'updates the status of all specified visits' do
        result = service.call

        expect(result[:count]).to eq(2)
        expect(visit1.reload.status).to eq('confirmed')
        expect(visit2.reload.status).to eq('confirmed')
        expect(visit3.reload.status).to eq('confirmed') # This one wasn't changed
      end

      it 'returns a hash with count and visits' do
        result = service.call

        expect(result).to be_a(Hash)
        expect(result[:count]).to eq(2)
        expect(result[:visits]).to include(visit1, visit2)
        expect(result[:visits]).not_to include(visit3, other_user_visit)
      end

      it 'does not update visits that belong to other users' do
        service.call

        expect(other_user_visit.reload.status).to eq('suggested')
      end
    end

    context 'when changing to declined status' do
      let(:visit_ids) { [visit1.id, visit2.id, visit3.id] }
      let(:status) { 'declined' }

      subject(:service) { described_class.new(user, visit_ids, status) }

      it 'updates the status to declined' do
        result = service.call

        expect(result[:count]).to eq(3)
        expect(visit1.reload.status).to eq('declined')
        expect(visit2.reload.status).to eq('declined')
        expect(visit3.reload.status).to eq('declined')
      end
    end

    context 'when visit_ids is empty' do
      let(:visit_ids) { [] }
      let(:status) { 'confirmed' }

      subject(:service) { described_class.new(user, visit_ids, status) }

      it 'returns false' do
        expect(service.call).to be(false)
      end

      it 'adds an error' do
        service.call
        expect(service.errors).to include('No visits selected')
      end

      it 'does not update any visits' do
        service.call
        expect(visit1.reload.status).to eq('suggested')
        expect(visit2.reload.status).to eq('suggested')
        expect(visit3.reload.status).to eq('confirmed')
      end
    end

    context 'when visit_ids is nil' do
      let(:visit_ids) { nil }
      let(:status) { 'confirmed' }

      subject(:service) { described_class.new(user, visit_ids, status) }

      it 'returns false' do
        expect(service.call).to be(false)
      end

      it 'adds an error' do
        service.call
        expect(service.errors).to include('No visits selected')
      end
    end

    context 'when status is invalid' do
      let(:visit_ids) { [visit1.id, visit2.id] }
      let(:status) { 'invalid_status' }

      subject(:service) { described_class.new(user, visit_ids, status) }

      it 'returns false' do
        expect(service.call).to be(false)
      end

      it 'adds an error' do
        service.call
        expect(service.errors).to include('Invalid status')
      end

      it 'does not update any visits' do
        service.call
        expect(visit1.reload.status).to eq('suggested')
        expect(visit2.reload.status).to eq('suggested')
      end
    end

    context 'when no matching visits are found' do
      let(:visit_ids) { [999_999, 888_888] }
      let(:status) { 'confirmed' }

      subject(:service) { described_class.new(user, visit_ids, status) }

      it 'returns false' do
        expect(service.call).to be(false)
      end

      it 'adds an error' do
        service.call
        expect(service.errors).to include('No matching visits found')
      end
    end

    context 'when some visit IDs do not belong to the user' do
      let(:visit_ids) { [visit1.id, other_user_visit.id] }
      let(:status) { 'confirmed' }

      subject(:service) { described_class.new(user, visit_ids, status) }

      it 'only updates visits that belong to the user' do
        result = service.call

        expect(result[:count]).to eq(1)
        expect(visit1.reload.status).to eq('confirmed')
        expect(other_user_visit.reload.status).to eq('suggested')
      end
    end
  end
end
