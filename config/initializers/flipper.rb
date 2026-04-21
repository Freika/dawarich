# frozen_string_literal: true

require 'flipper/adapters/active_record'

Rails.application.configure do
  config.flipper.memoize = true
end

Flipper.configure do |config|
  config.adapter { Flipper::Adapters::ActiveRecord.new }
end
