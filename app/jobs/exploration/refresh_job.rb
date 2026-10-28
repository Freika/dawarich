# frozen_string_literal: true

class Exploration::RefreshJob < ApplicationJob
  queue_as :low_priority

  def perform
    # Lazily backfill users who open exploration. Durable dirty state is created
    # by source writes, and survives a queue outage or an interrupted worker.
    Exploration::State.where('revision <> published_revision OR snapshot_id IS NULL').find_each do |state|
      user = User.find_by(id: state.user_id)
      Exploration::Schedule.call(user) if user
    end
    dataset = Exploration::Geography.current
    return unless dataset

    Exploration::Snapshot.where('dataset_id <> ? OR world_opened_area IS NULL', dataset.id)
                         .where(id: Exploration::State.select(:snapshot_id))
                         .find_each { |s| Exploration::Schedule.call(User.find(s.user_id)) }
  end
end
