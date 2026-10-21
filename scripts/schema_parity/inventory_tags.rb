# frozen_string_literal: true

DATA_DEPENDENT_TAGS = %w[rows validates env effect invalid].freeze

def data_dependent?(tags)
  tags.intersect?(DATA_DEPENDENT_TAGS) || (%w[job gated] - tags).empty?
end
