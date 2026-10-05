# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import::ImmichGeodataJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }

    it 'calls Immich::ImportGeodata' do
      expect_any_instance_of(Immich::ImportGeodata).to receive(:call)

      described_class.perform_now(user.id)
    end

    it 'forwards once to the owner and keeps a failed rehome command durable' do
      job_owner!('command:imports.immich_geodata', :oban)
      job = described_class.new(user.id)
      allow_any_instance_of(Immich::ImportGeodata).to receive(:call) do
        raise 'provider executed without admitted owner'
      end
      2.times { job.perform_now }
      expect(JobOutbox.pending.pluck(:event_id, :command_type, :payload))
        .to eq([[job.job_id, 'imports.immich_geodata', { 'user_id' => user.id, 'time_zone' => Time.zone.name }]])
      allow(described_class.queue_adapter).to receive(:enqueue_at).and_raise(RedisClient::CannotConnectError)
      expect(JobCommands.rehome!('imports.immich_geodata', by: 'spec'))
        .to eq({ moved: 0, left: 1, error: 'RedisClient::CannotConnectError' })
      expect(JobOutbox.pending.count).to eq(1)
      allow(described_class.queue_adapter).to receive(:enqueue_at).and_call_original
      expect(JobCommands.rehome!('imports.immich_geodata', by: 'spec')).to eq({ moved: 1, left: 0 })
      expect(JobOutbox.pending.count).to eq(0)
      expect(enqueued_jobs.last[:args]).to eq([user.id])
    end
  end
end
