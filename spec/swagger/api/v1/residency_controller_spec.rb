# frozen_string_literal: true

require 'swagger_helper'

describe 'Residency API', type: :request do
  path '/api/v1/residency' do
    get 'Returns per-country day counts for tax residency calculations' do
      tags 'Residency'
      description 'Computes per-country day counts and consecutive-day periods for the requested year. ' \
                  'Pro-only on Cloud; available to all self-hosted users.'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :year, in: :query, type: :integer, required: false,
                description: 'Year to compute residency for. Defaults to the latest year that has data for the user.'

      response '200', 'residency computed' do
        schema type: :object,
               properties: {
                 year: { type: :integer },
                 counting_mode: { type: :string, description: 'e.g. any_presence' },
                 total_tracked_days: { type: :integer },
                 available_years: { type: :array, items: { type: :integer } },
                 countries: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       country_name: { type: :string },
                       country_code: { type: :string, nullable: true },
                       days: { type: :integer },
                       periods: {
                         type: :array,
                         items: {
                           type: :object,
                           properties: {
                             start_date: { type: :string, format: :date },
                             end_date: { type: :string, format: :date },
                             consecutive_days: { type: :integer }
                           }
                         }
                       }
                     }
                   }
                 }
               }

        let(:user) { create(:user) }
        let(:api_key) { user.api_key }

        before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '403', 'pro plan required (cloud lite users)' do
        schema type: :object, properties: { error: { type: :string } }

        let(:user) { create(:user) }
        let(:api_key) { user.api_key }

        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
          user.update!(plan: :lite)
        end

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end
  end
end
