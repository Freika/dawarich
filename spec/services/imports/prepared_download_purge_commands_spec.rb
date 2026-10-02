# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::PreparedDownloadPurgeCommands do
  let(:user) { create(:user) }
  let(:import) { create(:import, user:, source: :gpx, skip_background_processing: true) }
  let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('<gpx/>'), filename: 'prepared.gpx') }
  let(:payload) do
    { 'blob_id' => blob.id, 'import_id' => import.id, 'user_id' => user.id, 'source_blob_id' => blob.id }
  end

  before do
    ActiveRecord::Base.connection.execute('CREATE SCHEMA IF NOT EXISTS phoenix')
    %w[20261001160000_import_blob_purges 20261001160100_import_blob_purge_bindings].each do |name|
      ActiveRecord::Base.connection.execute(File.read(Rails.root.join("app-phoenix/priv/repo/sql/#{name}.sql")))
    end
  end

  def receipt!
    values = %w[blob_id import_id user_id source_blob_id].map { |field| payload.fetch(field) }.join(',')
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      INSERT INTO phoenix.import_blob_purges(blob_id,import_id,user_id,source_blob_id) VALUES (#{values})
    SQL
  end

  it 'enqueues the actual purge job only for an authorized detached blob' do
    receipt!
    expect { described_class.call(payload) }.to have_enqueued_job(ActiveStorage::PurgeJob).with(blob)
  end

  it 'rejects missing, forged and foreign authorization' do
    expect { described_class.call(payload) }.not_to have_enqueued_job
    receipt!
    expect { described_class.call(payload.merge('user_id' => user.id + 1)) }.not_to have_enqueued_job
    expect { described_class.call(payload.merge('source_blob_id' => blob.id + 1)) }.not_to have_enqueued_job
    expect { described_class.call(payload.merge('blob_id' => blob.id.to_s)) }.not_to have_enqueued_job
  end

  it 'retains shared blobs including attachments created after authorization' do
    receipt!
    import.prepared_download.attach(blob)
    expect { described_class.call(payload) }.not_to have_enqueued_job
    expect(blob.reload.attachments.count).to eq(1)
  end

  it 'retains a blob if a surviving import now belongs to a different actor' do
    receipt!
    other = create(:user)
    import.update_columns(user_id: other.id)
    expect { described_class.call(payload) }.not_to have_enqueued_job
  end

  it 'can purge after import deletion and source replacement' do
    receipt!
    import.update_columns(name: 'replaced.gpx')
    import.file.attach(io: StringIO.new('<gpx/>'), filename: 'replacement.gpx')
    expect { described_class.call(payload) }.to have_enqueued_job(ActiveStorage::PurgeJob).with(blob)
    clear_enqueued_jobs
    Import.where(id: import.id).delete_all
    expect { described_class.call(payload) }.to have_enqueued_job(ActiveStorage::PurgeJob).with(blob)
  end

  it 'is harmless after the authorized blob has already disappeared' do
    receipt!
    ActiveStorage::Blob.where(id: blob.id).delete_all
    expect { described_class.call(payload) }.not_to have_enqueued_job
  end

  it 'retains a new attachment that appears after purge job scheduling' do
    receipt!
    described_class.call(payload)
    import.prepared_download.attach(blob)
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
    expect(ActiveStorage::Blob.find(blob.id).download).to eq('<gpx/>')
    expect(import.reload.prepared_download.blob_id).to eq(blob.id)
  end
end
