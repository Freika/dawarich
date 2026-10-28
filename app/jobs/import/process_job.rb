# frozen_string_literal: true

class Import::ProcessJob < ApplicationJob
  queue_as :imports

  def perform(import_id)
    user_id = Import.where(id: import_id).pick(:user_id)
    return unless user_id

    Users::DataLock.with_shared(user_id) do
      import = Import.find_by(id: import_id, user_id: user_id)
      return unless import&.user

      I18n.with_locale(import.user.locale) { import.process! }
    end
  end
end
