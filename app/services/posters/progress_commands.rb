# frozen_string_literal: true

module Posters
  module ProgressCommands
    HANDLERS = {
      'posters.progress' => {
        guard: 'Re-renders the current owner-scoped poster; repeats cannot restore stale progress or attachments',
        call: lambda { |payload|
          poster = Poster.find_by(id: payload.fetch('poster_id'), user_id: payload.fetch('user_id'))
          next unless poster

          I18n.with_locale(payload.fetch('locale')) do
            Turbo::StreamsChannel.broadcast_replace_to(
              [poster.user, :posters], target: ActionView::RecordIdentifier.dom_id(poster),
              partial: 'posters/poster', locals: { poster: poster }
            )
          end
        }
      }
    }.freeze
  end
end
