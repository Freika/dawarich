# frozen_string_literal: true

require 'swagger_helper'

describe 'Health API', type: :request do
  path '/api/v1/health' do
    get 'Retrieves application status' do
      tags 'Health'
      description 'Returns the health status of the application. No authentication required.'
      produces 'application/json'

      response '200', 'Healthy' do
        schema type: :object,
               properties: {
                 status: { type: :string, example: 'ok', description: 'Application health status' }
               }

        header 'X-Dawarich-Response',
               schema: {
                 type: :string,
                 example: 'Hey, I\'m alive!'
               },
               required: true,
               description: 'Depending on the authentication status, the response will differ. ' \
                            "If authenticated: 'Hey, I'm alive and authenticated!'. " \
                            "If not: 'Hey, I'm alive!'."
        header 'X-Dawarich-Version',
               schema: {
                 type: :string,
                 example: '1.0.0'
               },
               required: true,
               description: 'The version of the application, for example: 1.0.0'

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end
    end
  end
end
