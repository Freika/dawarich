# frozen_string_literal: true

require 'swagger_helper'

describe 'Health API', type: :request do
  path '/api/v1/health' do
    get 'Retrieves application status' do
      tags 'Health'
      produces 'application/json'
      response '200', 'areas found' do
        run_test!
      end
    end
  end
end
