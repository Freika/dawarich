# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Families::Members', type: :request do
  let(:owner) { create(:user) }
  let(:member) { create(:user) }
  let(:other_member) { create(:user) }
  let(:family) { create(:family, creator: owner) }

  before do
    create(:family_membership, user: owner, family: family, role: :owner)
    create(:family_membership, user: member, family: family, role: :member)
    create(:family_membership, user: other_member, family: family, role: :member)
  end

  def json
    JSON.parse(response.body)
  end

  def remove(caller, user_id)
    delete "/api/v1/families/members/#{user_id}", headers: { 'Authorization' => "Bearer #{caller.api_key}" }
  end

  def lapse_family
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    owner.update!(plan: :family, active_until: 1.day.ago)
    family.update!(access_until: nil)
  end

  it 'lets a member leave by deleting their own id' do
    member.update_family_location_sharing!(true, duration: 'permanent')

    remove(member, member.id)

    expect(response).to have_http_status(:no_content)
    expect(member.reload.family_membership).to be_nil
    expect(member.reload.family_sharing_enabled?).to be false
  end

  it 'lets the owner remove a member' do
    remove(owner, member.id)

    expect(response).to have_http_status(:no_content)
    expect(member.reload.family).to be_nil
  end

  it 'refuses the owner removing themselves with owner_cannot_leave' do
    remove(owner, owner.id)

    expect(response).to have_http_status(:unprocessable_content)
    expect(json['error']).to eq('owner_cannot_leave')
    expect(owner.reload.family).to eq(family)
  end

  it 'refuses a member removing another member with owner_required' do
    remove(member, other_member.id)

    expect(response).to have_http_status(:forbidden)
    expect(json['error']).to eq('owner_required')
    expect(other_member.reload.family).to eq(family)
  end

  it 'refuses a member removing the owner with owner_required' do
    remove(member, owner.id)

    expect(response).to have_http_status(:forbidden)
    expect(json['error']).to eq('owner_required')
  end

  it 'returns member_not_found for a user of another family' do
    stranger = create(:user)
    create(:family_membership, user: stranger, family: create(:family), role: :member)

    remove(owner, stranger.id)

    expect(response).to have_http_status(:not_found)
    expect(json['error']).to eq('member_not_found')
    expect(stranger.reload.family).to be_present
  end

  it 'returns member_not_found for an unknown id' do
    remove(owner, 0)

    expect(response).to have_http_status(:not_found)
    expect(json['error']).to eq('member_not_found')
  end

  it 'returns 404 for a caller in no family' do
    remove(create(:user), member.id)

    expect(response).to have_http_status(:not_found)
  end

  context 'when the family has lapsed' do
    before { lapse_family }

    it 'still lets a member leave' do
      remove(member, member.id)

      expect(response).to have_http_status(:no_content)
      expect(member.reload.family).to be_nil
    end

    it 'still lets the owner remove a member' do
      remove(owner, member.id)

      expect(response).to have_http_status(:no_content)
      expect(member.reload.family).to be_nil
    end
  end
end
