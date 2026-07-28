# frozen_string_literal: true

class Geojson::StreamHandler < Oj::Saj
  HashState = Struct.new(:data, :root, :key)
  ArrayState = Struct.new(:data, :key)
  FeatureStreamState = Data.define(:key)

  def initialize(&on_feature)
    super()
    raise ArgumentError, 'A feature callback is required' unless on_feature

    @on_feature = on_feature
    @stack = []
  end

  def hash_start(key = nil, *_)
    @stack << HashState.new({}, @stack.empty?, normalize_string(key))
  end

  def hash_end(key = nil, *_)
    state = @stack.pop
    value = state.data

    if state.root
      yield_feature(value) if value['type'] == 'Feature'
    else
      dispatch_to_parent(@stack.last, value, normalize_string(key) || state.key)
    end
  end

  def array_start(key = nil, *_)
    normalized_key = normalize_string(key)
    parent = @stack.last

    state = if parent.is_a?(HashState) && parent.root && normalized_key == 'features' && feature_collection?(parent)
              FeatureStreamState.new(normalized_key)
            else
              ArrayState.new([], normalized_key)
            end
    @stack << state
  end

  def array_end(key = nil, *_)
    state = @stack.pop
    return if state.is_a?(FeatureStreamState)

    dispatch_to_parent(@stack.last, state.data, normalize_string(key) || state.key)
  end

  def add_value(value, key)
    dispatch_to_parent(@stack.last, normalize_value(value), normalize_string(key))
  end

  private

  def feature_collection?(root)
    type = root.data['type']
    type.nil? || type == 'FeatureCollection'
  end

  def dispatch_to_parent(parent, value, key)
    return unless parent

    case parent
    when HashState
      parent.data[key] = value
    when ArrayState
      parent.data << value
    when FeatureStreamState
      yield_feature(value)
    end
  end

  def yield_feature(value)
    @on_feature.call(value) if value.is_a?(Hash) && value['type'] == 'Feature'
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
