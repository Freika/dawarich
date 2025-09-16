# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::HexagonContextResolver do
  describe '.call' do
    subject(:resolve_context) do
      described_class.call(
        params: params,
        current_api_user: current_api_user
      )
    end

    let(:user) { create(:user) }
    let(:current_api_user) { user }

    context 'with authenticated user (no UUID)' do
      let(:params) do
        {
          start_date: '2024-06-01T00:00:00Z',
          end_date: '2024-06-30T23:59:59Z'
        }
      end

      it 'resolves authenticated context' do
        result = resolve_context

        expect(result).to match({
          target_user: current_api_user,
          start_date: '2024-06-01T00:00:00Z',
          end_date: '2024-06-30T23:59:59Z',
          stat: nil
        })
      end
    end

    context 'with public sharing UUID' do
      let(:stat) { create(:stat, :with_sharing_enabled, user:, year: 2024, month: 6) }
      let(:params) { { uuid: stat.sharing_uuid } }
      let(:current_api_user) { nil }

      it 'resolves public sharing context' do
        result = resolve_context

        expect(result[:target_user]).to eq(user)
        expect(result[:stat]).to eq(stat)
        expect(result[:start_date]).to eq('2024-06-01T00:00:00+00:00')
        expect(result[:end_date]).to eq('2024-06-30T23:59:59+00:00')
      end
    end

    context 'with invalid sharing UUID' do
      let(:params) { { uuid: 'invalid-uuid' } }
      let(:current_api_user) { nil }

      it 'raises SharedStatsNotFoundError' do
        expect { resolve_context }.to raise_error(
          Maps::HexagonContextResolver::SharedStatsNotFoundError,
          'Shared stats not found or no longer available'
        )
      end
    end

    context 'with expired sharing' do
      let(:stat) { create(:stat, :with_sharing_expired, user:, year: 2024, month: 6) }
      let(:params) { { uuid: stat.sharing_uuid } }
      let(:current_api_user) { nil }

      it 'raises SharedStatsNotFoundError' do
        expect { resolve_context }.to raise_error(
          Maps::HexagonContextResolver::SharedStatsNotFoundError,
          'Shared stats not found or no longer available'
        )
      end
    end

    context 'with disabled sharing' do
      let(:stat) { create(:stat, :with_sharing_disabled, user:, year: 2024, month: 6) }
      let(:params) { { uuid: stat.sharing_uuid } }
      let(:current_api_user) { nil }

      it 'raises SharedStatsNotFoundError' do
        expect { resolve_context }.to raise_error(
          Maps::HexagonContextResolver::SharedStatsNotFoundError,
          'Shared stats not found or no longer available'
        )
      end
    end

    context 'with stat that does not exist' do
      let(:params) { { uuid: 'non-existent-uuid' } }
      let(:current_api_user) { nil }

      it 'raises SharedStatsNotFoundError' do
        expect { resolve_context }.to raise_error(
          Maps::HexagonContextResolver::SharedStatsNotFoundError,
          'Shared stats not found or no longer available'
        )
      end
    end
  end
end