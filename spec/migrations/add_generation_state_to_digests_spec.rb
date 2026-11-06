# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261027130100_add_generation_state_to_digests.rb')

RSpec.describe AddGenerationStateToDigests, :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }

  def run_down
    migration.migrate(:down)
    Users::Digest.reset_column_information
  end

  after do
    migration.migrate(:up) unless connection.column_exists?(:digests, :generation_status)
    Users::Digest.reset_column_information
  end

  it 'marks existing digests as ready' do
    digest = create(:users_digest)
    run_down

    migration.migrate(:up)
    Users::Digest.reset_column_information

    expect(Users::Digest.find(digest.id)).to be_generation_ready
  end

  it 'finishes when an earlier partial run already added the column' do
    run_down
    connection.add_column :digests, :generation_status, :integer, default: 0, null: false

    expect { migration.migrate(:up) }.not_to raise_error
    expect(connection.column_exists?(:digests, :generation_status, :integer)).to be(true)
  end
end
