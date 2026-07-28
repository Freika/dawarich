# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map v1 sunset banners', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it 'always shows the general v1 sunset banner on the classic map' do
    get map_v1_path

    expect(response.body).to include('map_v1_sunset_aug_2026')
    expect(response.body).to include('August 2026')
  end

  context 'when family location sharing is active in the user\'s family' do
    let(:family) { create(:family, creator: user) }
    let(:sharer) { create(:user) }

    before do
      allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(true)
      create(:family_membership, :owner, family: family, user: user)
      create(:family_membership, family: family, user: sharer)
      sharer.update_family_location_sharing!(true, duration: 'permanent')
    end

    it 'shows the family-history-on-v2 banner' do
      get map_v1_path

      expect(response.body).to include('map_v1_family_history_v2_only')
      expect(response.body).to include('Family location history is only shown on the new map')
    end
  end

  context 'when no family member is sharing' do
    it 'does not show the family banner' do
      get map_v1_path

      expect(response.body).not_to include('map_v1_family_history_v2_only')
    end
  end
end
