# frozen_string_literal: true

module Stats::EffectReceipts
  NAMESPACE = ['6ba7b8119dad11d180b400c04fd430c8'].pack('H*').freeze

  module_function

  def id(source, effect, user_id, year, month = nil)
    bytes = Digest::SHA1.digest(NAMESPACE + JSON.generate([source, effect, user_id, year, month])).bytes.first(16)
    bytes[6] = (bytes[6] & 0x0f) | 0x50
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    hex = bytes.pack('C*').unpack1('H*')
    [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join('-')
  end

  def done?(receipt)
    return false unless PhoenixSchema.table?('processed_commands')

    query('SELECT 1 FROM phoenix.processed_commands WHERE event_id=?', receipt).any?
  end

  def once(receipt, handler)
    return yield unless PhoenixSchema.table?('processed_commands')

    ActiveRecord::Base.transaction(requires_new: true) do
      claimed = query('INSERT INTO phoenix.processed_commands(event_id,handler,processed_at) ' \
                      'VALUES(?,?,now()) ON CONFLICT(event_id) DO NOTHING RETURNING event_id', receipt, handler)
      next if claimed.empty?

      result = yield
      query('DELETE FROM phoenix.processed_commands WHERE event_id=?', receipt) if result == :failed
      result
    end
  end

  def query(sql, *binds)
    ActiveRecord::Base.connection.exec_query(ActiveRecord::Base.sanitize_sql_array([sql, *binds]))
  end
  private_class_method :query
end
