# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyLocationsChannel, type: :channel do
  let(:owner) { create(:user, plan: :family, skip_auto_trial: true) }
  let(:family) { create(:family, creator: owner) }

  before { create(:family_membership, user: owner, family: family, role: :owner) }

  it 'streams for a member of a family whose owner holds the plan' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    member = create(:user, plan: :pro, skip_auto_trial: true)
    create(:family_membership, user: member, family: family)
    stub_connection(current_user: member)

    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(family)
  end

  it 'rejects a cloud user without the family plan' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    stub_connection(current_user: create(:user, plan: :pro, skip_auto_trial: true))

    subscribe

    expect(subscription).to be_rejected
  end

  it 'rejects a member once the owner stops paying' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    member = create(:user, plan: :pro, skip_auto_trial: true)
    create(:family_membership, user: member, family: family)
    owner.update!(plan: :pro)
    stub_connection(current_user: member)

    subscribe

    expect(subscription).to be_rejected
  end

  it 'rejects an anonymous connection' do
    stub_connection(current_user: nil)

    subscribe

    expect(subscription).to be_rejected
  end
end
