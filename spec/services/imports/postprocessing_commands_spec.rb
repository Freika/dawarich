# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::PostprocessingCommands do
  let(:user) { create(:user, settings: { 'visits_suggestions_enabled' => 'true' }) }
  let(:import) { create(:import, user:, skip_background_processing: true, source: :gpx, status: :processing) }
  let(:base) { { 'import_id' => import.id, 'user_id' => user.id, 'locale' => 'de', 'time_zone' => 'Europe/Berlin' } }

  it 'schedules captured local months and debounced achievement checks' do
    expect(Stats::CalculatingJob).to receive(:perform_later).with(user.id, 2026, 1) do
      expect(Time.zone.name).to eq('Europe/Berlin')
      expect(I18n.locale).to eq(:de)
    end
    expect(Achievements::CheckJob).to receive(:schedule).with(user.id, oldest_timestamp: 1_767_222_000)
    described_class.call(base.merge('step' => 'schedule_stats', 'months' => [[2026, 1]],
                                    'oldest_timestamp' => 1_767_222_000))
  end

  it 'uses the canonical owner-aware command producer for the current import' do
    expect(JobCommands).to receive(:produce).with('imports.update_points_count', { 'import_id' => import.id },
                                                  aggregate_id: import.id, producer: 'Phoenix Imports Postprocessing',
                                                dedupe_key: "points-count:#{import.id}")
    described_class.call(base.merge('step' => 'command', 'command_type' => 'imports.update_points_count',
                                    'command_payload' => { 'import_id' => import.id }, 'aggregate_id' => import.id))
  end

  it 'persists the registered outbox payload when its owner is Oban' do
    job_owner!('command:imports.update_points_count', :oban)
    described_class.call(base.merge('step' => 'command', 'command_type' => 'imports.update_points_count',
                                    'command_payload' => { 'import_id' => import.id }, 'aggregate_id' => import.id))
    command = JobOutbox.find_by!(command_type: 'imports.update_points_count', aggregate_id: import.id)
    expect(command.payload).to eq('import_id' => import.id)
    expect(command.state).to eq('pending')
    expect(command.command_version).to eq(1)
  end

  it 'enqueues the existing Sidekiq counter job when its owner remains Rails' do
    expect do
      described_class.call(base.merge('step' => 'command', 'command_type' => 'imports.update_points_count',
                                      'command_payload' => { 'import_id' => import.id }, 'aggregate_id' => import.id))
    end.to have_enqueued_job(Import::UpdatePointsCountJob).with(import.id)
  end

  it 'does not enqueue another user import or deleted import' do
    expect(JobCommands).not_to receive(:produce)
    described_class.call(base.merge('user_id' => create(:user).id, 'step' => 'command'))
    import.destroy!
    described_class.call(base.merge('step' => 'command'))
  end

  it 'rechecks visit preference and preserves the captured timestamp window' do
    expect(VisitSuggestingJob).to receive(:perform_later).with(user_id: user.id,
                                                               start_at: Time.iso8601('2026-01-01T00:20:00Z'),
                                                               end_at: Time.iso8601('2026-01-01T00:21:00Z'))
    described_class.call(base.merge('step' => 'schedule_visit_suggesting',
                                    'start_at' => '2026-01-01T00:20:00Z', 'end_at' => '2026-01-01T00:21:00Z'))
    user.update!(settings: { 'visits_suggestions_enabled' => 'false' })
    expect(VisitSuggestingJob).not_to receive(:perform_later)
    described_class.call(base.merge('step' => 'schedule_visit_suggesting',
                                    'start_at' => '2026-01-01T00:20:00Z', 'end_at' => '2026-01-01T00:21:00Z'))
  end

  it 'only enqueues extraction for the current pending extraction state' do
    allow(EnhancedImport::ExtractJob).to receive(:perform_later)
    described_class.call(base.merge('step' => 'extract'))
    expect(EnhancedImport::ExtractJob).not_to have_received(:perform_later)
    import.update_columns(status: 2, additional_data_extraction_status: 1)
    described_class.call(base.merge('step' => 'extract'))
    expect(EnhancedImport::ExtractJob).to have_received(:perform_later).with(import.id).once
  end
end
