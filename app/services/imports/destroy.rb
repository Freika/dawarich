# frozen_string_literal: true

class Imports::Destroy
  BATCH_SIZE = 5000

  attr_reader :user, :import

  def initialize(user, import)
    @user = user
    @import = import
  end

  def call
    points_count = @import.points_count.to_i

    delete_points_in_batches

    @import.destroy!

    Rails.logger.info "Import #{@import.id} deleted with #{points_count} points"

    Stats::BulkCalculator.new(@user.id).call
  end

  private

  def delete_points_in_batches
    loop do
      ids = @import.points.limit(BATCH_SIZE).pluck(:id)
      break if ids.empty?

      Point.where(id: ids).delete_all
    end
  end
end
