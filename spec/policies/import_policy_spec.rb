# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImportPolicy, type: :policy do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:import) { create(:import, user: user) }
  let(:other_import) { create(:import, user: other_user) }

  describe 'index?' do
    it 'allows authenticated users' do
      policy = ImportPolicy.new(user, Import)

      expect(policy).to permit(:index)
    end

    it 'denies unauthenticated users' do
      policy = ImportPolicy.new(nil, Import)

      expect(policy).not_to permit(:index)
    end
  end

  describe 'show?' do
    it 'allows users to view their own imports' do
      policy = ImportPolicy.new(user, import)

      expect(policy).to permit(:show)
    end

    it 'denies users from viewing other users imports' do
      policy = ImportPolicy.new(user, other_import)

      expect(policy).not_to permit(:show)
    end

    it 'denies unauthenticated users' do
      policy = ImportPolicy.new(nil, import)

      expect(policy).not_to permit(:show)
    end
  end

  describe 'new?' do
    context 'when the user subscription window is open' do
      it 'allows users to access new imports form' do
        policy = ImportPolicy.new(user, Import.new)

        expect(policy).to permit(:new)
      end
    end

    context 'when the user subscription window has closed' do
      let(:user) { create(:user).tap { |u| u.update!(status: :inactive, active_until: 1.day.ago) } }

      it 'denies users from accessing new imports form' do
        policy = ImportPolicy.new(user, Import.new)

        expect(policy).not_to permit(:new)
      end
    end

    context 'when an expired trial user has status: trial but active_until in the past' do
      let(:user) do
        create(:user).tap { |u| u.update_columns(status: User.statuses[:trial], active_until: 6.days.ago) }
      end

      it 'denies access to new imports form — gates must not diverge from create' do
        policy = ImportPolicy.new(user, Import.new)

        expect(user).to be_trial
        expect(user.active_until).to be_past
        expect(policy).not_to permit(:new)
      end
    end

    it 'denies unauthenticated users' do
      policy = ImportPolicy.new(nil, Import.new)

      expect(policy).not_to permit(:new)
    end
  end

  describe 'create?' do
    context 'when the user subscription window is open' do
      it 'allows users to create imports' do
        policy = ImportPolicy.new(user, Import.new)

        expect(policy).to permit(:create)
      end
    end

    context 'when the user subscription window has closed' do
      let(:user) { create(:user).tap { |u| u.update!(status: :inactive, active_until: 1.day.ago) } }

      it 'denies users from creating imports' do
        policy = ImportPolicy.new(user, Import.new)

        expect(policy).not_to permit(:create)
      end
    end

    context 'when an expired trial user has status: trial but active_until in the past' do
      let(:user) do
        create(:user).tap { |u| u.update_columns(status: User.statuses[:trial], active_until: 6.days.ago) }
      end

      it 'denies import creation — matches authenticate_active_user!' do
        policy = ImportPolicy.new(user, Import.new)

        expect(user).to be_trial
        expect(user.active_until).to be_past
        expect(policy).not_to permit(:create)
      end
    end

    it 'denies unauthenticated users' do
      policy = ImportPolicy.new(nil, Import.new)

      expect(policy).not_to permit(:create)
    end
  end

  describe 'update?' do
    it 'allows users to update their own imports' do
      policy = ImportPolicy.new(user, import)

      expect(policy).to permit(:update)
    end

    it 'denies users from updating other users imports' do
      policy = ImportPolicy.new(user, other_import)

      expect(policy).not_to permit(:update)
    end

    it 'denies unauthenticated users' do
      policy = ImportPolicy.new(nil, import)

      expect(policy).not_to permit(:update)
    end
  end

  describe 'destroy?' do
    it 'allows users to destroy their own imports' do
      policy = ImportPolicy.new(user, import)

      expect(policy).to permit(:destroy)
    end

    it 'denies users from destroying other users imports' do
      policy = ImportPolicy.new(user, other_import)

      expect(policy).not_to permit(:destroy)
    end

    it 'denies unauthenticated users' do
      policy = ImportPolicy.new(nil, import)

      expect(policy).not_to permit(:destroy)
    end
  end

  describe 'Scope' do
    let!(:user_import1) { create(:import, user: user) }
    let!(:user_import2) { create(:import, user: user) }
    let!(:other_user_import) { create(:import, user: other_user) }

    it 'returns only the users imports' do
      scope = ImportPolicy::Scope.new(user, Import).resolve

      expect(scope).to contain_exactly(user_import1, user_import2)
      expect(scope).not_to include(other_user_import)
    end

    it 'returns no imports for unauthenticated users' do
      scope = ImportPolicy::Scope.new(nil, Import).resolve

      expect(scope).to be_empty
    end
  end
end
