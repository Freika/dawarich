# frozen_string_literal: true

class Posters::CreateJob < ApplicationJob
  queue_as :posters
  sidekiq_options retry: 1

  class Busy < StandardError; end

  def perform(poster_id)
    poster = Poster.find(poster_id)
    return forward(poster) if JobOwnership.oban?('command:posters.create')

    result = PhoenixLease.hold("posters:#{poster.id}", Busy.new('poster generation is already running')) do
      JobOwnership.with_owner('command:posters.create') do
        I18n.with_locale(poster.user.locale) do
          Posters::Generate.new(poster).call
        end
      end
    end
    forward(poster) if result == :not_owner
  end

  private

  def forward(poster)
    JobCommands.forward('posters.create',
                        { 'poster_id' => poster.id, 'user_id' => poster.user_id, 'locale' => poster.user.locale },
                        event_id: job_id, aggregate_id: poster.id, producer: self.class.name,
                        dedupe_key: "poster-create:#{poster.id}")
  end
end
