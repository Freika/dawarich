# frozen_string_literal: true

class Imports::JsonStreamHandler < Oj::Saj
  State = Struct.new(:data, :key)
  Stream = Class.new
  Discard = Class.new

  attr_reader :metadata

  def initialize(keys:, root_array:, &on_entry)
    super()
    @keys = keys
    @root_array = root_array
    @on_entry = on_entry
    @stack = []
  end

  def hash_start(key = nil, *_)
    state = if @stack.empty? || collecting?
              State.new({}, normalize(key))
            else
              Discard.new
            end
    @stack << state
  end

  def hash_end(*)
    finish_collection
  end

  def array_start(key = nil, *_)
    key = normalize(key)
    state = if (@stack.empty? && @root_array) || (root_hash? && @keys.include?(key))
              @stack.last.data[key] = [] if root_hash?
              Stream.new
            elsif collecting?
              State.new([], key)
            else
              Discard.new
            end
    @stack << state
  end

  def array_end(*)
    finish_collection
  end

  def add_value(value, key)
    append(value.is_a?(String) ? normalize(value) : value, normalize(key))
  end

  private

  def root_hash?
    @stack.size == 1 && @stack.last.is_a?(State) && @stack.last.data.is_a?(Hash)
  end

  def collecting?
    return !@on_entry.nil? if @stack.last.is_a?(Stream)

    @stack.last.is_a?(State) && !root_hash?
  end

  def finish_collection
    state = @stack.pop
    return unless state.is_a?(State)

    if @stack.empty?
      @metadata = state.data
    else
      append(state.data, state.key)
    end
  end

  def append(value, key)
    parent = @stack.last
    case parent
    when State
      parent.data.is_a?(Hash) ? parent.data[key] = value : parent.data << value
    when Stream
      @on_entry&.call(value)
    end
  end

  def normalize(value)
    return if value.nil?

    value.to_s.dup.force_encoding(Encoding::UTF_8).scrub
  end
end
