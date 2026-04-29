# frozen_string_literal: true

require 'swagger_helper'

describe 'Users API', type: :request do
  path '/api/v1/users/me' do
    get 'Returns the current user' do
      tags 'Users'
      consumes 'application/json'
      security [bearer_auth: []]
      parameter name: 'Authorization', in: :header, type: :string, required: true,
                description: 'Bearer token in the format: Bearer {api_key}'

      response '200', 'user found' do
        let(:user) { create(:user) }
        let(:Authorization) { "Bearer #{user.api_key}" }

        schema type: :object,
               properties: {
                 user: {
                   type: :object,
                   properties: {
                     id: { type: :integer },
                     email: { type: :string },
                     created_at: { type: :string, format: 'date-time' },
                     updated_at: { type: :string, format: 'date-time' },
                     api_key: { type: :string },
                     theme: { type: :string },
                     settings: {
                       type: :object,
                       properties: {
                         maps: { type: :object },
                         fog_of_war_meters: { type: :integer },
                         meters_between_routes: { type: :integer },
                         preferred_map_layer: { type: :string },
                         speed_colored_routes: { type: :boolean },
                         points_rendering_mode: { type: :string },
                         minutes_between_routes: { type: :integer },
                         time_threshold_minutes: { type: :integer },
                         merge_threshold_minutes: { type: :integer },
                         live_map_enabled: { type: :boolean },
                         route_opacity: { type: :number },
                         immich_url: { type: :string, nullable: true },
                         photoprism_url: { type: :string, nullable: true },
                         visits_suggestions_enabled: { type: :boolean },
                         speed_color_scale: { type: :string, nullable: true },
                         fog_of_war_threshold: { type: :integer }
                       }
                     },
                     admin: { type: :boolean }
                   }
                 }
               }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }

        run_test!
      end
    end

    delete 'Requests deletion of the current user account' do
      tags 'Users'
      description 'On Cloud, sends a confirmation email and returns 202; the account is only deleted ' \
                  'after the user clicks the confirmation link. On self-hosted, deletes the account ' \
                  'immediately when the correct password is supplied.'
      consumes 'application/json'
      produces 'application/json'
      security [bearer_auth: []]
      parameter name: 'Authorization', in: :header, type: :string, required: true,
                description: 'Bearer token in the format: Bearer {api_key}'
      parameter name: :payload, in: :body, required: false, schema: {
        type: :object,
        properties: {
          password: { type: :string, format: :password,
                      description: 'Required on self-hosted to confirm account deletion' }
        }
      }

      response '202', 'confirmation email sent (cloud)' do
        schema type: :object, properties: { message: { type: :string } }

        let(:user) { create(:user) }
        let(:Authorization) { "Bearer #{user.api_key}" }
        let(:payload) { {} }

        before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '422', 'cannot delete account (family owner with members)' do
        schema type: :object,
               properties: { error: { type: :string }, message: { type: :string } }

        let(:user) { create(:user) }
        let(:Authorization) { "Bearer #{user.api_key}" }
        let(:payload) { {} }

        before do
          allow_any_instance_of(User).to receive(:can_delete_account?).and_return(false)
        end

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        let(:payload) { {} }

        run_test!
      end
    end
  end
end
