# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260730210200_add_unique_index_to_visits')

RSpec.describe AddUniqueIndexToVisits do
  let(:migration) { described_class.new }
  let(:connection) { ActiveRecord::Base.connection }
  let(:user) { create(:user) }
  let(:place) { create(:place, user: user) }
  let(:started_at) { Time.zone.now }

  before do
    connection.execute('DROP INDEX IF EXISTS idx_visits_user_started_at_place_unique')

    build_index_calls = 0
    allow(migration).to receive(:build_index) do
      build_index_calls += 1
      raise ActiveRecord::RecordNotUnique, 'duplicate key value violates unique constraint' if build_index_calls == 1
    end
  end

  def create_duplicate_visits
    keeper = create(:visit, user: user, place: place, started_at: started_at)
    loser = create(:visit, user: user, place: place, started_at: started_at)
    [keeper, loser]
  end

  context 'when place_visits does not exist' do
    around do |example|
      connection.execute('DROP TABLE place_visits CASCADE')
      example.run
    end

    it 'still collapses stragglers on the rescue path without raising' do
      keeper, loser = create_duplicate_visits

      expect { migration.up }.not_to raise_error

      expect(Visit.where(id: [keeper.id, loser.id]).pluck(:id)).to eq([keeper.id])
    end
  end

  context 'when place_visits exists' do
    it 'collapses stragglers and still removes place_visits rows for the loser' do
      keeper, loser = create_duplicate_visits
      loser_place_visit = create(:place_visit, visit: loser, place: place)

      migration.up

      expect(Visit.where(id: [keeper.id, loser.id]).pluck(:id)).to eq([keeper.id])
      expect(PlaceVisit.where(id: loser_place_visit.id)).not_to exist
    end
  end
end
