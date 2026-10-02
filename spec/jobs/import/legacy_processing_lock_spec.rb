# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import::ProcessJob, type: :job do
  let!(:import) { create(:import, source: :owntracks, skip_background_processing: true) }
  let(:job) { described_class.new }

  before do
    import.file.attach(io: File.open(Rails.root.join('spec/fixtures/files/owntracks/2024-03.rec')),
                       filename: '2024-03.rec', content_type: 'application/octet-stream')
  end

  it 'serializes a non-GPX processing job with the native destruction session lock' do
    ready = Queue.new
    release = Queue.new
    holder = Thread.new do
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      connection = PG.connect(host: config[:host], port: config[:port], user: config[:username],
                              password: config[:password], dbname: config[:database])
      key = "phoenix-import:#{import.id}"
      begin
        connection.exec_params('SELECT pg_advisory_lock(hashtextextended($1,0))', [key])
        ready.push(true)
        release.pop
        connection.exec_params('SELECT pg_advisory_unlock(hashtextextended($1,0))', [key])
      ensure
        connection.finish
      end
    end
    ready.pop
    expect { job.perform(import.id) }.to raise_error(Imports::GpxLegacy::Busy)
    expect(import.points.count).to eq(0)
    expect(import.reload).to be_created
  ensure
    release.push(true)
    holder&.join
  end

  it 'does not resume a non-GPX import already queued for destruction' do
    import.update!(status: :deleting)
    job.perform(import.id)
    expect(import.points.count).to eq(0)
    expect(import.reload).to be_deleting
    expect(Notification.where(user_id: import.user_id)).to be_empty
  end

  it 'does not process a queued non-GPX file for a soft-deleted actor' do
    import.user.update_column(:deleted_at, Time.current)
    job.perform(import.id)
    expect(import.points.count).to eq(0)
    expect(import.reload).to be_created
  end

  it 'preserves the legacy non-GPX processing of a completed import' do
    import.update!(status: :completed)
    job.perform(import.id)
    expect(import.points.count).to eq(9)
    expect(import.reload).to be_completed
  end
end
