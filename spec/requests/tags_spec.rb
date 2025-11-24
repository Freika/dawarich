# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Tags", type: :request do
  let(:user) { create(:user) }
  let(:tag) { create(:tag, user: user) }
  let(:valid_attributes) { { name: 'Home', icon: '🏠', color: '#4CAF50' } }
  let(:invalid_attributes) { { name: '', icon: 'X', color: 'invalid' } }

  before { sign_in user }

  describe "GET /tags" do
    it "returns success" do
      get tags_path
      expect(response).to be_successful
    end

    it "displays user's tags" do
      tag1 = create(:tag, user: user, name: 'Work')
      tag2 = create(:tag, user: user, name: 'Home')

      get tags_path
      expect(response.body).to include('Work')
      expect(response.body).to include('Home')
    end

    it "does not display other users' tags" do
      other_user = create(:user)
      other_tag = create(:tag, user: other_user, name: 'Private')

      get tags_path
      expect(response.body).not_to include('Private')
    end
  end

  describe "GET /tags/new" do
    it "returns success" do
      get new_tag_path
      expect(response).to be_successful
    end
  end

  describe "GET /tags/:id/edit" do
    it "returns success" do
      get edit_tag_path(tag)
      expect(response).to be_successful
    end

    it "prevents editing other users' tags" do
      other_tag = create(:tag, user: create(:user))

      get edit_tag_path(other_tag)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /tags" do
    context "with valid parameters" do
      it "creates a new tag" do
        expect {
          post tags_path, params: { tag: valid_attributes }
        }.to change(Tag, :count).by(1)
      end

      it "redirects to tags index" do
        post tags_path, params: { tag: valid_attributes }
        expect(response).to redirect_to(tags_path)
      end

      it "associates tag with current user" do
        post tags_path, params: { tag: valid_attributes }
        expect(Tag.last.user).to eq(user)
      end
    end

    context "with invalid parameters" do
      it "does not create a new tag" do
        expect {
          post tags_path, params: { tag: invalid_attributes }
        }.not_to change(Tag, :count)
      end

      it "returns unprocessable entity status" do
        post tags_path, params: { tag: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PATCH /tags/:id" do
    context "with valid parameters" do
      let(:new_attributes) { { name: 'Updated Name', color: '#FF0000' } }

      it "updates the tag" do
        patch tag_path(tag), params: { tag: new_attributes }
        tag.reload
        expect(tag.name).to eq('Updated Name')
        expect(tag.color).to eq('#FF0000')
      end

      it "redirects to tags index" do
        patch tag_path(tag), params: { tag: new_attributes }
        expect(response).to redirect_to(tags_path)
      end
    end

    context "with invalid parameters" do
      it "returns unprocessable entity status" do
        patch tag_path(tag), params: { tag: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    it "prevents updating other users' tags" do
      other_tag = create(:tag, user: create(:user))

      patch tag_path(other_tag), params: { tag: { name: 'Hacked' } }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /tags/:id" do
    it "destroys the tag" do
      tag_to_delete = create(:tag, user: user)

      expect {
        delete tag_path(tag_to_delete)
      }.to change(Tag, :count).by(-1)
    end

    it "redirects to tags index" do
      delete tag_path(tag)
      expect(response).to redirect_to(tags_path)
    end

    it "prevents deleting other users' tags" do
      other_tag = create(:tag, user: create(:user))

      delete tag_path(other_tag)
      expect(response).to have_http_status(:not_found)
    end
  end

  context "when not authenticated" do
    before { sign_out user }

    it "redirects to sign in for index" do
      get tags_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects to sign in for new" do
      get new_tag_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects to sign in for create" do
      post tags_path, params: { tag: valid_attributes }
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
