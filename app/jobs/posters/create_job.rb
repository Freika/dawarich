# frozen_string_literal: true

class Posters::CreateJob < ApplicationJob
  queue_as :posters
  sidekiq_options retry: 1

  def perform(poster_id)
    poster = Poster.find(poster_id)

    I18n.with_locale(poster.user.locale) do
      Posters::Generate.new(poster).call
    end
  end
end
