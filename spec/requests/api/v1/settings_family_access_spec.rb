# frozen_string_literal: true

require 'rails_helper'

# Regression coverage for the read/write divergence that occurs when a cloud
# user with their own paid :lite subscription joins a paid :family. The write
# path (Api::V1::SettingsController#settings_params + Users::SettingsUpdater)
# gates on `current_api_user.plan_restricted?` (Entitlements, which honors family
# inheritance), while the read path gates on `Users::SafeSettings#lite?`, fed by
# `User#safe_settings`. These specs assert the read path stays aligned with the
# write path after `User#safe_settings` was changed to derive the plan from
# `entitlements.full_access?`.
RSpec.describe 'Api::V1 Settings read/write alignment for family inherited access', type: :request do
  def paid_lite_user(email:)
    create(
      :user,
      plan: :lite, status: :active, active_until: 1.year.from_now,
      subscription_source: :paddle, skip_auto_trial: true, email: email
    )
  end

  def paid_family_owner(email:)
    create(
      :user,
      plan: :family, status: :active, active_until: 1.year.from_now,
      subscription_source: :paddle, skip_auto_trial: true, email: email
    )
  end

  context 'when a paid :lite member joins a paid :family' do
    let(:owner) { paid_family_owner(email: 'owner@example.com') }
    let(:alice) { paid_lite_user(email: 'alice@example.com') }
    let(:family) { create(:family, creator: owner) }
    let(:invitation) { create(:family_invitation, family: family, invited_by: owner, email: alice.email) }
    let(:api_key) { alice.api_key }

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      create(:family_membership, :owner, family: family, user: owner)
      # The production flow under test: Alice pays for :lite on her own, then
      # accepts the family invitation. SyncMembers skips her because her own
      # subscription is still live, so her plan column stays 'lite'.
      Families::AcceptInvitation.new(invitation: invitation, user: alice).call
      alice.reload
    end

    it 'safe_settings treats the joining member as non-lite, matching the write path' do
      # Default enabled_map_layers is ['Tracks', 'Heatmap']; a lite user would
      # have 'Heatmap' (a gated layer) stripped down to ['Tracks'].
      expect(alice.safe_settings.globe_projection).to eq(true)
      expect(alice.safe_settings.enabled_map_layers).to include('Heatmap')
    end

    describe 'GET /api/v1/settings' do
      before do
        alice.update!(
          settings: alice.settings.merge(
            'globe_projection' => true,
            'enabled_map_layers' => ['Tracks', 'Heatmap', 'Fog of War', 'Scratch map'],
            'maps' => alice.settings.fetch('maps', {}).merge(
              'hidden_tile_categories' => ['roads'],
              'disabled_poi_groups' => ['shopping']
            )
          )
        )
      end

      it 'returns gated map settings intact, mirroring write-path entitlements' do
        get "/api/v1/settings?api_key=#{api_key}"

        expect(response).to have_http_status(:success)
        body = response.parsed_body['settings']

        expect(body['globe_projection']).to eq(true)
        expect(body['enabled_map_layers']).to include('Heatmap', 'Fog of War', 'Scratch map')
        expect(body['maps']['hidden_tile_categories']).to eq(['roads'])
        expect(body['maps']['disabled_poi_groups']).to eq(['shopping'])
      end
    end

    describe 'PATCH /api/v1/settings' do
      it 'persists and returns globe_projection=true in the same response' do
        patch "/api/v1/settings?api_key=#{api_key}",
              params: { settings: { globe_projection: true } }

        expect(response).to have_http_status(:success)
        body = response.parsed_body

        expect(alice.reload.settings['globe_projection'].to_s).to eq('true')
        expect(body['settings']['globe_projection']).to eq(true)
        expect(alice.reload.safe_settings.globe_projection).to eq(true)
      end

      it 'persists and returns gated map layers in the same response' do
        patch "/api/v1/settings?api_key=#{api_key}",
              params: { settings: { enabled_map_layers: ['Tracks', 'Heatmap', 'Fog of War'] } }

        expect(response).to have_http_status(:success)
        body = response.parsed_body

        expect(alice.reload.settings['enabled_map_layers']).to include('Fog of War')
        expect(body['settings']['enabled_map_layers']).to include('Fog of War', 'Heatmap')
      end

      it 'persists and returns maps customizations in the same response' do
        patch "/api/v1/settings?api_key=#{api_key}",
              params: {
                settings: {
                  maps: {
                    hidden_tile_categories: ['poi'],
                    disabled_poi_groups: ['shopping']
                  }
                }
              }

        expect(response).to have_http_status(:success)
        body = response.parsed_body

        expect(alice.reload.settings['maps']['hidden_tile_categories']).to eq(['poi'])
        expect(body['settings']['maps']).to include(
          'hidden_tile_categories' => ['poi'],
          'disabled_poi_groups' => ['shopping']
        )
      end
    end
  end

  context 'when a cloud :lite user is NOT in a family' do
    let!(:solo) { paid_lite_user(email: 'solo@example.com') }
    let(:solo_api_key) { solo.api_key }

    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'still strips gated layers on both read and write (alignment the other way)' do
      patch "/api/v1/settings?api_key=#{solo_api_key}",
            params: { settings: { enabled_map_layers: ['Tracks', 'Heatmap', 'Fog of War'] } }

      expect(response).to have_http_status(:success)
      body = response.parsed_body

      expect(solo.reload.settings['enabled_map_layers']).not_to include('Fog of War')
      expect(body['settings']['enabled_map_layers']).not_to include('Fog of War', 'Heatmap')
      expect(solo.safe_settings.globe_projection).to eq(false)
    end
  end

  context 'when self-hosted, a :lite plan user' do
    let!(:self_hosted) { create(:user, :lite_plan, skip_auto_trial: true) }
    let(:self_hosted_key) { self_hosted.api_key }

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      self_hosted.update!(settings: self_hosted.settings.merge('globe_projection' => true))
    end

    it 'is never gated on read (entitlements grant full access to self-hosted)' do
      expect(self_hosted.plan_restricted?).to be false
      expect(self_hosted.safe_settings.globe_projection).to eq(true)
      expect(self_hosted.safe_settings.enabled_map_layers).to include('Heatmap')

      get "/api/v1/settings?api_key=#{self_hosted_key}"

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['settings']['globe_projection']).to eq(true)
    end
  end

  context 'when family access lapses for a :lite family member' do
    let(:owner) { paid_family_owner(email: 'lapsed-owner@example.com') }
    let(:lapsed_member) { paid_lite_user(email: 'lapsed@example.com') }
    let(:family) { create(:family, creator: owner) }

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      create(:family_membership, :owner, family: family, user: owner)
      create(:family_membership, family: family, user: lapsed_member)
      # Owner and the family's recorded access period are both in the past, so
      # inherited_family_access? returns false.
      owner.update!(active_until: 1.month.ago)
      family.update!(access_until: 1.month.ago)
      lapsed_member.reload
    end

    it 'is gated again on read once inherited access is no longer live' do
      expect(lapsed_member.plan_restricted?).to be true
      expect(lapsed_member.safe_settings.globe_projection).to eq(false)
    end
  end

  context 'when a paid-:lite family member is removed from the family' do
    let(:owner) { paid_family_owner(email: 'rem-owner@example.com') }
    let(:member) { paid_lite_user(email: 'removed@example.com') }
    let(:family) { create(:family, creator: owner) }
    let(:invitation) { create(:family_invitation, family: family, invited_by: owner, email: member.email) }
    let(:api_key) { member.api_key }

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      create(:family_membership, :owner, family: family, user: owner)
      Families::AcceptInvitation.new(invitation: invitation, user: member).call
      # While in the family, member can persist gated settings.
      patch "/api/v1/settings?api_key=#{api_key}",
            params: { settings: { globe_projection: true, enabled_map_layers: ['Tracks', 'Heatmap', 'Fog of War'] } }
      # Then the member leaves the family.
      member.reload
      Family::Membership.find_by!(user_id: member.id).destroy!
      member.reload
    end

    it 'loses in_family? and re-gates on read AND write' do
      expect(member.in_family?).to be false
      expect(member.plan_restricted?).to be true

      # Read path strips the previously-persisted gated feature.
      expect(member.safe_settings.globe_projection).to eq(false)
      expect(member.safe_settings.enabled_map_layers).not_to include('Fog of War')

      # Write path strips too (aligned): a fresh PATCH with gated layers is
      # sanitized and the response reflects it.
      patch "/api/v1/settings?api_key=#{api_key}",
            params: { settings: { enabled_map_layers: ['Tracks', 'Heatmap', 'Scratch map'] } }

      body = response.parsed_body['settings']
      expect(member.reload.settings['enabled_map_layers']).not_to include('Scratch map')
      expect(body['enabled_map_layers']).not_to include('Scratch map', 'Heatmap')
    end
  end
end
