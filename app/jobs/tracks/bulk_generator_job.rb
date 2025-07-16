# frozen_string_literal: true

# Background job for bulk track generation.
#
# This job regenerates all tracks for a user from scratch, typically used for:
# - Initial track generation after data import
# - Full recalculation when settings change
# - Manual track regeneration requested by user
#
# The job uses the new simplified Tracks::Generator service with bulk mode,
# which cleans existing tracks and regenerates everything from points.
#
# Parameters:
# - user_id: The user whose tracks should be generated
# - start_at: Optional start timestamp to limit processing
# - end_at: Optional end timestamp to limit processing
#
class Tracks::BulkGeneratorJob < ApplicationJob
  queue_as :default

  def perform(user_id, start_at: nil, end_at: nil)
    user = User.find(user_id)
    
    Rails.logger.info "Starting bulk track generation for user #{user_id}, " \
                     "start_at: #{start_at}, end_at: #{end_at}"
    
    generator = Tracks::Generator.new(
      user,
      start_at: start_at,
      end_at: end_at,
      mode: :bulk
    )
    
    generator.call
    
    Rails.logger.info "Completed bulk track generation for user #{user_id}"
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Record not found in bulk track generation: #{e.message}"
    # Don't retry if records are missing
  rescue StandardError => e
    Rails.logger.error "Error in bulk track generation for user #{user_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise # Re-raise for job retry logic
  end
end