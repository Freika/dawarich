# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family getting started panel', type: :request do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  let(:owner) { create(:user, plan: :family, status: :trial, active_until: 5.days.from_now) }
  let(:family) { create(:family, creator: owner, name: 'My Family') }
  let!(:owner_membership) { create(:family_membership, :owner, user: owner, family: family) }

  describe 'for an owner whose family is still empty' do
    before { sign_in owner }

    it 'renders the getting started panel' do
      get family_path

      expect(response.body).to include('id="family-getting-started"')
    end

    it 'invites them to add someone' do
      get family_path

      expect(response.body).to include(I18n.t('families.getting_started.invite_title'))
    end

    it 'says how many seats are in use' do
      get family_path

      expect(response.body).to include(
        I18n.t('families.getting_started.seats', used: 1, total: Family::MAX_MEMBERS)
      )
    end

    it 'offers the mobile apps' do
      get family_path

      expect(response.body).to include('apps.apple.com')
      expect(response.body).to include('play.google.com')
    end

    it 'says when the trial ends' do
      get family_path

      expect(response.body).to include(
        I18n.t('families.getting_started.trial_ends_on', date: I18n.l(owner.active_until.to_date, format: :long))
      )
    end
  end

  describe 'the standing invite form' do
    let(:member) { create(:user) }
    let!(:member_membership) { create(:family_membership, user: member, family: family) }

    before { sign_in owner }

    it 'keeps warning the owner that members lose access with the plan' do
      get family_path

      expect(response.body).to include(
        I18n.t('families.getting_started.members_lose_access_when_your_plan_ends')
      )
    end
  end

  describe 'once the family has another member' do
    let(:member) { create(:user) }
    let!(:member_membership) { create(:family_membership, user: member, family: family) }

    before { sign_in owner }

    it 'stops nudging the owner to invite' do
      get family_path

      expect(response.body).not_to include(I18n.t('families.getting_started.invite_title'))
    end

    it 'drops the panel once the owner is also sharing' do
      owner.update_family_location_sharing!(true)

      get family_path

      expect(response.body).not_to include('id="family-getting-started"')
    end
  end

  describe 'while an invitation is outstanding' do
    before do
      create(:family_invitation, family: family, invited_by: owner)
      sign_in owner
    end

    it 'stops nudging the owner to invite' do
      get family_path

      expect(response.body).not_to include(I18n.t('families.getting_started.invite_title'))
    end
  end

  describe 'for a member who has not started sharing' do
    let(:member) { create(:user) }
    let!(:member_membership) { create(:family_membership, user: member, family: family) }

    before { sign_in member }

    it 'asks them to turn sharing on' do
      get family_path

      expect(response.body).to include(I18n.t('families.getting_started.sharing_title'))
    end

    it 'offers the mobile apps' do
      get family_path

      expect(response.body).to include('apps.apple.com')
    end

    it 'does not show the owner invite panel' do
      get family_path

      expect(response.body).not_to include(I18n.t('families.getting_started.invite_title'))
    end
  end

  describe 'on a self-hosted instance where families are unlimited' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      sign_in owner
    end

    it 'still offers the getting started panel' do
      get family_path

      expect(response.body).to include('id="family-getting-started"')
    end

    it 'does not advertise a seat cap' do
      get family_path

      expect(response.body).not_to include(
        I18n.t('families.getting_started.seats', used: 1, total: Family::MAX_MEMBERS)
      )
    end
  end

  describe 'when a member turns sharing on' do
    let(:member) { create(:user) }
    let!(:member_membership) { create(:family_membership, user: member, family: family) }

    before { sign_in member }

    it 'stands the panel down without needing a page reload' do
      patch location_sharing_family_path,
            params: { enabled: 'true' },
            headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response.body).to include('family-getting-started-slot')
      expect(response.body).not_to include(I18n.t('families.getting_started.sharing_title'))
    end
  end

  describe 'for a member who is already sharing' do
    let(:member) { create(:user) }
    let!(:member_membership) { create(:family_membership, user: member, family: family) }

    before do
      member.update_family_location_sharing!(true)
      sign_in member
    end

    it 'drops the panel entirely' do
      get family_path

      expect(response.body).not_to include('id="family-getting-started"')
    end
  end
end
