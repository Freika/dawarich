# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillFamilyMemberEntitlementsJob do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  let(:owner) do
    create(:user, plan: :family, status: :active, active_until: 1.year.from_now, skip_auto_trial: true)
  end
  let(:family) { create(:family, creator: owner) }
  let!(:owner_membership) { create(:family_membership, :owner, user: owner, family: family) }
  let!(:member) do
    create(:user, plan: :lite, status: :inactive, active_until: nil, skip_auto_trial: true)
      .tap { |user| create(:family_membership, user: user, family: family) }
  end

  it 'brings an existing member onto the owner plan' do
    described_class.perform_now

    expect(member.reload).to be_pro
    expect(member.reload).to be_active
  end

  it 'is idempotent' do
    described_class.perform_now

    expect { described_class.perform_now }.not_to(change { member.reload.updated_at })
  end

  it 'does nothing on self-hosted instances' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

    expect { described_class.perform_now }.not_to(change { member.reload.attributes.slice('status', 'plan') })
  end
end
