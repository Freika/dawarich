# frozen_string_literal: true

module Imports
  module BusyRetry
    ATTEMPTS = 10
    MESSAGE = 'Another attempt kept this import busy, so it was stopped. Please try again.'

    module_function

    def fail!(import_id, from:, user_id: nil)
      scope = Import.where(id: import_id, status: from)
      scope = scope.where(user_id:) if user_id
      scope.update_all(status: :failed, error_message: MESSAGE, updated_at: Time.current)
    end
  end
end
