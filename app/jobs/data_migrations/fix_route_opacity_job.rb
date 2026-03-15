# frozen_string_literal: true

class DataMigrations::FixRouteOpacityJob < ApplicationJob
  queue_as :data_migrations

  def perform
    Rails.logger.info('Starting route opacity fix job')

    count = User.where("(settings->>'route_opacity')::float > 1").count
    Rails.logger.info("Found #{count} users with route_opacity > 1")

    return if count.zero?

    User.where("(settings->>'route_opacity')::float > 1").update_all(
      Arel.sql(
        "settings = jsonb_set(settings, '{route_opacity}', to_jsonb((settings->>'route_opacity')::float / 100.0))"
      )
    )

    Rails.logger.info("Completed route opacity fix job. Updated #{count} users")
  end
end
