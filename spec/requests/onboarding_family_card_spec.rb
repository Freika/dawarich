# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Onboarding modal family card', type: :request do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  let(:card_title) { I18n.t('map.onboarding_modal.invite_your_family') }

  it 'offers the family step to a family-plan user' do
    sign_in create(:user, plan: :family, status: :trial, active_until: 7.days.from_now)

    get stats_path

    expect(response.body).to include(card_title)
  end

  it 'offers the family step to someone already in a family' do
    owner = create(:user, plan: :family, status: :trial, active_until: 7.days.from_now)
    family = create(:family, creator: owner)
    create(:family_membership, :owner, user: owner, family: family)
    member = create(:user, plan: :lite)
    create(:family_membership, user: member, family: family)

    sign_in member

    get stats_path

    expect(response.body).to include(card_title)
  end

  it 'hides the family step from a pro user' do
    sign_in create(:user, plan: :pro, status: :trial, active_until: 7.days.from_now)

    get stats_path

    expect(response.body).not_to include(card_title)
  end
end
