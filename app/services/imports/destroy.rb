# frozen_string_literal: true

class Imports::Destroy
  attr_reader :user, :import

  def initialize(user, import)
    @user = user
    @import = import
  end

  def call
    points_count = @import.points_count

    ActiveRecord::Base.transaction do
      # Use destroy_all instead of delete_all to trigger counter_cache callbacks
      # This ensures users.points_count is properly decremented
      @import.points.destroy_all
      @import.destroy!
    end

    Rails.logger.info "Import #{@import.id} deleted with #{points_count} points"

    Stats::BulkCalculator.new(@user.id).call
  end
end
