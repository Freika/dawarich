# frozen_string_literal: true

class ImportJob < ApplicationJob
  queue_as :imports

  def perform(user_id, import_id)
    puts "ImportJob started for user_id: #{user_id}, import_id: #{import_id}"
    
    user = User.find(user_id)
    import = user.imports.find(import_id)

    import.process!
    puts "ImportJob finished for user_id: #{user_id}, import_id: #{import_id}"
 
  end
end
