# frozen_string_literal: true

module Achievements
  class RefreshCollectionsJob < ApplicationJob
    queue_as :achievements

    def perform
      dirty = CollectionState.where('revision <> published_revision OR completed_at IS NULL ' \
                                     'OR published_dataset_id IS DISTINCT FROM ? ' \
                                     'OR timezone_version IS DISTINCT FROM ?',
                                    Exploration::Geography.current&.id, LocationTimezone.version)
      dirty.includes(:user).find_each do |state|
        CollectionSchedule.call(state.user)
      end
    end
  end
end
