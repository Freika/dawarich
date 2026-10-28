# frozen_string_literal: true

require 'rails_helper'
require 'stringio'

migration_files = %w[
  20260908120000_create_exploration
  20260909193000_add_exploration_world_totals
  20261028110000_enqueue_thematic_achievements_backfill
  20261028120000_create_achievement_collections
  20261028130000_add_achievement_city_catalog
  20261028140000_watch_achievement_privacy_and_cities
  20261028143000_add_download_preparation_pending_to_imports
  20261028150000_track_collection_dataset
  20261028160000_refresh_collection_privacy_fingerprint
  20261028170000_track_collection_timezone_version
  20261028200000_activate_requested_exploration
]
migration_files.each { |file| require Rails.root.join("db/migrate/#{file}.rb") }

RSpec.describe 'Release schema replay' do
  let(:connection) { ApplicationRecord.connection }
  let(:migrations) do
    [CreateExploration, AddExplorationWorldTotals, EnqueueThematicAchievementsBackfill,
     CreateAchievementCollections, AddAchievementCityCatalog, WatchAchievementPrivacyAndCities,
     AddDownloadPreparationPendingToImports, TrackCollectionDataset, RefreshCollectionPrivacyFingerprint,
     TrackCollectionTimezoneVersion, ActivateRequestedExploration].map(&:new)
  end

  def schema_dump
    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(ApplicationRecord.connection_pool, stream)
    stream.string
  end

  def activation_time(user)
    connection.select_value("SELECT activated_at FROM exploration_states WHERE user_id=#{user.id}")
  end

  it 'replays every migration without changing the installed schema' do
    before = schema_dump

    2.times { migrations.each { |migration| migration.migrate(:up) } }

    expect(schema_dump).to eq(before)
    expect(enqueued_jobs.count { |job| job[:job] == Achievements::BulkCheckJob }).to eq(1)
  end

  it 'can roll back twice and rebuild twice without losing existing points' do
    user = create(:user)
    point = create(:point, user: user)
    point_before = connection.select_one("SELECT * FROM points WHERE id=#{point.id}")
    before = schema_dump

    2.times { migrations.reverse_each { |migration| migration.migrate(:down) } }
    2.times { migrations.each { |migration| migration.migrate(:up) } }

    expect(schema_dump).to eq(before)
    expect(connection.select_one("SELECT * FROM points WHERE id=#{point.id}")).to eq(point_before)
  end

  it 'finishes installing indexes, foreign keys and triggers after partial setup' do
    connection.remove_index :exploration_territories, :dataset_id
    connection.remove_foreign_key :exploration_territories, :exploration_datasets
    connection.remove_index :exploration_datasets, :version
    connection.remove_foreign_key :exploration_cell_coverages, :exploration_cells
    connection.remove_index :achievement_collectibles, name: 'index_achievement_collectibles_on_owner_series_subject'
    connection.remove_index :achievement_collectibles, :city_selection_id
    connection.remove_foreign_key :achievement_collectibles, :achievement_city_selections
    connection.execute('DROP TRIGGER achievement_collections_insert ON points')

    migrations.each { |migration| migration.migrate(:up) }

    expect(connection.index_exists?(:exploration_territories, :dataset_id)).to be(true)
    expect(connection.foreign_key_exists?(:exploration_territories, :exploration_datasets)).to be(true)
    expect(connection.index_exists?(:exploration_datasets, :version, unique: true)).to be(true)
    expect(connection.foreign_key_exists?(:exploration_cell_coverages, :exploration_cells)).to be(true)
    expect(connection.index_exists?(:achievement_collectibles, %i[user_id series subject_key],
                                    unique: true)).to be(true)
    expect(connection.index_exists?(:achievement_collectibles, :city_selection_id)).to be(true)
    expect(connection.foreign_key_exists?(:achievement_collectibles, :achievement_city_selections)).to be(true)
    expect(connection.select_value(<<~SQL)).to eq(1)
      SELECT COUNT(*) FROM pg_trigger
      WHERE tgrelid = 'points'::regclass AND tgname = 'achievement_collections_insert'
    SQL
  end

  it 'preserves existing activation times while filling eligible missing activations' do
    active = create(:user)
    pending = create(:user)
    idle = create(:user)
    original = 3.days.ago.change(usec: 0)
    [active, pending, idle].each do |user|
      connection.execute(<<~SQL)
        INSERT INTO exploration_states(user_id,revision,published_revision,created_at,updated_at)
        VALUES(#{user.id},1,0,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP) ON CONFLICT(user_id) DO NOTHING
      SQL
    end
    connection.execute(<<~SQL)
      UPDATE exploration_states SET activated_at=#{connection.quote(original)}, requested_at=now()
      WHERE user_id=#{active.id}
    SQL
    connection.execute("UPDATE exploration_states SET requested_at=now() WHERE user_id=#{pending.id}")

    2.times { ActivateRequestedExploration.new.migrate(:up) }

    expect(activation_time(active)).to eq(original)
    expect(activation_time(pending)).to be_present
    expect(activation_time(idle)).to be_nil
  end
end
