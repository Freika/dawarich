# frozen_string_literal: true

class GoogleMaps::PhoneTakeoutStreamHandler < Oj::Saj
  STREAMED_ARRAYS = {
    'semanticSegments' => :semantic_segment,
    'rawSignals' => :raw_signal
  }.freeze

  HashState = Struct.new(:data, :root, :key)
  ArrayState = Struct.new(:data, :key)
  StreamState = Data.define(:section)
  DiscardState = Class.new
  # Counts the entries of a skipped section without materializing them, so callers can
  # report how much data was passed over.
  SkippedState = Struct.new(:section, :seen)

  def initialize(on_entry:, on_profile:, skip_sections: [], on_skipped: nil)
    super()
    @on_entry = on_entry
    @on_profile = on_profile
    @skip_sections = Array(skip_sections).to_set
    @on_skipped = on_skipped
    @stack = []
  end

  def hash_start(key = nil, *_)
    normalized_key = normalize_string(key)
    parent = @stack.last

    state = if discard_collection?(parent, normalized_key)
              DiscardState.new
            else
              HashState.new({}, @stack.empty?, normalized_key)
            end
    @stack << state
  end

  def hash_end(key = nil, *_)
    state = @stack.pop
    if state.is_a?(DiscardState)
      parent = @stack.last
      parent.seen += 1 if parent.is_a?(SkippedState)
      return
    end
    return if state.root

    dispatch_to_parent(@stack.last, state.data, normalize_string(key) || state.key)
  end

  def array_start(key = nil, *_)
    normalized_key = normalize_string(key)
    parent = @stack.last

    state = if @stack.empty?
              StreamState.new(:raw_array)
            elsif parent.is_a?(DiscardState)
              DiscardState.new
            elsif parent.is_a?(HashState) && parent.root
              section = STREAMED_ARRAYS[normalized_key]
              if section.nil?
                DiscardState.new
              elsif @skip_sections.include?(section)
                SkippedState.new(section, 0)
              else
                StreamState.new(section)
              end
            else
              ArrayState.new([], normalized_key)
            end
    @stack << state
  end

  def array_end(key = nil, *_)
    state = @stack.pop
    if state.is_a?(SkippedState)
      @on_skipped&.call(state.section, state.seen)
      return
    end
    return if state.is_a?(StreamState) || state.is_a?(DiscardState)

    dispatch_to_parent(@stack.last, state.data, normalize_string(key) || state.key)
  end

  def add_value(value, key)
    dispatch_to_parent(@stack.last, normalize_value(value), normalize_string(key))
  end

  private

  def discard_collection?(parent, key)
    return true if parent.is_a?(DiscardState) || parent.is_a?(SkippedState)

    parent.is_a?(HashState) && parent.root && key != 'userLocationProfile'
  end

  def dispatch_to_parent(parent, value, key)
    return unless parent

    case parent
    when HashState
      if parent.root && key == 'userLocationProfile'
        @on_profile.call(value)
      else
        parent.data[key] = value
      end
    when ArrayState
      parent.data << value
    when StreamState
      @on_entry.call(parent.section, value)
    end
  end

  def normalize_value(value)
    value.is_a?(String) ? normalize_string(value) : value
  end

  def normalize_string(value)
    return if value.nil?

    string = value.to_s
    return string if string.encoding == Encoding::UTF_8 && string.valid_encoding?

    string.dup.force_encoding(Encoding::UTF_8).scrub
  end
end
