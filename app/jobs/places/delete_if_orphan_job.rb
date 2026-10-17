# frozen_string_literal: true

module Places
  class DeleteIfOrphanJob < ApplicationJob
    queue_as :places

    def perform(place_id)
      Places::JobCommands.execute('places.delete_if_orphan', place_id, job_id: job_id) do
        Places::DeleteIfOrphan.call(place_id)
      end
    end
  end
end
