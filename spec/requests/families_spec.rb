# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Families', type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let!(:membership) { create(:family_membership, user: user, family: family, role: :owner) }

  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
    sign_in user
  end

  describe 'GET /families' do
    context 'when user is not in a family' do
      let(:user_without_family) { create(:user) }

      before { sign_in user_without_family }

      it 'renders the index page' do
        get '/families'
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when user is in a family' do
      it 'redirects to family show page' do
        get '/families'
        expect(response).to redirect_to(family_path(family))
      end
    end
  end

  describe 'GET /families/:id' do
    it 'shows the family page' do
      get "/families/#{family.id}"
      expect(response).to have_http_status(:ok)
    end

    context 'when user is not in the family' do
      let(:outsider) { create(:user) }

      before { sign_in outsider }

      it 'redirects to families index' do
        get "/families/#{family.id}"
        expect(response).to redirect_to(families_path)
      end
    end
  end

  describe 'GET /families/new' do
    context 'when user is not in a family' do
      let(:user_without_family) { create(:user) }

      before { sign_in user_without_family }

      it 'renders the new family form' do
        get '/families/new'
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when user is already in a family' do
      it 'redirects to family show page' do
        get '/families/new'
        expect(response).to redirect_to(family_path(family))
      end
    end
  end

  describe 'POST /families' do
    let(:user_without_family) { create(:user) }

    before { sign_in user_without_family }

    context 'with valid attributes' do
      let(:valid_attributes) { { family: { name: 'Test Family' } } }

      it 'creates a new family' do
        expect do
          post '/families', params: valid_attributes
        end.to change(Family, :count).by(1)
      end

      it 'creates a family membership for the user' do
        expect do
          post '/families', params: valid_attributes
        end.to change(FamilyMembership, :count).by(1)
      end

      it 'redirects to the new family with success message' do
        post '/families', params: valid_attributes
        expect(response).to have_http_status(:found)
        expect(response.location).to match(%r{/families/})
        follow_redirect!
        expect(response.body).to include('Family created successfully!')
      end
    end

    context 'with invalid attributes' do
      let(:invalid_attributes) { { family: { name: '' } } }

      it 'does not create a family' do
        expect do
          post '/families', params: invalid_attributes
        end.not_to change(Family, :count)
      end

      it 'renders the new template with errors' do
        post '/families', params: invalid_attributes
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'GET /families/:id/edit' do
    it 'shows the edit form' do
      get "/families/#{family.id}/edit"
      expect(response).to have_http_status(:ok)
    end

    context 'when user is not the owner' do
      before { membership.update!(role: :member) }

      it 'redirects due to authorization failure' do
        get "/families/#{family.id}/edit"
        expect(response).to have_http_status(:see_other)
        expect(flash[:alert]).to include('not authorized')
      end
    end
  end

  describe 'PATCH /families/:id' do
    let(:new_attributes) { { family: { name: 'Updated Family Name' } } }

    context 'with valid attributes' do
      it 'updates the family' do
        patch "/families/#{family.id}", params: new_attributes
        family.reload
        expect(family.name).to eq('Updated Family Name')
        expect(response).to redirect_to(family_path(family))
      end
    end

    context 'with invalid attributes' do
      let(:invalid_attributes) { { family: { name: '' } } }

      it 'does not update the family' do
        original_name = family.name
        patch "/families/#{family.id}", params: invalid_attributes
        family.reload
        expect(family.name).to eq(original_name)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when user is not the owner' do
      before { membership.update!(role: :member) }

      it 'redirects due to authorization failure' do
        patch "/families/#{family.id}", params: new_attributes
        expect(response).to have_http_status(:see_other)
        expect(flash[:alert]).to include('not authorized')
      end
    end
  end

  describe 'DELETE /families/:id' do
    context 'when family has only one member' do
      it 'deletes the family' do
        expect do
          delete "/families/#{family.id}"
        end.to change(Family, :count).by(-1)
        expect(response).to redirect_to(families_path)
      end
    end

    context 'when family has multiple members' do
      before do
        create(:family_membership, user: other_user, family: family, role: :member)
      end

      it 'does not delete the family' do
        expect do
          delete "/families/#{family.id}"
        end.not_to change(Family, :count)
        expect(response).to redirect_to(family_path(family))
        follow_redirect!
        expect(response.body).to include('Cannot delete family with members')
      end
    end

    context 'when user is not the owner' do
      before { membership.update!(role: :member) }

      it 'redirects due to authorization failure' do
        delete "/families/#{family.id}"
        expect(response).to have_http_status(:see_other)
        expect(flash[:alert]).to include('not authorized')
      end
    end
  end

  describe 'DELETE /families/:id/leave' do
    context 'when user is not the owner' do
      before { membership.update!(role: :member) }

      it 'allows user to leave the family' do
        expect do
          delete "/families/#{family.id}/leave"
        end.to change { user.reload.family }.from(family).to(nil)
        expect(response).to redirect_to(families_path)
      end
    end

    context 'when user is the owner with other members' do
      before do
        create(:family_membership, user: other_user, family: family, role: :member)
      end

      it 'prevents leaving and shows error message' do
        expect do
          delete "/families/#{family.id}/leave"
        end.not_to(change { user.reload.family })
        expect(response).to redirect_to(family_path(family))
        follow_redirect!
        expect(response.body).to include('cannot leave')
      end
    end

    context 'when user is the only owner' do
      it 'allows leaving and deletes the family' do
        expect do
          delete "/families/#{family.id}/leave"
        end.to change(Family, :count).by(-1)
        expect(response).to redirect_to(families_path)
      end
    end
  end

  describe 'authorization for outsiders' do
    let(:outsider) { create(:user) }

    before { sign_in outsider }

    it 'denies access to show when user is not in family' do
      get "/families/#{family.id}"
      expect(response).to redirect_to(families_path)
    end

    it 'redirects to families index when user is not in family for edit' do
      get "/families/#{family.id}/edit"
      expect(response).to redirect_to(families_path)
    end

    it 'redirects to families index when user is not in family for update' do
      patch "/families/#{family.id}", params: { family: { name: 'Hacked' } }
      expect(response).to redirect_to(families_path)
    end

    it 'redirects to families index when user is not in family for destroy' do
      delete "/families/#{family.id}"
      expect(response).to redirect_to(families_path)
    end

    it 'redirects to families index when user is not in family for leave' do
      delete "/families/#{family.id}/leave"
      expect(response).to redirect_to(families_path)
    end
  end

  describe 'authentication required' do
    before { sign_out user }

    it 'redirects to login for index' do
      get '/families'
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirects to login for show' do
      get "/families/#{family.id}"
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirects to login for new' do
      get '/families/new'
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirects to login for create' do
      post '/families', params: { family: { name: 'Test' } }
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirects to login for edit' do
      get "/families/#{family.id}/edit"
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirects to login for update' do
      patch "/families/#{family.id}", params: { family: { name: 'Test' } }
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirects to login for destroy' do
      delete "/families/#{family.id}"
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirects to login for leave' do
      delete "/families/#{family.id}/leave"
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
