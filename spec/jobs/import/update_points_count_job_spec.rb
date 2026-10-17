# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import::UpdatePointsCountJob, type: :job do
  let(:import) { create(:import, processed: 0) }

  before { create_list(:point, 2, user: import.user, import:) }

  it 'recounts processed while Sidekiq owns the key' do
    described_class.perform_now(import.id)

    expect(import.reload.processed).to eq(2)
  end

  it 'forwards an old payload with its job id and writes nothing while Oban owns the key' do
    job_owner!(ImportCommands::UPDATE_POINTS_COUNT_KEY, :oban)
    job = described_class.new(import.id)

    job.perform_now

    expect(import.reload.processed).to eq(0)
    expect(JobOutbox.pending.sole).to have_attributes(event_id: job.job_id, command_type: 'imports.update_points_count',
                                                      payload: { 'import_id' => import.id })
  end

  it 'is a no-op for a missing import' do
    expect { described_class.perform_now(-1) }.not_to raise_error
    expect(JobOutbox.count).to eq(0)
  end

  it 'counts before taking the owner lock and updates inside it' do
    phoenix_tables!
    events = []
    record = lambda do |*, payload|
      sql = payload[:sql]
      events << :count if sql.include?('COUNT(*)') && sql.include?('"points"')
      events << :lock if sql.include?('FOR SHARE')
      events << :write if sql.start_with?('UPDATE "imports"')
    end

    ActiveSupport::Notifications.subscribed(record, 'sql.active_record') { described_class.perform_now(import.id) }

    expect(events).to eq(%i[count lock write])
  end
end
