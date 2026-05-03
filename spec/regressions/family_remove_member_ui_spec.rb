# frozen_string_literal: true

require 'rails_helper'

# Verifies the family show page exposes the per-member remove action to the
# family owner. The backend (route, controller, service, policy) supports
# member removal, but the view is missing the button — leaving owners unable
# to clean up the family before deletion.
RSpec.describe 'Family#show member-remove action', type: :request do
  let(:owner) { create(:user) }
  let(:family) { create(:family, creator: owner) }
  let!(:owner_membership) { create(:family_membership, user: owner, family: family, role: :owner) }

  let(:other_member) { create(:user) }
  let!(:other_member_membership) do
    create(:family_membership, user: other_member, family: family, role: :member)
  end

  before { sign_in owner }

  it 'renders a remove control targeted at the other member when the owner views the family' do
    get family_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(family_member_path(other_member_membership)),
                             'Family#show should render a DELETE link/button to ' \
                             "#{family_member_path(other_member_membership)} so the owner can"
  end
end
