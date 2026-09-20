# frozen_string_literal: true

class ValidatePlacesUserIdNotNull < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  CONSTRAINT_NAME = 'places_user_id_not_null'

  def up
    unless user_id_not_null?
      drain_userless_places

      validate_check_constraint :places, name: CONSTRAINT_NAME if constraint_exists?
      change_column_null :places, :user_id, false
    end

    # Outside the guard: a run that died between SET NOT NULL and this drop must
    # still be able to clean up the temporary constraint on the next attempt.
    remove_check_constraint :places, name: CONSTRAINT_NAME if constraint_exists?
  end

  def down
    return unless user_id_not_null?

    change_column_null :places, :user_id, true
  end

  private

  # 20260508093702 enqueued the backfill with perform_later. An instance that
  # crosses both migrations in a single db:migrate has never run it, because
  # Sidekiq is a separate container that is not up during the web entrypoint's
  # migration step. Run it inline so validation cannot abort an unattended deploy.
  def drain_userless_places
    pending = userless_count
    return if pending.zero?

    # The backfill assigns each ownerless place to the account that visited it
    # and deletes any that no account ever visited.
    Rails.logger.info "[Migration] places_user_id_backfill pending=#{pending}"
    before = Place.count
    DataMigrations::BackfillPlacesUserIdJob.perform_now

    # Counts skew if another process inserts places while this runs; during an
    # unattended upgrade Sidekiq is not up yet, so they are exact there.
    deleted = before - Place.count
    Rails.logger.info "[Migration] places_user_id_backfill assigned=#{pending - deleted} deleted=#{deleted}"

    remaining = userless_count
    return if remaining.zero?

    raise ActiveRecord::MigrationError,
          "[Migration] places_user_id_backfill remaining=#{remaining}. " \
          'List them with: SELECT id FROM places WHERE user_id IS NULL; ' \
          'assign an owner to those places or delete them, then migrate again'
  end

  def userless_count
    connection.select_value('SELECT count(*) FROM places WHERE user_id IS NULL').to_i
  end

  def user_id_not_null?
    connection.columns(:places).find { |column| column.name == 'user_id' }&.null == false
  end

  # Scoped to this table and to CHECK constraints only: PostgreSQL 17+ also
  # catalogues column NOT NULL constraints in pg_constraint, and auto-names the
  # one for places.user_id after this very constraint.
  def constraint_exists?
    connection.select_value(
      ActiveRecord::Base.sanitize_sql(
        ["SELECT 1 FROM pg_constraint WHERE conrelid = 'places'::regclass AND contype = 'c' AND conname = ?",
         CONSTRAINT_NAME]
      )
    ).present?
  end
end
