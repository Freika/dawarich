# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::LoadRegions do
  describe '#call' do
    context 'without seeded countries' do
      it 'raises a message pointing at the seeds' do
        expect { described_class.new.call }
          .to raise_error(Achievements::LoadRegions::MissingCountriesError, %r{db/seeds\.rb})
      end
    end

    context 'with seeded countries' do
      before do
        create(:country)
        described_class.new.call
      end

      it 'seeds exactly the subdivisions the registry references' do
        expected = Achievements::Registry.subdivision_sets.flat_map(&:region_codes).uniq.sort

        expect(Region.pluck(:code).sort).to eq(expected)
      end

      it 'stores no country-level codes' do
        expect(Region.where.not('code LIKE ?', '%-%')).to be_empty
      end

      it 'stores valid geometries' do
        expect(Region.where('NOT ST_IsValid(geom)').count).to eq(0)
      end

      it 'is idempotent' do
        expect { described_class.new.call }.not_to change(Region, :count)
      end
    end
  end
end
