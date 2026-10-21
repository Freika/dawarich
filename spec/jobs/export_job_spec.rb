# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportJob, type: :job do
  let(:export) { create(:export) }

  it 'calls the Exports::Create service' do
    expect(Exports::Create).to receive(:new).with(export:).and_call_original

    described_class.perform_now(export.id)
  end

  it 'raises when export is not found' do
    expect { described_class.perform_now(-1) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'retains the processing claim when the service raises before publishing' do
    service = instance_double(Exports::Create)
    allow(Exports::Create).to receive(:new).with(export:).and_return(service)
    allow(service).to receive(:call).and_raise('synthetic export failure')

    expect { described_class.perform_now(export.id) }.to raise_error('synthetic export failure')
    expect(export.reload).to be_processing
    expect(export.processing_started_at).to be_present
    expect(export.file).not_to be_attached
    expect(Notification.where(user: export.user)).to be_empty
    expect(JobOutbox.where(command_type: 'exports.points')).to be_empty
  end

  it 'retains media wrappers as source drain debt without importing their arguments' do
    phoenix_tables!
    queue = "media-source-#{SecureRandom.hex(8)}"
    forms = [[ExportJob, [export.id]], [Posters::CreateJob, [123]], [RouteVideos::PurgeJob, []]]
    wrappers = JobDrain::WRAPPERS
    messages = wrappers.product(forms).map do |wrapper, (job_class, arguments)|
      JSON.generate('class' => wrapper, 'wrapped' => job_class.name, 'queue' => queue,
                    'jid' => SecureRandom.hex(12), 'args' => [job_class.new(*arguments).serialize])
    end
    before = JobDrain.status
    outbox_before = JobOutbox.count

    begin
      Sidekiq.redis do |redis|
        redis.sadd('queues', queue)
        messages.each { |message| redis.lpush("queue:#{queue}", message) }
      end
      status = JobDrain.status
      expect(status[:status]).to eq('BLOCKED')
      expect(status[:reasons]).to include('queued_work')
      expect(status[:counts][:queued]).to eq(before[:counts][:queued] + messages.length)
      forms.each { |form| expect(status[:classes][form.first.name]).to eq(wrappers.length) }
      expect(JSON.generate(status)).not_to include('arguments', 'job_id')
      expect(JobOutbox.count).to eq(outbox_before)
      expect(Sidekiq.redis { |redis| redis.lrange("queue:#{queue}", 0, -1) }.sort).to eq(messages.sort)
    ensure
      Sidekiq.redis do |redis|
        redis.del("queue:#{queue}")
        redis.srem('queues', queue)
      end
    end
  end

  it 'claims created → processing then runs Exports::Create' do
    described_class.perform_now(export.id)

    expect(export.reload).to be_completed
    expect(export.file).to be_attached
    expect(ActiveStorage::Blob.count).to eq(1)
    expect(Notification.where(user: export.user).count).to eq(1)
  end

  it 'a processing or completed export is not run again' do
    %i[processing completed].each do |status|
      stale = create(:export, status:)

      expect { described_class.perform_now(stale.id) }.not_to change(Notification, :count)
      expect(stale.reload.status).to eq(status.to_s)
      expect(stale.file).not_to be_attached
    end
  end

  describe 'after Oban took command:exports.points over' do
    before do
      export
      JobOutbox.delete_all
      job_owner!('command:exports.points', :oban)
    end

    it 'owned by oban: forwards with event_id = job_id and does not run' do
      job = described_class.new(export.id)

      job.perform_now

      expect(JobOutbox.sole).to have_attributes(event_id: job.job_id, command_type: 'exports.points',
                                                aggregate_id: export.id, dedupe_key: "points-export:#{export.id}",
                                                command_version: 2,
                                                payload: { 'export_id' => export.id, 'user_id' => export.user_id,
                                                           'time_zone' => Time.zone.name })
      expect(export.reload).to be_created
    end

    it 'a retried forward leaves one outbox row' do
      job = described_class.new(export.id)

      2.times { job.perform_now }

      expect(JobOutbox.count).to eq(1)
    end
  end
end
