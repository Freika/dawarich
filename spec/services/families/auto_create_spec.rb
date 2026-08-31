# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::AutoCreate do
  subject(:service) { described_class.new(user: user) }

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  let(:user) { create(:user, plan: :family, status: :trial, active_until: 7.days.from_now) }

  describe 'for a family-plan user without a family' do
    it 'creates a family' do
      expect { service.call }.to change(Family, :count).by(1)
    end

    it 'returns true' do
      expect(service.call).to be true
    end

    it 'makes the user its owner' do
      service.call

      expect(user.reload.family_owner?).to be true
    end

    it 'names the family with the localised default' do
      service.call

      expect(user.reload.family.name).to eq(I18n.t('services.families.auto_create.default_name'))
    end

    it 'names the family in the owner locale' do
      user.update!(settings: user.settings.merge('locale' => 'de'))

      service.call

      expect(user.reload.family.name).to eq(I18n.t('services.families.auto_create.default_name', locale: :de))
    end

    it 'turns the owner location sharing on' do
      service.call

      expect(user.reload.family_sharing_enabled?).to be true
    end

    it 'shares indefinitely rather than for a fixed window' do
      service.call

      expect(user.reload.family_sharing_expires_at).to be_nil
    end

    it 'leaves history sharing off' do
      service.call

      expect(user.reload.family_share_history?).to be false
    end

    it 'notifies the owner' do
      expect { service.call }.to change(user.notifications, :count).by(1)
    end

    it 'tells the owner the plan is ready rather than that they created it' do
      service.call

      expect(user.notifications.last.title)
        .to eq(I18n.t('services.families.auto_create.notification_title'))
    end

    it 'points the owner at the seats they can fill' do
      service.call

      expect(user.notifications.last.content).to include((Family::MAX_MEMBERS - 1).to_s)
    end

    it 'names the family in the notification' do
      service.call

      expect(user.notifications.last.content).to include(user.reload.family.name)
    end

    it 'creates only one family when run twice' do
      service.call

      expect { described_class.new(user: user.reload).call }.not_to change(Family, :count)
    end
  end

  describe 'when a family should not be created' do
    it 'skips a user who already owns a family' do
      family = create(:family, creator: user)
      create(:family_membership, :owner, user: user, family: family)

      expect { service.call }.not_to change(Family, :count)
    end

    it 'skips a user who is a member of someone else family' do
      other_family = create(:family)
      create(:family_membership, user: user, family: other_family)

      expect { service.call }.not_to change(Family, :count)
    end

    it 'skips a user who is not on the family plan' do
      user.update!(plan: :pro)

      expect { service.call }.not_to change(Family, :count)
    end

    it 'skips self-hosted instances' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

      expect { service.call }.not_to change(Family, :count)
    end

    it 'returns false' do
      user.update!(plan: :pro)

      expect(service.call).to be false
    end
  end
end
