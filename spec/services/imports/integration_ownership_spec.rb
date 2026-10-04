# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Integration legacy ownership', :non_transactional do
  it 'holds the legacy owner through effects while a concurrent transfer waits' do
    user = create(:user)
    key = 'command:imports.immich_geodata'
    job_owner!(key, :sidekiq)
    holding = Queue.new
    release = Queue.new
    effects = Queue.new
    service = instance_double(Immich::ImportGeodata)
    allow(Immich::ImportGeodata).to receive(:new).and_return(service)
    allow(service).to receive(:call) do
      holding << true
      release.pop
      effects << :legacy
    end
    job = Import::ImmichGeodataJob.new(user.id)
    holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { job.perform_now }
    end

    begin
      holding.pop
      expect do
        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '50ms'")
          ActiveRecord::Base.connection.execute("UPDATE phoenix.job_owners SET owner='oban' WHERE key='#{key}'")
        end
      end.to raise_error(ActiveRecord::LockWaitTimeout)
    ensure
      release << true
      raise 'legacy integration did not finish' unless holder.join(5)
    end

    expect(holder.value).not_to be_a(Exception)
    expect(effects.size).to eq(1)
    JobOwnership.put!(key, :oban, pinned: false, by: 'spec')
    job.perform_now
    expect(effects.size).to eq(1)
    expect(JobOutbox.pending.where(command_type: 'imports.immich_geodata').pluck(:event_id, :payload))
      .to eq([[job.job_id, { 'user_id' => user.id, 'time_zone' => Time.zone.name }]])
  ensure
    JobOutbox.where(command_type: 'imports.immich_geodata').delete_all
    ActiveRecord::Base.connection.execute("DELETE FROM phoenix.job_owners WHERE key='#{key}'") if key
  end
end
