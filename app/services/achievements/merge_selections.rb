# frozen_string_literal: true

module Achievements
  class MergeSelections
    def self.call(survivor, duplicate)
      old = Selection.find_by(place_id: duplicate.id, user_id: survivor.user_id)
      return unless old

      selected = Selection.find_or_create_by!(place_id: survivor.id, user_id: survivor.user_id)
      Collectible.where(selection_id: old.id).find_each do |card|
        existing = Collectible.find_by(user_id: survivor.user_id, series: card.series,
                                       subject_key: "place:#{survivor.id}")
        if existing
          card.events.order(:id).each do |event|
            next if event.kind == 'earned' && existing.events.exists?(kind: 'earned', level: event.level)

            event.update!(collectible: existing)
          end
          card.destroy!
        else
          card.update!(selection: selected, subject_key: "place:#{survivor.id}")
        end
      end
      old.destroy!
    end
  end
end
