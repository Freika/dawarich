require_relative '../../../../config/environment'
raise 'own auth test database required' unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == 'dawarich_test_a11_auth_session'
ActionController::Base.allow_forgery_protection = true
ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = false
ActiveJob::Base.queue_adapter = :test
run Rails.application
Rails.application.load_server
