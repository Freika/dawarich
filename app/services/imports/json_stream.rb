# frozen_string_literal: true

class Imports::JsonStream
  def initialize(path, keys: [], root_array: false)
    @path = path
    @keys = keys
    @root_array = root_array
  end

  def metadata
    return @metadata if defined?(@metadata)

    @metadata = parse(nil).metadata
  end

  def each(&block)
    return enum_for(:each) unless block

    metadata
    parse(block)
  end

  private

  def parse(block)
    handler = Imports::JsonStreamHandler.new(keys: @keys, root_array: @root_array, &block)
    File.open(@path, 'rb') { |io| Imports::SajParser.parse(io, handler) }
    handler
  end
end
