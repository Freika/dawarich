# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SafeTimestampParser, type: :controller do
  controller(ApplicationController) do
    include SafeTimestampParser

    def index
      render plain: safe_timestamp(params[:date]).to_s
    end
  end

  before do
    routes.draw { get 'index' => 'anonymous#index' }
  end

  describe '#safe_timestamp' do
    context 'with valid dates within range' do
      it 'returns correct timestamp for 2020-01-01' do
        get :index, params: { date: '2020-01-01' }
        expected = Time.zone.parse('2020-01-01').to_i
        expect(response.body).to eq(expected.to_s)
      end

      it 'returns correct timestamp for 1980-06-15' do
        get :index, params: { date: '1980-06-15' }
        expected = Time.zone.parse('1980-06-15').to_i
        expect(response.body).to eq(expected.to_s)
      end
    end

    context 'with dates before valid range' do
      it 'clamps year 1000 to minimum timestamp (1970-01-01)' do
        get :index, params: { date: '1000-01-30' }
        min_timestamp = Time.zone.parse('1970-01-01').to_i
        expect(response.body).to eq(min_timestamp.to_s)
      end

      it 'clamps year 1900 to minimum timestamp (1970-01-01)' do
        get :index, params: { date: '1900-12-25' }
        min_timestamp = Time.zone.parse('1970-01-01').to_i
        expect(response.body).to eq(min_timestamp.to_s)
      end

      it 'clamps year 1969 to minimum timestamp (1970-01-01)' do
        get :index, params: { date: '1969-07-20' }
        min_timestamp = Time.zone.parse('1970-01-01').to_i
        expect(response.body).to eq(min_timestamp.to_s)
      end
    end

    context 'with dates after valid range' do
      it 'clamps year 2150 to maximum timestamp (2100-01-01)' do
        get :index, params: { date: '2150-01-01' }
        max_timestamp = Time.zone.parse('2100-01-01').to_i
        expect(response.body).to eq(max_timestamp.to_s)
      end

      it 'clamps year 3000 to maximum timestamp (2100-01-01)' do
        get :index, params: { date: '3000-12-31' }
        max_timestamp = Time.zone.parse('2100-01-01').to_i
        expect(response.body).to eq(max_timestamp.to_s)
      end
    end

    context 'with invalid date strings' do
      it 'returns current time for unparseable date' do
        freeze_time do
          get :index, params: { date: 'not-a-date' }
          expected = Time.zone.now.to_i
          expect(response.body).to eq(expected.to_s)
        end
      end

      it 'returns current time for empty string' do
        freeze_time do
          get :index, params: { date: '' }
          expected = Time.zone.now.to_i
          expect(response.body).to eq(expected.to_s)
        end
      end
    end

    context 'edge cases' do
      it 'handles Unix epoch exactly (1970-01-01)' do
        get :index, params: { date: '1970-01-01' }
        expected = Time.zone.parse('1970-01-01').to_i
        expect(response.body).to eq(expected.to_s)
      end

      it 'handles maximum date exactly (2100-01-01)' do
        get :index, params: { date: '2100-01-01' }
        expected = Time.zone.parse('2100-01-01').to_i
        expect(response.body).to eq(expected.to_s)
      end
    end
  end
end
