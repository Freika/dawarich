# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatsQuery do
  before { Rails.cache.clear }

  describe '#points_stats' do
    subject(:points_stats) { described_class.new(user).points_stats }

    let(:user) { create(:user) }
    let!(:import) { create(:import, user: user) }

    # Written past the factory and the model callbacks: the factory fills city
    # and Point recomputes country_id spatially on save, so a point built the
    # obvious way does not hold the values these examples are asserting on.
    def point_with(geocoded:, city: nil, country_id: nil)
      create(:point, user: user, import: import).tap do |point|
        point.update_columns(
          reverse_geocoded_at: geocoded ? Time.current : nil,
          city: city,
          country_id: country_id
        )
      end
    end

    context 'when the user has no points' do
      it 'reports zeroes rather than dividing by zero' do
        expect(points_stats).to eq(total: 0, geocoded: 0, geocoded_percentage: 0.0, without_data: 0)
      end
    end

    context 'when the user has a mix of points' do
      before do
        point_with(geocoded: true, city: 'Berlin')
        point_with(geocoded: true)
        point_with(geocoded: false)
      end

      it 'counts geocoded points and the share of them that came back empty' do
        expect(points_stats).to eq(total: 3, geocoded: 2, geocoded_percentage: 66.7, without_data: 1)
      end

      it "ignores other users' points" do
        other = create(:user)
        create(:point, user: other).update_columns(reverse_geocoded_at: Time.current, city: 'Paris')

        expect(points_stats).to include(total: 3, geocoded: 2)
      end
    end

    context 'when every geocoded point carries data' do
      before { 2.times { point_with(geocoded: true, city: 'Berlin') } }

      it 'reports nothing without data' do
        expect(points_stats).to include(geocoded: 2, without_data: 0, geocoded_percentage: 100.0)
      end
    end

    context 'when a point is geocoded and only the country resolved' do
      before { point_with(geocoded: true, country_id: create(:country).id) }

      it 'does not count it as missing data' do
        expect(points_stats).to include(without_data: 0)
      end
    end

    context 'when no point is geocoded' do
      before { 2.times { point_with(geocoded: false) } }

      it 'reports zero percent' do
        expect(points_stats).to include(geocoded: 0, geocoded_percentage: 0.0, without_data: 0)
      end
    end

    context 'when the counter cache lags behind the geocoded count' do
      before do
        2.times { point_with(geocoded: true, city: 'Berlin') }
        user.update_column(:points_count, 1)
      end

      it 'clamps the percentage at 100 instead of reporting more than everything' do
        expect(points_stats[:geocoded_percentage]).to eq(100.0)
      end
    end

    # The panel is wrapped in DawarichSettings.store_geodata?, so on instances
    # that do not store it the count was scanned and then thrown away.
    context 'when the instance does not store geodata' do
      before do
        allow(DawarichSettings).to receive(:store_geodata?).and_return(false)
        point_with(geocoded: true)
      end

      it 'omits the empty-result count entirely' do
        expect(points_stats[:without_data]).to be_nil
      end

      it 'runs one count instead of two' do
        expect(Point.connection).to receive(:select_value).once.and_call_original

        points_stats
      end
    end

    context 'caching' do
      before { point_with(geocoded: true, city: 'Berlin') }

      it 'does not touch the database on a second call' do
        described_class.new(user).points_stats

        expect(Point.connection).not_to receive(:select_value)
        described_class.new(user).points_stats
      end

      it 'takes the total from the counter cache rather than a query' do
        user.update_column(:points_count, 42)

        expect(points_stats[:total]).to eq(42)
      end
    end
  end
end
