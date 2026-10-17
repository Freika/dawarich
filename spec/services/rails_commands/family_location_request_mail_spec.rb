# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RailsCommands family_location_request_mail' do
  let(:family) { create(:family) }
  let(:requester) { family.creator }
  let(:target) { create(:user) }

  before do
    create(:family_membership, :owner, family:, user: requester)
    create(:family_membership, family:, user: target)
    requester.update!(settings: requester.settings.merge('timezone' => 'America/New_York'))
  end

  def run(payload) = RailsCommands::Registry.handler('family_location_request_mail').call(payload)

  it 'enqueues the mail Families::CreateLocationRequest enqueues for an API request' do
    Time.use_zone('America/New_York') do
      Families::CreateLocationRequest.new(requester:, target_user: target).call
    end
    rails_job = enqueued_jobs.sole
    request = Family::LocationRequest.sole
    clear_enqueued_jobs

    run('user_id' => requester.id, 'request_id' => request.id)

    job = enqueued_jobs.sole
    expect(job.except(:at, 'job_id', 'enqueued_at', 'provider_job_id'))
      .to eq(rails_job.except(:at, 'job_id', 'enqueued_at', 'provider_job_id'))
    expect(rails_job['timezone']).to eq('America/New_York')
  end

  it 'enqueues one mail when the command runs twice' do
    request = create(:family_location_request, requester:, target_user: target, family:)

    2.times { run('user_id' => requester.id, 'request_id' => request.id) }

    expect(enqueued_jobs.size).to eq(1)
  end

  it 'enqueues the mail on the next run when the first enqueue raised' do
    request = create(:family_location_request, requester:, target_user: target, family:)
    attempts = 0
    allow(ActionMailer::MailDeliveryJob.queue_adapter).to receive(:enqueue).and_wrap_original do |enqueue, *args|
      raise RedisClient::CannotConnectError, 'queue unreachable' if (attempts += 1) == 1

      enqueue.call(*args)
    end
    payload = { 'user_id' => requester.id, 'request_id' => request.id }

    expect { run(payload) }.to raise_error(RedisClient::CannotConnectError)
    expect(enqueued_jobs).to be_empty

    run(payload)

    expect(enqueued_jobs.size).to eq(1)
  end

  it 'raises and enqueues nothing when the cache cannot be reached' do
    request = create(:family_location_request, requester:, target_user: target, family:)
    unreachable = ActiveSupport::Cache::RedisCacheStore.new(redis: -> { raise Redis::CannotConnectError, 'down' })
    allow(Rails).to receive(:cache).and_return(unreachable)

    expect { run('user_id' => requester.id, 'request_id' => request.id) }.to raise_error(/cache/)
    expect(enqueued_jobs).to be_empty
  end

  it 'enqueues nothing for a request that is gone' do
    run('user_id' => requester.id, 'request_id' => 999_999_999)

    expect(enqueued_jobs).to be_empty
  end
end
