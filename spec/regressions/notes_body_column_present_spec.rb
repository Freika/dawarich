# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260622090000_backfill_notes_columns')

RSpec.describe BackfillNotesColumns, :non_transactional do
  def column?(name)
    ActiveRecord::Base.connection.column_exists?(:notes, name)
  end

  around do |example|
    example.run
  ensure
    ActiveRecord::Base.connection.add_column(:notes, :body, :text) unless column?(:body)
    Note.reset_column_information
  end

  it 'restores the body column when a pre-existing notes table lacks it' do
    ActiveRecord::Base.connection.remove_column(:notes, :body) if column?(:body)
    Note.reset_column_information

    expect(column?(:body)).to be(false)
    expect { Note.new.body = 'x' }.to raise_error(NoMethodError)

    described_class.new.up
    Note.reset_column_information

    expect(column?(:body)).to be(true)
    expect { Note.new.body = 'x' }.not_to raise_error
  end

  it 'is a safe no-op when every column already exists' do
    expect(column?(:body)).to be(true)
    expect { described_class.new.up }.not_to raise_error
    expect(column?(:body)).to be(true)
  end

  it 'raises a clear error when duplicate attachable dates would violate the unique index' do
    connection = ActiveRecord::Base.connection
    user = create(:user)
    noted_at = Time.current

    connection.execute("DROP INDEX IF EXISTS #{described_class::UNIQUE_INDEX_NAME}")
    Note.insert_all(
      Array.new(2) do
        { user_id: user.id, body: 'dup', noted_at: noted_at, attachable_type: 'Trip',
          attachable_id: 999_999, created_at: Time.current, updated_at: Time.current }
      end
    )

    expect { described_class.new.up }.to raise_error(/duplicate/i)
  ensure
    Note.where(attachable_id: 999_999).delete_all
    unless connection.index_name_exists?(:notes, described_class::UNIQUE_INDEX_NAME)
      connection.execute(<<~SQL.squish)
        CREATE UNIQUE INDEX IF NOT EXISTS #{described_class::UNIQUE_INDEX_NAME}
        ON notes (attachable_type, attachable_id, (CAST(noted_at AS date)))
        WHERE attachable_id IS NOT NULL
      SQL
    end
  end
end
