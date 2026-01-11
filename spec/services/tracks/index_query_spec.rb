# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::IndexQuery do
  let(:user) { create(:user) }
  let(:params) { {} }
  let(:query) { described_class.new(user: user, params: params) }

  describe '#call' do
    let!(:newest_track) do
      create(:track, user: user,
             start_at: Time.zone.parse('2024-01-03 10:00'),
             end_at: Time.zone.parse('2024-01-03 12:00'))
    end

    let!(:older_track) do
      create(:track, user: user,
             start_at: Time.zone.parse('2024-01-01 10:00'),
             end_at: Time.zone.parse('2024-01-01 12:00'))
    end
    let!(:other_user_track) { create(:track) }

    it 'returns tracks for the user ordered by start_at desc' do
      result = query.call

      expect(result).to match_array([newest_track, older_track])
      expect(result.first).to eq(newest_track)
      expect(result).not_to include(other_user_track)
    end

    context 'with pagination params' do
      let(:params) { { page: 1, per_page: 1 } }

      it 'applies pagination settings' do
        result = query.call
        expect(result.count).to eq(1)
      end
    end

    context 'with overlapping date range filter' do
      let(:params) do
        {
          start_at: '2024-01-02T00:00:00Z',
          end_at: '2024-01-04T00:00:00Z'
        }
      end

      it 'returns tracks that overlap the date range' do
        result = query.call

        expect(result).to include(newest_track)
        expect(result).not_to include(older_track)
      end
    end

    context 'with invalid date params' do
      let(:params) { { start_at: 'invalid', end_at: 'also-invalid' } }

      it 'ignores the invalid filter and returns all tracks' do
        result = query.call
        expect(result.count).to eq(2)
      end
    end
  end

  describe '#pagination_headers' do
    it 'builds the pagination header hash' do
      paginated_relation = double('paginated', current_page: 2, total_pages: 5, total_count: 12)

      headers = query.pagination_headers(paginated_relation)

      expect(headers).to eq(
        'X-Current-Page' => '2',
        'X-Total-Pages' => '5',
        'X-Total-Count' => '12'
      )
    end
  end
end
