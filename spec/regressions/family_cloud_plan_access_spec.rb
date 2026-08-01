# frozen_string_literal: true

require 'rails_helper'

# Regression: the family feature was gated on `self_hosted?`, so cloud users who
# paid for the Family plan received 403s (and 404s on routes) on every family
# path, while the upgrade CTA they were sent to was itself unreachable.
# Access must follow the subscription plan, not the hosting mode.
RSpec.describe 'Family access on cloud', type: :request do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  describe 'a subscriber on the family plan' do
    let(:subscriber) { create(:user, plan: :family, skip_auto_trial: true) }

    it 'reaches the family creation form' do
      sign_in subscriber

      get new_family_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="family[name]"')
    end

    it 'creates a family' do
      sign_in subscriber

      expect { post family_path, params: { family: { name: 'The Burmakins' } } }
        .to change(Family, :count).by(1)

      expect(response).to redirect_to(family_path)
    end

    it 'reaches the family page' do
      family = create(:family, creator: subscriber)
      create(:family_membership, user: subscriber, family: family, role: :owner)
      sign_in subscriber

      get family_path

      expect(response).to have_http_status(:ok)
    end

    it 'reaches the family locations API' do
      family = create(:family, creator: subscriber)
      create(:family_membership, user: subscriber, family: family, role: :owner)

      get '/api/v1/families/locations', params: { api_key: subscriber.api_key }

      expect(response).to have_http_status(:ok)
    end

    it 'can delete the family after the plan lapses' do
      family = create(:family, creator: subscriber)
      create(:family_membership, user: subscriber, family: family, role: :owner)
      subscriber.update!(plan: :pro)
      sign_in subscriber

      expect { delete family_path }.to change(Family, :count).by(-1)

      expect(response).to redirect_to(new_family_path)
    end
  end

  describe 'a user without the family plan' do
    let(:non_subscriber) { create(:user, plan: :pro, skip_auto_trial: true) }

    before { stub_const('MANAGER_URL', 'https://manager.example.com') }

    it 'is offered the upgrade instead of a 403' do
      sign_in non_subscriber

      get new_family_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Upgrade to Family')
      expect(response.body).not_to include('name="family[name]"')
    end

    it 'cannot create a family' do
      sign_in non_subscriber

      expect { post family_path, params: { family: { name: 'Freeloaders' } } }
        .not_to change(Family, :count)

      expect(response).to redirect_to(new_family_path)
    end

    it 'is refused by the family locations API' do
      get '/api/v1/families/locations', params: { api_key: non_subscriber.api_key }

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('family_plan_required')
    end

    it 'is not shown the family link in the navbar' do
      sign_in non_subscriber

      get stats_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(new_family_path)
    end
  end

  # The owner buys the plan; the people they invite do not. Requiring the plan
  # from members would make the plan itself useless.
  describe 'a member of someone else\'s family' do
    let(:owner) { create(:user, plan: :family, skip_auto_trial: true) }
    let(:family) { create(:family, creator: owner) }
    let(:member) { create(:user, plan: :pro, skip_auto_trial: true) }

    before do
      create(:family_membership, user: owner, family: family, role: :owner)
      stub_const('MANAGER_URL', 'https://manager.example.com')
    end

    it 'can accept an invitation without holding the plan' do
      invitation = create(:family_invitation, family: family, invited_by: owner, email: member.email)
      sign_in member

      expect { post accept_family_invitation_path(token: invitation.token) }
        .to change { member.reload.family }.from(nil).to(family)
    end

    it 'reaches the family page' do
      create(:family_membership, user: member, family: family)
      sign_in member

      get family_path

      expect(response).to have_http_status(:ok)
    end

    it 'reaches the family locations API' do
      create(:family_membership, user: member, family: family)

      get '/api/v1/families/locations', params: { api_key: member.api_key }

      expect(response).to have_http_status(:ok)
    end

    it 'loses access when the owner stops paying' do
      membership = create(:family_membership, user: member, family: family)
      owner.update!(plan: :pro)
      sign_in member

      get family_path

      expect(response).to redirect_to(new_family_path)

      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('no longer active')
      expect(response.body).to include(family_member_path(membership))
    end

    it 'shows the lapsed owner member removal and family deletion controls' do
      membership = create(:family_membership, user: member, family: family)
      owner.update!(plan: :pro)
      sign_in owner

      get new_family_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(family_member_path(membership))
      expect(response.body).to include('Delete Family')
    end

    it 'keeps the removal notice when a lapsed owner removes a member' do
      membership = create(:family_membership, user: member, family: family)
      owner.update!(plan: :pro)
      sign_in owner

      delete family_member_path(membership)

      expect(response).to redirect_to(new_family_path)
      expect(flash[:notice]).to include('removed')
    end

    it 'keeps the Family link in the navbar for members of a lapsed family' do
      create(:family_membership, user: member, family: family)
      owner.update!(plan: :pro)
      sign_in member

      get stats_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(new_family_path)
    end

    it 'lets a member of a lapsed family turn off location sharing' do
      create(:family_membership, user: member, family: family)
      member.update_family_location_sharing!(true)
      owner.update!(plan: :pro)
      sign_in member

      patch location_sharing_family_path, params: { enabled: 'false' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(member.reload.family_sharing_enabled?).to be(false)
    end

    it 'lets a lapsed owner revoke a pending invitation' do
      invitation = create(:family_invitation, family: family, invited_by: owner, email: 'someone@example.com')
      owner.update!(plan: :pro)
      sign_in owner

      expect { delete family_invitation_path(invitation.token) }
        .to change { invitation.reload.status }.from('pending').to('cancelled')

      expect(response).to redirect_to(new_family_path)
      expect(flash[:notice]).to eq('Invitation cancelled')
    end

    it 'keeps the alert when a lapsed owner deletes a family that still has members' do
      create(:family_membership, user: member, family: family)
      owner.update!(plan: :pro)
      sign_in owner

      expect { delete family_path }.not_to change(Family, :count)

      expect(response).to redirect_to(new_family_path)
      expect(flash[:alert]).to include('Cannot delete family with members')
    end

    it 'can leave the family after the owner stops paying' do
      membership = create(:family_membership, user: member, family: family)
      owner.update!(plan: :pro)
      sign_in member

      expect { delete family_member_path(membership) }
        .to change { member.reload.family }.from(family).to(nil)

      expect(response).to redirect_to(new_family_path)
    end

    it 'cannot accept an invitation into a family whose plan has lapsed' do
      invitation = create(:family_invitation, family: family, invited_by: owner, email: member.email)
      owner.update!(plan: :pro)
      sign_in member

      expect { post accept_family_invitation_path(token: invitation.token) }
        .not_to change(Family::Membership, :count)

      expect(response).to redirect_to(root_path)
    end
  end

  describe 'non-HTML requests against the web guard' do
    let(:non_subscriber) { create(:user, plan: :pro, skip_auto_trial: true) }

    it 'returns JSON 403 for JSON requests' do
      sign_in non_subscriber

      get family_path(format: :json)

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('family_plan_required')
    end

    it 'redirects turbo stream requests to the upgrade page' do
      sign_in non_subscriber

      get family_path, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to redirect_to(new_family_path)
      expect(response).to have_http_status(:see_other)
    end
  end

  describe 'self-hosted instances' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

    it 'keeps the family feature open to every plan' do
      user = create(:user, plan: :lite)
      sign_in user

      get new_family_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="family[name]"')
    end
  end
end
