# frozen_string_literal: true

require 'oj'

class StreamHandler < Oj::ScHandler
  attr_reader :import_id

  def initialize(import_id)
    @import_id = import_id
    @buffer = {}
  end

  def hash_start
    {}
  end

  def hash_end
    ImportGoogleTakeoutJob.perform_later(import_id, @buffer.to_json)

    @buffer = {}
  end

  def hash_set(_buffer, key, value)
    @buffer[key] = value
  end
end
