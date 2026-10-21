# frozen_string_literal: true

module RailsIconsCache
  STORE = ActiveSupport::Cache::MemoryStore.new(size: 4.megabytes)

  def icon(name, library: RailsIcons.configuration.default_library, from: library, variant: nil, **arguments)
    key = Digest::SHA256.hexdigest(Marshal.dump([name.to_s, (from || library).to_s, variant.to_s, arguments]))
    STORE.fetch(key) { super.to_str }.html_safe
  end
end

RailsIcons::Helpers::IconHelper.prepend(RailsIconsCache)
