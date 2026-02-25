# frozen_string_literal: true

# Streaming JSON handler relays sections and streamed values back to the importer instance.

class JsonStreamHandler < Oj::Saj
  HashState = Struct.new(:data, :root, :key)
  ArrayState = Struct.new(:array, :key)
  StreamState = Struct.new(:key)

  def initialize(processor)
    super()
    @processor = processor
    @stack = []
  end

  def hash_start(key = nil, *_)
    state = HashState.new({}, @stack.empty?, normalize_key(key))
    @stack << state
  end

  def hash_end(key = nil, *_)
    state = @stack.pop
    value = state.data
    parent = @stack.last

    dispatch_to_parent(parent, value, normalize_key(key) || state.key)
  end

  def array_start(key = nil, *_)
    normalized_key = normalize_key(key)
    parent = @stack.last

    if parent.is_a?(HashState) && parent.root && @stack.size == 1 && Users::ImportData::STREAMED_SECTIONS.include?(normalized_key)
      @stack << StreamState.new(normalized_key)
    else
      @stack << ArrayState.new([], normalized_key)
    end
  end

  def array_end(key = nil, *_)
    state = @stack.pop
    case state
    when StreamState
      @processor.send(:finish_stream, state.key)
    when ArrayState
      value = state.array
      parent = @stack.last
      dispatch_to_parent(parent, value, normalize_key(key) || state.key)
    end
  end

  def add_value(value, key)
    parent = @stack.last
    dispatch_to_parent(parent, value, normalize_key(key))
  end

  private

  def normalize_key(key)
    key&.to_s
  end

  def dispatch_to_parent(parent, value, key)
    return unless parent

    case parent
    when HashState
      if parent.root && @stack.size == 1
        @processor.send(:handle_section, key, value)
      else
        parent.data[key] = value
      end
    when ArrayState
      parent.array << value
    when StreamState
      @processor.send(:handle_stream_value, parent.key, value)
    end
  end
end
