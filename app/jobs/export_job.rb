# frozen_string_literal: true

class ExportJob < ApplicationJob
  queue_as :exports
  sidekiq_options retry: 2

  OWNERSHIP_KEY = 'command:exports.points'

  def perform(export_id)
    export = Export.find(export_id)
    claimed = JobOwnership.with_owner(OWNERSHIP_KEY) { claim(export) }
    return forward(export) if claimed == :not_owner
    return unless claimed

    Exports::Create.new(export: export.reload).call
  end

  private

  def claim(export)
    Export.where(id: export.id, status: :created)
          .update_all(status: :processing, processing_started_at: Time.current, updated_at: Time.current) == 1
  end

  def forward(export)
    JobCommands.forward('exports.points', { 'export_id' => export.id, 'user_id' => export.user_id },
                        event_id: job_id, aggregate_id: export.id, producer: self.class.name,
                        dedupe_key: "points-export:#{export.id}")
  end
end
