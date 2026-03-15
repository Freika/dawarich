# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::ExpireLocationRequestsJob, type: :job do
  let(:family) { create(:family) }
  let(:requester) { family.creator }
  let(:target_user) { create(:user) }

  before do
    create(:family_membership, family: family, user: requester, role: :owner)
    create(:family_membership, family: family, user: target_user)
  end

  describe '#perform' do
    it 'expires pending requests past their expires_at' do
      expired = create(:family_location_request,
                       requester: requester, target_user: target_user, family: family,
                       status: :pending, expires_at: 1.hour.ago)

      described_class.perform_now

      expect(expired.reload).to be_expired
    end

    it 'does not expire pending requests still within their window' do
      active = create(:family_location_request,
                      requester: requester, target_user: target_user, family: family,
                      status: :pending, expires_at: 1.hour.from_now)

      described_class.perform_now

      expect(active.reload).to be_pending
    end

    it 'does not change already accepted requests' do
      accepted = create(:family_location_request,
                        requester: requester, target_user: target_user, family: family,
                        status: :accepted, expires_at: 1.hour.ago)

      described_class.perform_now

      expect(accepted.reload).to be_accepted
    end

    it 'does not change already declined requests' do
      declined = create(:family_location_request,
                        requester: requester, target_user: target_user, family: family,
                        status: :declined, expires_at: 1.hour.ago)

      described_class.perform_now

      expect(declined.reload).to be_declined
    end

    it 'writes correct integer enum value for expired status' do
      expired = create(:family_location_request,
                       requester: requester, target_user: target_user, family: family,
                       status: :pending, expires_at: 1.hour.ago)

      described_class.perform_now

      raw_status = Family::LocationRequest.where(id: expired.id).pick(:status)
      expect(raw_status).to eq('expired')
    end

    it 'is idempotent' do
      expired = create(:family_location_request,
                       requester: requester, target_user: target_user, family: family,
                       status: :pending, expires_at: 1.hour.ago)

      described_class.perform_now
      described_class.perform_now

      expect(expired.reload).to be_expired
    end
  end
end
