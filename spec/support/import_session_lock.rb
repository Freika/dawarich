# frozen_string_literal: true

module ImportSessionLock
  def hold_import_lock(key)
    ready = Queue.new
    release = Queue.new
    holder = Thread.new do
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      connection = PG.connect(host: config[:host], port: config[:port], user: config[:username],
                              password: config[:password], dbname: config[:database])
      connection.exec_params('SELECT pg_advisory_lock(hashtextextended($1,0))', [key])
      ready.push(:locked)
      release.pop
    rescue StandardError => e
      ready.push(e)
    ensure
      connection&.finish
    end
    locked = ready.pop
    raise locked unless locked == :locked

    yield
  ensure
    release&.push(true)
    holder&.join
  end
end

RSpec.configure { |config| config.include ImportSessionLock }
