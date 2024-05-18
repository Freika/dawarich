# frozen_string_literal: true

namespace :rswag do
  desc 'Generate Swagger docs'
  task generate: [:environment] do
    system 'bundle exec rake rswag:specs:swaggerize PATTERN="spec/swagger/**/*_spec.rb"'
  end
end
