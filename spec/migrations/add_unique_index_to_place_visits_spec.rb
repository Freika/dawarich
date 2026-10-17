# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260310000003_add_unique_index_to_place_visits')

RSpec.describe AddUniqueIndexToPlaceVisits do
  let(:migration) { described_class.new }
  let(:connection) { ActiveRecord::Base.connection }

  context 'when place_visits does not exist' do
    around do |example|
      connection.execute('DROP TABLE place_visits CASCADE')
      example.run
    end

    it 'does not raise on up' do
      expect { migration.up }.not_to raise_error
    end

    it 'does not raise on down' do
      expect { migration.down }.not_to raise_error
    end
  end

  context 'when place_visits exists' do
    before do
      connection.execute('DROP INDEX IF EXISTS idx_place_visits_visit_id_place_id')
      allow(migration).to receive(:add_index)
      allow(migration).to receive(:remove_index)
    end

    it 'removes duplicate (visit_id, place_id) rows, keeping the oldest' do
      visit = create(:visit)
      place = create(:place)
      keeper = create(:place_visit, visit: visit, place: place)
      create(:place_visit, visit: visit, place: place)

      migration.up

      expect(PlaceVisit.where(visit_id: visit.id, place_id: place.id).pluck(:id)).to eq([keeper.id])
    end
  end
end
