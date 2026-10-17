# frozen_string_literal: true

module ImportLease
  def hold_import_lock(name)
    phoenix_leases!
    connection = ActiveRecord::Base.connection
    connection.exec_update(
      "INSERT INTO phoenix.leases (name, holder, expires_at) VALUES ($1, 'phoenix-spec', now() + interval '1 hour')",
      'spec', [name]
    )
    yield
  ensure
    connection&.exec_update("DELETE FROM phoenix.leases WHERE name = $1 AND holder = 'phoenix-spec'", 'spec', [name])
  end
end

RSpec.configure { |config| config.include ImportLease }
