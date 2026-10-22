# frozen_string_literal: true

module Imports
  module SajParser
    STRICT_ERRORS = [EncodingError, JSON::ParserError].freeze

    module_function

    def parse(io, handler)
      strict = valid?(io)
      io.rewind
      strict ? Oj::Parser.new(:saj, handler:).load(io) : Oj.saj_parse(handler, io)
    end

    def valid?(io)
      Oj::Parser.new(:validate).load(io)
      true
    rescue *STRICT_ERRORS
      false
    end
  end
end
