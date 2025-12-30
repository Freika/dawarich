# frozen_string_literal: true

class Imports::Destroy
  attr_reader :user, :import

  def initialize(user, import)
    @user = user
    @import = import
  end

  def call
    points_count = @import.points_count.to_i

    ActiveRecord::Base.transaction do
      @import.points.destroy_all
      @import.destroy!
    end

    Rails.logger.info "Import #{@import.id} deleted with #{points_count} points"

    Stats::BulkCalculator.new(@user.id).call
  end
end
