# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family access at the locked consent decision' do
  include ActiveSupport::Testing::TimeHelpers

  let(:family) { create(:family, access_until: 5.minutes.from_now) }
  let(:owner) { family.creator }
  let(:responder) { create(:user) }
  let(:request_record) do
    create(:family_location_request, family: family, requester: owner,
                                    target_user: responder, expires_at: 1.hour.from_now)
  end

  before do
    create(:family_membership, family: family, user: owner, role: :owner)
    create(:family_membership, family: family, user: responder)
  end

  def respond(decision = :accept)
    Families::RespondToLocationRequest.new(request: request_record, responder: responder,
                                           decision: decision, duration: '1h').call
  end

  it 'refuses consent when Cloud access expires while waiting for the request lock' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    expect(DawarichSettings.family_feature_available_for?(responder)).to be(true)
    deadline = family.access_until
    allow(request_record).to receive(:with_lock).and_wrap_original do |lock, &block|
      lock.call { travel_to(deadline + 1.second) { block.call } }
    end

    expect(respond.success?).to be(false)
    expect(request_record.reload).to be_pending
    expect(responder.reload.family_sharing_enabled?).to be(false)
  end

  it 'refuses a responder removed from the family during the lock wait' do
    allow(request_record).to receive(:with_lock).and_wrap_original do |lock, &block|
      responder.family_membership.destroy!
      lock.call(&block)
    end

    expect(respond.success?).to be(false)
    expect(request_record.reload).to be_expired
    expect(responder.reload.family_sharing_enabled?).to be(false)
  end

  it 'retains self-hosted consent when the recorded Cloud deadline has passed' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    family.update!(access_until: 1.minute.ago)

    expect(respond.success?).to be(true)
    expect(request_record.reload).to be_accepted
    expect(responder.reload.family_sharing_enabled?).to be(true)
  end

  it 'accepts consent while inherited Cloud access is current' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

    expect(respond.success?).to be(true)
    expect(request_record.reload).to be_accepted
  end

  it 'leaves a declined decision pending when Cloud access has already expired' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    family.update!(access_until: 1.minute.ago)

    expect(respond(:decline).success?).to be(false)
    expect(request_record.reload).to be_pending
  end
end
