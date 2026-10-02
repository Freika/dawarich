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

  it 'enqueues nothing for a request that is gone' do
    run('user_id' => requester.id, 'request_id' => 999_999_999)

    expect(enqueued_jobs).to be_empty
  end
end
