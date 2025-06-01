# frozen_string_literal: true

class Imports::Destroy
  attr_reader :user, :import

  def initialize(user, import)
    @user = user
    @import = import
  end

  def call
    ActiveRecord::Base.transaction do
      @import.points.delete_all
      @import.destroy!
    end

    Stats::BulkCalculator.new(@user.id).call
  end
end
