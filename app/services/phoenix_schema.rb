# frozen_string_literal: true

module PhoenixSchema
  QUERY = 'SELECT to_regclass($1) IS NOT NULL'

  module_function

  def table?(name)
    key = [Process.pid, ActiveRecord::Base.connection_pool.db_config, name]
    return true if present.include?(key)

    found = ActiveRecord::Base.connection.select_value(QUERY, 'PhoenixSchema', ["phoenix.#{name}"])
    present << key if found
    found
  end

  def reset! = present.clear

  def present = (@present ||= Concurrent::Set.new)

  private_class_method :present
end
