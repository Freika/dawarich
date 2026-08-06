# frozen_string_literal: true

class Import::ProcessJob < ApplicationJob
  queue_as :imports

  def perform(import_id)
    import = Import.find(import_id)

    I18n.with_locale(import.user.locale) { import.process! }
  end
end
