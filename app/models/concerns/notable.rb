# frozen_string_literal: true

module Notable
  extend ActiveSupport::Concern

  included do
    has_many :notes, as: :attachable, dependent: :nullify
  end
end
