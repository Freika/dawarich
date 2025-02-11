# frozen_string_literal: true

require 'swagger_helper'

describe 'Health API', type: :request do
  path '/api/v1/health' do
    get 'Retrieves application status' do
      tags 'Health'
      produces 'application/json'
      response '200', 'Healthy' do
        schema type: :object,
               properties: {
                 status: { type: :string }
               }

        header 'X-Dawarich-Response',
               type: :string,
               required: true,
               example: 'Hey, I\'m alive!',
               description: "Depending on the authentication status of the request, the response will be different. If the request is authenticated, the response will be 'Hey, I'm alive and authenticated!'. If the request is not authenticated, the response will be 'Hey, I'm alive!'."
        header 'X-Dawarich-Version',
               type: :string,
               required: true,
               example: '1.0.0',
               description: 'The version of the application, for example: 1.0.0'

        run_test!
      end
    end
  end
end
