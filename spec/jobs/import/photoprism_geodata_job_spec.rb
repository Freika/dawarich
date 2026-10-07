# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import::PhotoprismGeodataJob, type: :job do
  let(:user) { create(:user) }

  it 'forwards once to the owner and keeps a failed rehome command durable' do
    job_owner!('command:imports.photoprism_geodata', :oban)
    job = described_class.new(user.id)
    allow_any_instance_of(Photoprism::ImportGeodata).to receive(:call) do
      raise 'provider executed without admitted owner'
    end
    2.times { job.perform_now }
    expect(JobOutbox.pending.pluck(:event_id, :command_type, :payload))
      .to eq([[job.job_id, 'imports.photoprism_geodata', { 'user_id' => user.id, 'time_zone' => Time.zone.name }]])
    expect(job.arguments).to eq([user.id])
    expect(job.serialize).to include('locale' => I18n.locale.to_s, 'timezone' => Time.zone.name)
    expect(Import.where(user:)).to be_empty
    expect(user.points).to be_empty
    allow(described_class.queue_adapter).to receive(:enqueue_at).and_raise(RedisClient::CannotConnectError)
    expect(JobCommands.rehome!('imports.photoprism_geodata', by: 'spec'))
      .to eq({ moved: 0, left: 1, error: 'RedisClient::CannotConnectError' })
    expect(JobOutbox.pending.count).to eq(1)
    allow(described_class.queue_adapter).to receive(:enqueue_at).and_call_original
    expect(JobCommands.rehome!('imports.photoprism_geodata', by: 'spec')).to eq({ moved: 1, left: 0 })
    expect(JobOutbox.pending.count).to eq(0)
    expect(enqueued_jobs.last[:args]).to eq([user.id])
    expect(Import.where(user:)).to be_empty
  end
end
