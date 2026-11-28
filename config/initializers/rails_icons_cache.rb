# frozen_string_literal: true

module RailsIconsCache
  MAX_ENTRIES = 1024
  STORE = Concurrent::Map.new
  MUTEX = Mutex.new

  def icon(name, library: RailsIcons.configuration.default_library, from: library, variant: nil, **arguments)
    key = icon_cache_key([name, from || library, variant, arguments])
    value = STORE[key] || MUTEX.synchronize do
      STORE.clear if STORE.size >= MAX_ENTRIES && !STORE.key?(key)
      STORE.compute_if_absent(key) { super.to_str.freeze }
    end
    value.html_safe
  end

  private

  def icon_cache_key(value)
    case value
    when Hash
      [Hash, value.map { |key, item| [icon_cache_key(key), icon_cache_key(item)].freeze }.freeze].freeze
    when Array
      [Array, value.map { |item| icon_cache_key(item) }.freeze].freeze
    else
      value.frozen? ? value : value.dup.freeze
    end
  end
end

RailsIcons::Helpers::IconHelper.prepend(RailsIconsCache)
