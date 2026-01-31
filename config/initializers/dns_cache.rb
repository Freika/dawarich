# frozen_string_literal: true

# DNS Caching Layer
#
# Reduces DNS lookup overhead during bulk operations (e.g., reverse geocoding).
# Caches DNS resolutions in Rails.cache (Redis) for 5 minutes.

Rails.application.config.after_initialize do
  Resolv.class_eval do
    class << self
      alias_method :getaddress_without_cache, :getaddress

      def getaddress(name)
        # Skip caching for IP addresses (no DNS lookup needed)
        return getaddress_without_cache(name) if ip_address?(name)

        cache_key = "dawarich/dns:#{name}"
        cached = Rails.cache.read(cache_key)
        return cached if cached

        result = getaddress_without_cache(name)
        Rails.cache.write(cache_key, result, expires_in: 5.minutes)
        result
      end

      private

      def ip_address?(name)
        # Match IPv4 addresses (e.g., 192.168.1.1)
        return true if name.match?(/\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/)

        # Match IPv6 addresses (e.g., ::1, 2001:db8::1)
        return true if name.match?(/\A[\h:]+\z/)

        false
      end
    end
  end
end
