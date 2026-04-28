# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GapfillPolicy, type: :policy do
  let(:user) { create(:user) }

  describe 'preview?' do
    it 'allows authenticated users' do
      policy = GapfillPolicy.new(user, :gapfill)

      expect(policy).to permit(:preview)
    end

    it 'denies unauthenticated users' do
      policy = GapfillPolicy.new(nil, :gapfill)

      expect(policy).not_to permit(:preview)
    end
  end

  describe 'create?' do
    it 'allows authenticated users' do
      policy = GapfillPolicy.new(user, :gapfill)

      expect(policy).to permit(:create)
    end

    it 'denies unauthenticated users' do
      policy = GapfillPolicy.new(nil, :gapfill)

      expect(policy).not_to permit(:create)
    end
  end
end
