# frozen_string_literal: true

class Import::ProcessJob < ApplicationJob
  queue_as :imports

  def perform(import_id)
    import = Import.find_by(id: import_id)
    return unless import&.user

    import.process!
  end
end
