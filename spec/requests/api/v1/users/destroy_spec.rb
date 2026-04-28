# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Users::Destroy', type: :request do
  describe 'DELETE /api/v1/users/me' do
    let(:user) { create(:user) }
    let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

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
  end
end
