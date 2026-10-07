# frozen_string_literal: true

class Points::TileEpochCommand < Points::TileEpoch
  class CacheWriteFailed < StandardError; end

  class << self
    def bump(user_id, timestamps: nil)
      write_tokens(user_id, timestamps ? years_from_timestamps(timestamps) : [])
    end

    private

    def write_tokens(user_id, years)
      years = [SENTINEL_YEAR] if years.empty?
      years.each do |year|
        written = Rails.cache.write(key(user_id, year), fresh_token, raw: true)
        raise CacheWriteFailed, 'tile epoch cache write failed' unless written == true
      end
    end
  end
end
