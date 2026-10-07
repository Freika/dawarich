# frozen_string_literal: true

module Users::Digests::Execution
  module_function

  def run(receipt, effect, user_id, year, month = nil, source: nil)
    unless PhoenixSchema.table?('digest_executions')
      outcome = yield(:generate)
      return outcome if %i[failed missing].include?(outcome)

      publication = yield(:publish)
      return yield(:failed, publication) if publication.is_a?(StandardError)

      return publication
    end

    identity = [effect, user_id, year.to_i, month.to_i]
    result = transaction(identity, receipt) do
      adopt(identity, receipt, source)
      saved = read(identity)
      next if saved && %w[generated published].include?(saved['state'])

      write(identity, 'claimed')
      outcome = yield(:generate)
      if outcome == :failed
        query('DELETE FROM phoenix.digest_executions WHERE effect=? AND user_id=? AND year=? AND month=?', *identity)
        next :failed
      end
      write(identity, 'generated', outcome == :missing ? 'missing' : 'mail')
      generation = Stats::EffectReceipts.id(receipt, effect.sub('calculate_', 'generate_'), nil, nil)
      mirror(generation, "#{effect.sub('calculate_', 'generate_')}:#{outcome == :missing ? 'missing' : 'mail'}")
    end
    return :failed if result == :failed

    transaction(identity, receipt) do
      saved = read(identity)
      next if saved['state'] == 'published'

      failed = false
      ActiveRecord::Base.transaction(requires_new: true) do
        publication = yield(:publish) if saved['outcome'] == 'mail'
        if publication.is_a?(StandardError)
          failed = publication
          raise ActiveRecord::Rollback
        end
      end
      next yield(:failed, failed) if failed

      write(identity, 'published', saved['outcome'])
      mirror(receipt, effect)
    end
  end

  def published?(effect, user_id, year, month = nil)
    return false unless PhoenixSchema.table?('digest_executions')

    transaction([effect, user_id, year.to_i, month.to_i], nil) do
      read([effect, user_id, year.to_i, month.to_i])&.fetch('state') == 'published'
    end
  end

  def transaction(identity, receipt)
    ActiveRecord::Base.transaction(requires_new: true) do
      query('SELECT pg_advisory_xact_lock(hashtextextended(?,0))', receipt) if receipt
      query('SELECT pg_advisory_xact_lock(hashtextextended(?,0))', JSON.generate(identity))
      yield
    end
  end

  def adopt(identity, receipt, source)
    saved = read(identity)
    return if saved && (!saved['legacy'] || saved['state'] == 'published')

    effect = identity.first
    generation = Stats::EffectReceipts.id(receipt, effect.sub('calculate_', 'generate_'), nil, nil)
    terminal = query('SELECT handler FROM phoenix.processed_commands WHERE event_id IN (?,?)', receipt, source)
    if terminal.any? { |row| row['handler'] == effect }
      write(identity, 'published', 'mail')
    else
      handler = query('SELECT handler FROM phoenix.processed_commands WHERE event_id=?',
                      generation).first&.fetch('handler')
      outcome = handler&.delete_prefix("#{effect.sub('calculate_', 'generate_')}:")
      write(identity, 'generated', outcome) if %w[mail missing].include?(outcome)
    end
    query('UPDATE phoenix.digest_executions SET legacy=false WHERE effect=? AND user_id=? AND year=? AND month=?',
          *identity)
  end

  def read(identity)
    query('SELECT state,outcome,legacy FROM phoenix.digest_executions ' \
          'WHERE effect=? AND user_id=? AND year=? AND month=?',
          *identity).first
  end

  def write(identity, state, outcome = nil)
    query('INSERT INTO phoenix.digest_executions(effect,user_id,year,month,state,outcome) VALUES(?,?,?,?,?,?) ' \
          'ON CONFLICT(effect,user_id,year,month) DO UPDATE ' \
          'SET state=EXCLUDED.state,outcome=EXCLUDED.outcome,updated_at=now()',
          *identity, state, outcome)
  end

  def mirror(receipt, handler)
    query('INSERT INTO phoenix.processed_commands(event_id,handler,processed_at) VALUES(?,?,now()) ' \
          'ON CONFLICT(event_id) DO NOTHING', receipt, handler)
  end

  def query(sql, *binds)
    ActiveRecord::Base.connection.exec_query(ActiveRecord::Base.sanitize_sql_array([sql, *binds]))
  end
  private_class_method :transaction, :adopt, :read, :write, :mirror, :query
end
