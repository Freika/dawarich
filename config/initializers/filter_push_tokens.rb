# frozen_string_literal: true

Rails.application.config.filter_parameters += %i[push_token api_key_digest]
