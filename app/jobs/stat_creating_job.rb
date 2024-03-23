class StatCreatingJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    CreateStats.new(user_id).call
  end
end
