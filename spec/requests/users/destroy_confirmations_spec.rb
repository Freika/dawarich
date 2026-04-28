# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::DestroyConfirmations', type: :request do
  describe 'GET /users/me/destroy/confirm' do
    let(:user) { create(:user) }

    before { Rails.cache.clear }

    it 'soft-deletes the user and queues hard deletion on a valid token' do
      token = Users::IssueDestroyToken.new(user).call

      expect do
        get '/users/me/destroy/confirm', params: { token: token }
      end.to have_enqueued_job(Users::DestroyJob).with(user.id)

      expect(user.reload.deleted_at).to be_present
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:notice]).to match(/scheduled for deletion/i)
    end

    it 'rejects a replayed token (atomic single-use)' do
      token = Users::IssueDestroyToken.new(user).call
      get '/users/me/destroy/confirm', params: { token: token } # consume

      another = create(:user)
      another_token = Users::IssueDestroyToken.new(another).call

      # Same token twice → second click rejected (already-used flash)
      get '/users/me/destroy/confirm', params: { token: token }
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to match(/already been used/i)

      # Sanity: a fresh token still works for a different user
      get '/users/me/destroy/confirm', params: { token: another_token }
      expect(another.reload.deleted_at).to be_present
    end

    it 'rejects a token with the wrong purpose' do
      payload = { user_id: user.id, purpose: 'something_else', jti: SecureRandom.uuid,
                  iat: Time.now.to_i, exp: 1.hour.from_now.to_i }
      token = JWT.encode(payload, ENV.fetch('JWT_SECRET_KEY'), 'HS256')

      get '/users/me/destroy/confirm', params: { token: token }

      expect(user.reload.deleted_at).to be_nil
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'rejects deletion when the user owns a family with other members' do
      family = create(:family, creator: user)
      create(:family_membership, family: family, user: user, role: :owner)
      create(:family_membership, family: family, user: create(:user), role: :member)

      token = Users::IssueDestroyToken.new(user).call

      get '/users/me/destroy/confirm', params: { token: token }

      expect(user.reload.deleted_at).to be_nil
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to match(/family/i)
    end

    it 'rejects an invalid/garbage token' do
      get '/users/me/destroy/confirm', params: { token: 'not-a-real-token' }

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to match(/invalid|expired/i)
    end
  end
end
