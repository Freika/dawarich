# frozen_string_literal: true

module Photoprism
  class ResponseValidator < JsonResponseValidator
    PROVIDER = 'Photoprism'
    I18N_SCOPE = 'services.photoprism.response_validator'
  end
end
