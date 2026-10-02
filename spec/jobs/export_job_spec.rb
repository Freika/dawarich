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
