# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::BulkUpdater do
  let(:user) { create(:user) }

  describe '.call' do
    it 'updates the given columns for each row by id' do
      point = create(:point, user:, raw_data: { 'a' => 1 }, raw_data_archived: true)

      Points::BulkUpdater.call(
        [{ id: point.id, raw_data: { 'b' => 2 }, raw_data_archived: false }],
        %i[raw_data raw_data_archived]
      )

      point.reload
      expect(point.raw_data).to eq({ 'b' => 2 })
      expect(point.raw_data_archived).to be(false)
    end

    it 'does not touch columns outside the given list' do
      point = create(:point, user:, lonlat: 'POINT(13.4 52.5)', city: 'Berlin')

      Points::BulkUpdater.call([{ id: point.id, city: 'Munich' }], %i[city])

      point.reload
      expect(point.city).to eq('Munich')
      expect(point.lon).to be_within(0.0001).of(13.4)
    end

    it 'does not insert a row for an id that does not exist' do
      expect do
        Points::BulkUpdater.call([{ id: 999_999_999, city: 'Nowhere' }], %i[city])
      end.not_to change(Point, :count)
    end

    it 'returns 0 for an empty batch' do
      expect(Points::BulkUpdater.call([], %i[city])).to eq(0)
    end

    it 'writes NULL when a value is nil' do
      point = create(:point, user:, city: 'Berlin')

      Points::BulkUpdater.call([{ id: point.id, city: nil }], %i[city])

      expect(point.reload.city).to be_nil
    end
  end
end
