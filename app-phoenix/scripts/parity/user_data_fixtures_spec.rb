# frozen_string_literal: true

require 'rails_helper'
require_relative 'user_data_fixtures_support'

RSpec.describe 'Phoenix fixtures: Rails user data' do
  before do
    @previous_urls = Rails.application.routes.default_url_options.dup
    Rails.application.routes.default_url_options = @previous_urls.merge(host: 'www.example.com')
  end

  after { Rails.application.routes.default_url_options = @previous_urls }

  include ActiveSupport::Testing::TimeHelpers
  self.use_transactional_tests = false

  before do
    allow(Rails.application).to receive(:secret_key_base).and_return(A12bFixtureSupport::SECRET)
    Notification.connection.execute("SELECT setval(pg_get_serial_sequence('notifications','id'),1,false)")
  end

  around do |example|
    Time.use_zone('UTC') { travel_to(Time.utc(2026, 10, 2, 12)) { example.run } }
  end

  it 'keeps Rails export ordering stable when the sequence starts below fixed fixture IDs' do
    UserDataFixturesSupport.with_users do
      Export.connection.execute("SELECT setval(pg_get_serial_sequence('exports','id'),1,false)")
      UserDataFixturesSupport.with_crypto do
        user = UserDataFixturesSupport.dataset('UTC')
        export = Users::ExportData.new(user).export
        entries = UserDataFixturesSupport.extracted(export)
        names = entries.fetch('exports.jsonl').lines.map { |line| JSON.parse(line).fetch('name') }

        expect(names).to eq(['synthetic export', export.name])
        expect(export.id).to eq(988_202)
      end
    end
  end

  it 'records every user-data entity and both reader versions' do
    result = UserDataFixturesSupport.capture
    expect(result.fetch('sections')).to contain_exactly(
      'settings', 'areas', 'imports', 'exports', 'trips', 'notifications', 'places', 'tags',
      'taggings', 'points', 'visits', 'stats', 'tracks', 'digests', 'raw_data_archives'
    )
    expect(result.fetch('versions')).to eq([1, 2])
    expect(result.fetch('restores').fetch('v2').fetch('result')).to include(
      'points_created' => 3, 'tracks_created' => 1, 'raw_data_archives_created' => 1
    )
    expect(result.fetch('restores').fetch('v1_reversed').fetch('result')).to include('points_created' => 3)
    expect(result.fetch('restores').fetch('v2_repeat').fetch('result')).to include('points_created' => 0)
    expect(result.fetch('boundaries').map { |row| row.fetch('count') }).to eq([4999, 5000, 5001])
    result.fetch('boundaries').each do |row|
      expect(row.fetch('result')).to include('points_created' => row['count'], 'places_created' => row['count'],
                                             'visits_created' => row['count'])
    end
    expect(result.fetch('cases').fetch('transaction_error').fetch('error').fetch('class'))
      .to eq('ActiveModel::UnknownAttributeError')
    expect(result.fetch('cases').fetch('transaction_error').fetch('settings').fetch('timezone')).to eq('UTC')
    expect(result.fetch('cases').fetch('dropped_columns').fetch('result').fetch('points_created')).to eq(1)
    expect(result.fetch('cases').fetch('missing_files').fetch('result').fetch('files_restored')).to eq(0)
    expect(result.fetch('export_errors').fetch('missing_attachment').fetch('status')).to eq('completed')
    expect(result.fetch('export_errors').fetch('missing_attachment').fetch('imports').first.fetch('file_error'))
      .to start_with('Failed to download:')
    expect(result.fetch('export_errors').fetch('tampered_archive').fetch('raw_data_archives').first.fetch('file_error'))
      .to start_with('Failed to export archive file:')
    RSpec::Mocks.with_temporary_scope do
      allow_any_instance_of(Points::AnomalyFilter).to receive(:call).and_raise(StandardError,
                                                                               'synthetic anomaly failure')
      result['post_commit_anomaly'] = UserDataFixturesSupport.with_users do
        user = UserDataFixturesSupport.owner
        UserDataFixturesSupport.restore('post_commit_anomaly', UserDataFixturesSupport.read_entries('v2'), user)
      end
    end
    expect(result.fetch('post_commit_anomaly').fetch('result')).to include('points_created' => 3)
    expect(result.fetch('post_commit_anomaly').fetch('error')).to be_nil
    expect(result.fetch('post_commit_anomaly').fetch('notifications').last.fetch('title'))
      .to eq('Data import completed')
    RSpec::Mocks.with_temporary_scope do
      allow(ActiveStorage::Blob.service).to receive(:upload).and_raise(StandardError, 'synthetic storage write failed')
      result['post_commit_storage_failure'] = UserDataFixturesSupport.with_users do
        UserDataFixturesSupport.restore('failed_attachment', UserDataFixturesSupport.read_entries('v2'),
                                        UserDataFixturesSupport.owner)
      end
    end
    expect(result.fetch('post_commit_storage_failure').fetch('error'))
      .to eq('class' => 'StandardError', 'message' => 'synthetic storage write failed')
    expect(result.fetch('post_commit_storage_failure').fetch('rows').fetch('points').size).to eq(3)
    expect(result.fetch('post_commit_storage_failure').fetch('notifications').map { |row| row['title'] })
      .to eq(['Synthetic <title>&', 'Data import completed', 'Data import failed'])
    result['nil_source_restores'] = %w[v1 v2].to_h do |version|
      outcome = UserDataFixturesSupport.with_users do
        user = UserDataFixturesSupport.owner
        Import.connection.execute("SELECT setval(pg_get_serial_sequence('imports','id'),988001,false)")
        UserDataFixturesSupport.insert(Import, user, 988_105, name: 'pending upload', source: nil)
        UserDataFixturesSupport.restore("nil_source_#{version}", UserDataFixturesSupport.read_entries(version), user,
                                        save: false)
      end
      expect(outcome.fetch('error')).to be_nil
      expect(outcome.fetch('result')).to include('points_created' => 3)
      expect(outcome.fetch('rows').fetch('imports').find { |row| row['name'] == 'pending upload' }.fetch('source'))
        .to be_nil
      [version, outcome]
    end
    failures = %w[invalid_jsonl_root invalid_jsonl_monthly invalid_manifest].to_h do |name|
      outcome = UserDataFixturesSupport.failure(name, entries: UserDataFixturesSupport.read_entries(name))
      expect(outcome.fetch('service').fetch('error')).to eq(result.fetch('cases').fetch(name).fetch('error'))
      expect(outcome.fetch('job').fetch('notifications').size).to eq(2)
      [name, outcome]
    end
    UserDataFixturesSupport.write('parser_failures.json', failures)
    events = %w[v1 v1_reversed].to_h do |version|
      recorded = UserDataFixturesSupport.with_users do
        user = UserDataFixturesSupport.owner
        Dir.mktmpdir('user-data-reader') do |directory|
          path = Pathname.new(directory)
          path.join('data.json').binwrite(UserDataFixturesSupport.read_entries(version).fetch('data.json'))
          reader = Users::ImportData::V1Handler.new(user, path, {})
          values = []
          sections = %w[counts settings areas imports exports trips stats notifications]
          allow(reader).to receive(:handle_section) do |name, value|
            values << ['section', name, value] if sections.include?(name)
          end
          allow(reader).to receive(:import_places_batch) do |batch|
            batch.each { |row| values << ['row', 'places', row] }
          end
          allow(reader).to receive(:import_visits_batch) do |batch|
            batch.each { |row| values << ['row', 'visits', row] }
          end
          allow_any_instance_of(Users::ImportData::Points).to receive(:add) do |_importer, row|
            values << ['row', 'points', row]
          end
          allow_any_instance_of(Users::ImportData::Points).to receive(:finalize).and_return(0)
          reader.process
          values
        end
      end
      expect(recorded.last[0..1]).to eq(%w[row points])
      [version, recorded]
    end
    UserDataFixturesSupport.write('v1_reader_events.json', events)
    UserDataFixturesSupport.write('capture.json', result)
    { '05' => result.slice('sections', 'exports'), '06' => result.slice('exports', 'boundaries'),
      '07' => result.slice('exports', 'export_errors'), '08' => result.slice('versions', 'restores', 'cases'),
      '09' => result.slice('restores', 'cases', 'post_commit_storage_failure'),
      '10' => result.slice('restores', 'boundaries', 'nil_source_restores'),
      '11' => result.slice('post_commit_anomaly', 'post_commit_storage_failure') }.each do |id, captured|
      UserDataFixturesSupport.write("a12f3a-e#{id}.json", captured)
    end
  end

  it 'captures rescued point SQL failure aborting the outer transaction' do
    capture = UserDataFixturesSupport.with_users do
      user = UserDataFixturesSupport.owner
      result = {}
      begin
        ActiveRecord::Base.transaction do
          data = [{ 'timestamp' => 1_767_225_600, 'lonlat' => 'POINT(12.4 51.3)', 'course' => '100000000000' }]
          result['inserted'] = Users::ImportData::Points.new(user, data).call
          ActiveRecord::Base.connection.select_value('SELECT 1')
        end
      rescue ActiveRecord::StatementInvalid => e
        result['sqlstate'] = e.cause.result.error_field(PG::Result::PG_DIAG_SQLSTATE)
      end
      result['points'] = user.points.count
      result
    end
    expect(capture).to eq('inserted' => 0, 'sqlstate' => '25P02', 'points' => 0)
    UserDataFixturesSupport.write('points_sql_failure.json', capture)
  end

  it 'portable raw payload is plaintext gzip' do
    result = UserDataFixturesSupport.portable
    bytes = Base64.strict_decode64(result.fetch('bytes'))
    expect(bytes.byteslice(0, 2).bytes).to eq([31, 139])
    expect(bytes).to eq(UserDataFixturesSupport.raw_gzip)
    expect(result.fetch('metadata')).to include('format_version' => 1,
                                                'content_checksum' => Digest::SHA256.hexdigest(bytes))
    expect(result.fetch('metadata')).not_to have_key('encryption')
    UserDataFixturesSupport.write('portable.json', result)
  end

  it 'missing manifest and data returns nil after failure notification' do
    result = UserDataFixturesSupport.failure('missing')
    expect(result.fetch('service')).to include('result' => nil, 'error' => nil)
    expect(result.fetch('service').fetch('notifications').map do |row|
      row.fetch('title')
    end).to eq(['Data import failed'])
    expect(result.fetch('job')).to include('error' => nil, 'status' => 'processing', 'points_count' => 1)
    expect(result.fetch('job').fetch('notifications').map { |row| row.fetch('title') }).to eq(['Data import failed'])
    UserDataFixturesSupport.write('missing.json', result)
  end

  it 'unsupported version raises after service and job notifications' do
    result = UserDataFixturesSupport.failure('version3')
    expected = { 'class' => 'StandardError', 'message' => 'Unsupported export format version: 3' }
    expect(result.fetch('service')).to include('result' => nil, 'error' => expected)
    expect(result.fetch('job')).to include('error' => expected, 'status' => 'failed', 'points_count' => 91)
    expect(result.fetch('service').fetch('notifications').size).to eq(1)
    expect(result.fetch('job').fetch('notifications').map { |row| row.fetch('title') })
      .to eq(['Data import failed', 'Data import failed'])
    UserDataFixturesSupport.write('version3.json', result)
  end
