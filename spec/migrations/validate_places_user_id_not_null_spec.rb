# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260815100001_validate_places_user_id_not_null')

# The self-hoster upgrade path: an instance that never drained the async
# backfill from 20260508093702 must still migrate cleanly rather than aborting
# db:migrate and crash-looping the container.
RSpec.describe ValidatePlacesUserIdNotNull do
  let(:user) { create(:user) }
  let(:connection) { ActiveRecord::Base.connection }

  around do |example|
    connection.execute('ALTER TABLE places ALTER COLUMN user_id DROP NOT NULL')
    example.run
  end

  # A NOT VALID check still rejects new NULLs, so ownerless fixtures must be
  # created before 20260815100000's constraint is armed.
  def arm_check_constraint
    connection.execute(
      'ALTER TABLE places ADD CONSTRAINT places_user_id_not_null CHECK (user_id IS NOT NULL) NOT VALID'
    )
  end

  def orphan_place
    place = create(:place, user: user)
    place.update_columns(user_id: nil)
    place
  end

  it 'backfills a stranded ownerless place instead of aborting the migration' do
    place = orphan_place
    create(:place_visit, place: place, visit: create(:visit, user: user))
    arm_check_constraint

    expect { described_class.new.up }.not_to raise_error

    expect(place.reload.user_id).to eq(user.id)
  end

  it 'leaves user_id NOT NULL after a successful run' do
    arm_check_constraint

    described_class.new.up

    expect(connection.columns(:places).find { |c| c.name == 'user_id' }.null).to be(false)
  end

  it 'is idempotent when the column is already NOT NULL' do
    arm_check_constraint
    described_class.new.up

    expect { described_class.new.up }.not_to raise_error
  end

  it 'drops a temporary constraint left behind by a run that died after SET NOT NULL' do
    arm_check_constraint
    connection.execute('ALTER TABLE places ALTER COLUMN user_id SET NOT NULL')

    described_class.new.up

    leftover = connection.select_value(
      "SELECT 1 FROM pg_constraint WHERE conrelid = 'places'::regclass " \
      "AND contype = 'c' AND conname = 'places_user_id_not_null'"
    )
    expect(leftover).to be_nil
  end

  it 'raises with an actionable message when a place cannot be attributed' do
    orphan_place
    arm_check_constraint
    allow(DataMigrations::BackfillPlacesUserIdJob).to receive(:perform_now)

    expect { described_class.new.up }
      .to raise_error(ActiveRecord::MigrationError, /remaining=1/)
  end
end
