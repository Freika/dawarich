# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260622090000_backfill_notes_columns')

RSpec.describe BackfillNotesColumns do
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
end
