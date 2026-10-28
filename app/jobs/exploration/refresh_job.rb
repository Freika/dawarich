# frozen_string_literal: true

class Exploration::RefreshJob < ApplicationJob
  queue_as :low_priority

  def perform
    Exploration::State.activated.where('revision <> published_revision OR snapshot_id IS NULL').find_each do |state|
      user = User.find_by(id: state.user_id)
      Exploration::Schedule.call(user) if user
    end
    dataset = Exploration::Geography.current
    return unless dataset

    Exploration::Snapshot.where('dataset_id <> ? OR world_opened_area IS NULL', dataset.id)
                         .where(id: Exploration::State.activated.select(:snapshot_id))
                         .find_each { |s| Exploration::Schedule.call(User.find(s.user_id)) }
  end
end
