# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public shares belonging to deleted users', type: :request do
  let(:user) { create(:user) }

  it 'refuses a monthly share after its owner is soft-deleted' do
    stat = create(:stat, :with_sharing_enabled, user:, year: 2024, month: 6)
    user.mark_as_deleted!

    get shared_stat_path(stat.sharing_uuid)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t('controllers.shared.stats.shared_stats_not_found_or_no_longer_available'))
  end

  it 'refuses a yearly share after its owner is soft-deleted' do
    digest = create(:users_digest, :with_sharing_enabled, user:, year: 2024)
    user.mark_as_deleted!

    get shared_users_digest_path(digest.sharing_uuid)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t('controllers.shared.digests.shared_digest_not_found_or_no_longer_available'))
  end
end
