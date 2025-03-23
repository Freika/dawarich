# frozen_string_literal: true

class Import::ProcessJob < ApplicationJob
  queue_as :imports

  def perform(import_id)
    import = Import.find(import_id)

    import.process!
  end
end
