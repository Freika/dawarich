# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'User family auto-creation', type: :model do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    ActiveJob::Base.queue_adapter = :test
  end

  let(:user) { create(:user, plan: :pro, status: :trial, active_until: 7.days.from_now) }

  describe 'when the plan becomes family' do
    it 'enqueues the auto-creation job' do
      expect { user.update!(plan: :family) }
        .to have_enqueued_job(Families::AutoCreationJob).with(user.id)
    end

    it 'creates the family when the job runs' do
      perform_enqueued_jobs(only: Families::AutoCreationJob) do
        expect { user.update!(plan: :family) }.to change(Family, :count).by(1)
      end
    end

    it 'leaves the owner sharing their location' do
      perform_enqueued_jobs(only: Families::AutoCreationJob) { user.update!(plan: :family) }

      expect(user.reload.family_sharing_enabled?).to be true
    end
  end

  describe 'when no family is due' do
    it 'ignores a plan change that is not to family' do
      user.update!(plan: :family)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      expect { user.update!(plan: :lite) }.not_to have_enqueued_job(Families::AutoCreationJob)
    end

    it 'ignores an update that leaves the plan alone' do
      user.update!(plan: :family)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      expect { user.update!(status: :active) }.not_to have_enqueued_job(Families::AutoCreationJob)
    end

    it 'ignores a user who is already in a family' do
      family = create(:family)
      create(:family_membership, user: user, family: family)

      expect { user.update!(plan: :family) }.not_to have_enqueued_job(Families::AutoCreationJob)
    end

    it 'ignores self-hosted instances' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

      expect { user.update!(plan: :family) }.not_to have_enqueued_job(Families::AutoCreationJob)
    end
  end

  describe 'arriving through the subscription callback', type: :request do
    let(:jwt_secret) { 'test_secret' }
    let(:webhook_secret) { 'test_webhook_secret' }

    before do
      Rails.cache.clear
      stub_const('ENV', ENV.to_h.merge(
                          'JWT_SECRET_KEY' => jwt_secret,
                          'SUBSCRIPTION_WEBHOOK_SECRET' => webhook_secret
                        ))
    end

    def post_family_callback
      token = JWT.encode(
        {
          user_id: user.id,
          status: 'trial',
          plan: 'family',
          active_until: 7.days.from_now.iso8601,
          subscription_source: 'paddle',
          event_id: "paddle:#{SecureRandom.uuid}",
          exp: 30.minutes.from_now.to_i
        },
        jwt_secret,
        'HS256'
      )

      post '/api/v1/subscriptions/callback',
           params: { token: token },
           headers: { 'X-Webhook-Secret' => webhook_secret }
    end

    it 'creates the family for a user upgraded to the family plan' do
      perform_enqueued_jobs(only: Families::AutoCreationJob) do
        expect { post_family_callback }.to change { user.reload.in_family? }.from(false).to(true)
      end

      expect(response).to have_http_status(:ok)
    end

    it 'leaves the new owner sharing their location' do
      perform_enqueued_jobs(only: Families::AutoCreationJob) { post_family_callback }

      expect(user.reload.family_sharing_enabled?).to be true
    end
  end
end