end

RSpec.describe 'Phoenix fixtures: user data settings boundary', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  around { |example| Time.use_zone('UTC') { travel_to(Time.utc(2026, 10, 2, 12)) { example.run } } }
  after { ActionController::Base.allow_forgery_protection = false }
  it 'captures the backup form and endpoint flashes in all shipped locales' do
    [Import, Export, ActiveStorage::Blob, ActiveStorage::Attachment].each do |model|
      sequence = model.connection.select_value("SELECT pg_get_serial_sequence('#{model.table_name}','id')")
      model.connection.execute("SELECT setval('#{sequence}',9888000,false)")
    end
    user = create(:user, id: 988_800, email: 'backup-http@example.test', admin: false,
                         settings: { 'timezone' => 'UTC' })
    user.update_columns(api_key: 'a12f' * 16)
    clear_enqueued_jobs
    traces = {}
    observe = lambda do
      document = Nokogiri::HTML5(response.body)
      document.css('meta[name="csrf-token"],meta[name="csp-nonce"],input[name="authenticity_token"]').each do |node|
        node[node.name == 'meta' ? 'content' : 'value'] = 'CSRF'
      end
      document.css('[nonce]').each { _1['nonce'] = 'NONCE' }
      document.css('turbo-cable-stream-source[signed-stream-name]').each { _1['signed-stream-name'] = 'STREAM' }
      { status: response.status, media_type: response.media_type, body: FixtureRecording.normalize(document.to_html),
        headers: response.headers.slice('Location', 'Content-Type', 'Cache-Control', 'Vary', 'X-Frame-Options'),
        set_cookie: response.headers['Set-Cookie'].present?, flash: flash.to_hash,
        imports: user.imports.order(:id).pluck(:id, :name, :source, :status, :additional_data_extraction_status),
        exports: user.exports.order(:id).pluck(:id, :name, :status),
        jobs: enqueued_jobs.map { { class: _1[:job].name, args: _1[:args], queue: _1[:queue] } } }
    end
    result = %w[en de es fr pl ca zh].to_h do |locale|
      traces[locale] = {}
      user.update!(settings: user.settings.merge('locale' => locale))
      sign_in(user)
      ActionController::Base.allow_forgery_protection = true
      get '/users/edit'
      traces[locale]['edit'] = observe.call
      ActionController::Base.allow_forgery_protection = false
      expect(response).to have_http_status(:ok)
      form = Nokogiri::HTML5(response.body).at_css('form[action="/settings/users/import"]')
      expect(form.at_css('input[type="file"]')['name']).to eq('archive')
      form.css('input[name="authenticity_token"]').each { |input| input['value'] = 'CSRF' }
      form.css('[data-direct-upload-url]').each { |input| input['data-direct-upload-url'] = 'UPLOAD' }
      form['data-upload-url-value'] = 'UPLOAD'
      get '/settings/users/export'
      expect(response).to have_http_status(:found)
      traces[locale]['export'] = observe.call
      export = { 'status' => response.status, 'location' => URI(response.location).path, 'flash' => flash.to_hash }
      get '/users/edit'
      post '/settings/users/import', params: { archive: '' }
      expect(response).to have_http_status(:found)
      traces[locale]['blank'] = observe.call
      blank = { 'status' => response.status, 'location' => URI(response.location).path, 'flash' => flash.to_hash }
      post '/settings/users/import', params: { archive: 'invalid-signed-id' }
      expect(response).to have_http_status(:found)
      traces[locale]['invalid'] = observe.call
      invalid = { 'status' => response.status, 'location' => URI(response.location).path, 'flash' => flash.to_hash }
      containers = { array: ['synthetic'], object: { nested: 'synthetic' } }.to_h do |kind, value|
        post '/settings/users/import', params: { archive: value }
        expect(response).to have_http_status(:found)
        expect(flash.to_hash).to have_key('alert')
        [kind, { status: response.status, location: URI(response.location).path, flash: flash.to_hash.slice('alert') }]
      end
      filename = %w[en de].include?(locale) ? 'backup.zip' : "#{locale}-backup.zip"
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('synthetic archive'), filename: filename,
                                                    content_type: 'application/zip')
      post '/settings/users/import', params: { archive: blob.signed_id }
      expect(response).to have_http_status(:found)
      expect(flash.to_hash).to have_key('notice')
      traces[locale]['valid'] = observe.call
      valid = { 'status' => response.status, 'location' => URI(response.location).path,
                'flash' => flash.to_hash.slice('notice') }
      blob.update_column(:filename, '')
      post '/settings/users/import', params: { archive: blob.signed_id }
      expect(response).to have_http_status(:found)
      traces[locale]['failed'] = observe.call
      failed = { 'status' => response.status, 'location' => URI(response.location).path,
                 'flash' => flash.to_hash.slice('alert') }
      user.update_columns(status: User.statuses.fetch('trial'), subscription_source: 0)
      user.imports.update_all(demo: true)
      4.times { |index| user.imports.create!(name: "#{locale} trial boundary #{index}", source: :user_data_archive) }
      blob.update_columns(filename: 'trial.zip', byte_size: 11.megabytes)
      trial = {}
      %w[count_four count_five size_limit size_over subscribed].each do |boundary|
        blob.update_column(:filename, "#{locale}-#{boundary}.zip")
        user.imports.update_all(demo: true) if boundary == 'size_limit'
        blob.update_column(:byte_size, 11.megabytes + 1) if boundary == 'size_over'
        if boundary == 'subscribed'
          user.update_column(:subscription_source, User.subscription_sources.fetch('paddle'))
          5.times { |index| user.imports.create!(name: "#{locale} subscribed boundary #{index}") }
        end
        before = [user.imports.count, ActiveStorage::Attachment.count, enqueued_jobs.size]
        post '/settings/users/import', params: { archive: blob.signed_id }
        rejected = %w[count_five size_over].include?(boundary)
        expect(flash.to_hash).to have_key(rejected ? 'alert' : 'notice')
        expect(user.imports.count - before[0]).to eq(rejected ? 0 : 1)
        traces[locale][boundary] = observe.call
        trial[boundary] = { 'status' => response.status, 'location' => URI(response.location).path,
                            'flash' => flash.to_hash.slice(rejected ? 'alert' : 'notice'),
                            'imports_created' => user.imports.count - before[0],
                            'attachments_created' => ActiveStorage::Attachment.count - before[1],
                            'jobs_created' => enqueued_jobs.size - before[2] }
      end
      sign_out(:user)
      [locale,
       { 'valid' => valid, 'failed' => failed, 'form' => form.to_html, 'export' => export, 'blank' => blank,
'invalid' => invalid, 'containers' => containers, 'trial' => trial }]
    end
    UserDataFixturesSupport.write('http.json', result)
    UserDataFixturesSupport.write('a12f3a-e04.json', { summary: result, traces: })
  end
end
