# frozen_string_literal: true

module Points
  class Revision < ApplicationRecord
    self.table_name = 'point_revisions'

    def self.for_user(user_id, start_at: nil, end_at: nil)
      scope = where(user_id: user_id)
      scope = scope.where(month: month_for(start_at)..) if start_at
      scope = scope.where(month: ..month_for(end_at)) if end_at
      Digest::SHA256.hexdigest(scope.order(:month).pluck(:month, :revision).to_json)
    end

    def self.month_for(timestamp)
      Time.at(timestamp).utc.to_date.beginning_of_month
    end
    private_class_method :month_for
  end
end
