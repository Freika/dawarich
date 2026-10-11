# frozen_string_literal: true

module StorageRequestPathLogging
  def filtered_path
    prefix = Regexp.escape(ActiveStorage.routes_prefix)
    super.sub(%r{(#{prefix}/(?:disk|blobs(?:/(?:redirect|proxy))?|representations(?:/(?:redirect|proxy))?))/[^?]*},
              '\\1/[FILTERED]')
  end
end

ActiveSupport.on_load(:action_dispatch_request) do
  prepend StorageRequestPathLogging
end
