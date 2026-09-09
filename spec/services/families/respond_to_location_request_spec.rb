# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::RespondToLocationRequest do
  let(:family) { create(:family) }
  let(:requester) { create(:user) }
  let(:target) { create(:user) }
  let!(:requester_membership) { create(:family_membership, user: requester, family: family, role: :owner) }
  let!(:target_membership) { create(:family_membership, user: target, family: family, role: :member) }
  let(:request) { create(:family_location_request, requester: requester, target_user: target, family: family) }

  describe '#call' do
    it 'accepts a request, enables sharing with the given duration' do
      result = described_class.new(request: request, responder: target, decision: :accept, duration: '1h').call

      expect(result.success?).to be true
      expect(request.reload).to be_accepted
      expect(request.responded_at).to be_present
      expect(target.reload.family_sharing_enabled?).to be true
      expect(target.family_sharing_duration).to eq('1h')
    end

    it 'falls back to the suggested duration on accept' do
      described_class.new(request: request, responder: target, decision: :accept).call

      expect(target.reload.family_sharing_duration).to eq(request.suggested_duration)
    end

    it 'declines a request without enabling sharing' do
      result = described_class.new(request: request, responder: target, decision: :decline).call

      expect(result.success?).to be true
      expect(request.reload).to be_declined
      expect(target.reload.family_sharing_enabled?).to be false
    end

    it 'rejects a responder who is not the target' do
      result = described_class.new(request: request, responder: requester, decision: :accept).call

      expect(result.success?).to be false
      expect(result.status).to eq(:forbidden)
    end

    it 'rejects an expired request' do
      request.update!(expires_at: 1.hour.ago)

      result = described_class.new(request: request, responder: target, decision: :accept).call

      expect(result.success?).to be false
      expect(result.status).to eq(:unprocessable_content)
    end
  end
end
