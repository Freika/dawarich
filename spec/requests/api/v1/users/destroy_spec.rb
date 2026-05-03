# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Users::Destroy', type: :request do
  describe 'DELETE /api/v1/users/me' do
    let(:user) { create(:user, password: 'secret123456') }
    let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

    before do
      Rails.cache.clear
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    end

    it 'does NOT delete the user immediately — sends a confirmation email instead' do
      user # materialize before request

      expect do
        delete '/api/v1/users/me', headers: headers
      end.not_to(change(User.unscoped, :count))

      expect(User.unscoped.find_by(id: user.id)).to be_present
      expect(user.reload.deleted_at).to be_nil
    end

    it 'enqueues the account-destroy confirmation email' do
      expect do
        delete '/api/v1/users/me', headers: headers
      end.to have_enqueued_job(Users::MailerSendingJob).with(
        user.id, 'account_destroy_confirmation', hash_including(:link_url)
      )
    end

    it 'returns 202 with a confirmation message' do
      delete '/api/v1/users/me', headers: headers

      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)['message']).to include('confirmation email')
    end

    it 'returns 401 without auth' do
      delete '/api/v1/users/me'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'embeds a verifiable destroy token in the link_url' do
      delete '/api/v1/users/me', headers: headers

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.find do |j|
        j[:job] == Users::MailerSendingJob && j[:args][1] == 'account_destroy_confirmation'
      end
      link_url = enqueued[:args].last['link_url']
      token = URI.decode_www_form(URI.parse(link_url).query).to_h['token']

      result = Users::VerifyDestroyToken.new(token).call
      expect(result.user).to eq(user)
    end

    it 'rate-limits a second destroy request to 429 within the window' do
      delete '/api/v1/users/me', headers: headers
      delete '/api/v1/users/me', headers: headers

      expect(response).to have_http_status(:too_many_requests)
      expect(JSON.parse(response.body)['error']).to eq('rate_limited')
    end

    context 'in self-hosted mode' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'soft-deletes immediately when password is correct (no email)' do
        expect do
          delete '/api/v1/users/me', params: { password: 'secret123456' }, headers: headers
        end.to have_enqueued_job(Users::DestroyJob).with(user.id)

        expect(response).to have_http_status(:ok)
        expect(user.reload.deleted_at).to be_present
      end

      it 'does NOT enqueue an email in self-hosted mode' do
        expect do
          delete '/api/v1/users/me', params: { password: 'secret123456' }, headers: headers
        end.not_to have_enqueued_job(Users::MailerSendingJob)
      end

      it 'returns 401 without password' do
        delete '/api/v1/users/me', headers: headers

        expect(response).to have_http_status(:unauthorized)
        expect(user.reload.deleted_at).to be_nil
      end

      it 'returns 401 with wrong password' do
        delete '/api/v1/users/me', params: { password: 'wrong' }, headers: headers

        expect(response).to have_http_status(:unauthorized)
        expect(user.reload.deleted_at).to be_nil
      end
    end

    context 'when the user owns a family with other members' do
      let(:family) { create(:family, creator: user) }

      before do
        create(:family_membership, family: family, user: user, role: :owner)
        create(:family_membership, family: family, user: create(:user), role: :member)
      end

      it 'returns 422 and does NOT soft-delete (cloud)' do
        delete '/api/v1/users/me', headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)['error']).to eq('cannot_delete_account')
        expect(user.reload.deleted_at).to be_nil
      end

      it 'does NOT enqueue the confirmation email when blocked (cloud)' do
        expect do
          delete '/api/v1/users/me', headers: headers
        end.not_to have_enqueued_job(Users::MailerSendingJob)
      end

      it 'returns 422 and does NOT soft-delete (self-hosted)' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

        delete '/api/v1/users/me', params: { password: 'secret123456' }, headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(user.reload.deleted_at).to be_nil
      end

      it 'does NOT enqueue Users::DestroyJob when blocked (self-hosted)' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

        expect do
          delete '/api/v1/users/me', params: { password: 'secret123456' }, headers: headers
        end.not_to have_enqueued_job(Users::DestroyJob)
      end

      it 'rejects regardless of password validity (self-hosted)' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

        delete '/api/v1/users/me', params: { password: 'wrong' }, headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(user.reload.deleted_at).to be_nil
      end
    end
  end
end
