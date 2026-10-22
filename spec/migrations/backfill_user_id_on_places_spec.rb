# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260508093702_backfill_user_id_on_places')

# The migration is a thin wrapper: its assignment logic lives in
# DataMigrations::BackfillPlacesUserIdJob (covered in that job's own spec).
# What is covered here is the branch it chooses.
RSpec.describe BackfillUserIdOnPlaces do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  around do |example|
    ActiveRecord::Base.connection.execute('ALTER TABLE places ALTER COLUMN user_id DROP NOT NULL')
    example.run
  end

  it 'enqueues the backfill job when at least one place has a NULL user_id' do
    create(:place, user: user).update_columns(user_id: nil)

    expect { described_class.new.up }
      .to have_enqueued_job(DataMigrations::BackfillPlacesUserIdJob)
  end

  it 'skips enqueueing when every place already has an owner' do
    create(:place, user: user)

    expect { described_class.new.up }
      .not_to have_enqueued_job(DataMigrations::BackfillPlacesUserIdJob)
  end

  it 'refuses to roll back, because orphan places were deleted' do
    expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
