# frozen_string_literal: true

module Reddis
  def self.client
    @client ||= Redis.new(url: ENV['REDIS_URL'])
  end
end
