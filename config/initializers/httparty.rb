# frozen_string_literal: true

# Suppress warnings about nil deprecation
# https://github.com/jnunemaker/httparty/issues/568#issuecomment-1450473603

HTTParty::Response.class_eval do
  def warn_about_nil_deprecation; end
end
