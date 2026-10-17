# frozen_string_literal: true

class PhoenixLeaseRecord < ApplicationRecord
  self.abstract_class = true

  POOL_SIZE = 2

  def self.connect!
    establish_connection(ActiveRecord::Base.connection_db_config.configuration_hash.merge(pool: POOL_SIZE))
  end

  connect! unless Rails.env.test?
end
