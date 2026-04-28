# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::RequestAccountDestroy do
  let(:user) { create(:user) }

  before { Rails.cache.clear }

  def call_service
    described_class.new(user, host: 'example.com', protocol: 'https').call
  end

  it 'enqueues the confirmation email and returns :sent' do
    expect { @result = call_service }
      .to have_enqueued_job(Users::MailerSendingJob).with(
        user.id, 'account_destroy_confirmation', hash_including(:link_url)
      )

    expect(@result.status).to eq(:sent)
  end

  it 'embeds a verifiable destroy token in the link_url' do
    call_service
    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.find do |j|
      j[:job] == Users::MailerSendingJob && j[:args][1] == 'account_destroy_confirmation'
    end
    link_url = enqueued[:args].last['link_url']
    token = URI.decode_www_form(URI.parse(link_url).query).to_h['token']

    decoded = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY'), false).first
    expect(decoded['user_id']).to eq(user.id)
    expect(decoded['purpose']).to eq('account_destroy')
  end

  it 'returns :throttled on the second call within the rate-limit window' do
    first = call_service
    second = call_service

    expect(first.status).to eq(:sent)
    expect(second.status).to eq(:throttled)
  end

  it 'enqueues exactly one email even if called repeatedly' do
    expect do
      3.times { call_service }
    end.to have_enqueued_job(Users::MailerSendingJob).once
  end

  it 'allows another request once the rate-limit slot is cleared' do
    call_service
    Rails.cache.delete("#{described_class::RATE_LIMIT_KEY_PREFIX}#{user.id}")

    expect(call_service.status).to eq(:sent)
  end

  it 'rate-limits per user (does not block other users)' do
    other = create(:user)

    expect(call_service.status).to eq(:sent)
    expect(described_class.new(other, host: 'example.com', protocol: 'https').call.status).to eq(:sent)
  end
end
