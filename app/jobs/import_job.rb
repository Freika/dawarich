# frozen_string_literal: true

class ImportJob < ApplicationJob
  queue_as :imports

  def perform(user_id, import_id)
    
    user = User.find(user_id)
    import = user.imports.find(import_id)

    import.process!
 
  end
end
