# frozen_string_literal: true

require_relative '../../../../config/environment'
unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database.start_with?('dawarich_test')
  raise 'own auth test database required'
end

ActionController::Base.allow_forgery_protection = true
ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = false
ActiveJob::Base.queue_adapter = :test
run Rails.application
Rails.application.load_server
