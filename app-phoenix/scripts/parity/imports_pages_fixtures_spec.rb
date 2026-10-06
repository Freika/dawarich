# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixtures: the new-import, GPX import and preparing-download pages as Rails renders them',
               type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/imports_pages') }
  let(:now) { Time.utc(2026, 9, 26, 12, 0, 0) }
  let(:secret) { 'phoenix-a2-cookie-fixture-secret-not-for-production' }

  before { FileUtils.mkdir_p(dir.join('pages')) }

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  def write_json(name, data)
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      File.write(dir.join(name), "#{JSON.pretty_generate(data)}\n")
    else
      expect(JSON.parse(dir.join(name).read)).to eq(data.as_json)
    end
  end

  def users
    [
      { id: 9801, email: 'a73-owner@dawarich.test', status: :active, settings: { 'timezone' => 'Europe/Berlin' } },
      { id: 9802, email: 'a73-trial@dawarich.test', status: :trial, settings: { 'timezone' => 'UTC' } }
    ]
  end

  def gpx_counts(waypoints) = { 'waypoints_seen' => waypoints, 'trackpoints_seen' => 12, 'route_points_seen' => 0 }

  def imports
    [
      [980_101, 9801, 'fresh.gpx', 2, gpx_counts(2), 0, {}, nil, 3],
      [980_102, 9801, 'no waypoints.gpx', 2, gpx_counts(0), 0, {}, nil, 0],
      [980_103, 9801, 'extracted & done.gpx', 2, gpx_counts(4), 3,
       { 'counts' => { 'visits' => 2, 'places' => 3, 'tracks' => 4, 'segments' => 5 } }, nil, 0],
      [980_104, 9801, 'running.gpx', 2, gpx_counts(1), 2, { 'started_at' => 600 }, nil, 0],
      [980_105, 9801, 'queued.gpx', 2, gpx_counts(1), 1, { 'started_at' => 60 }, nil, 0],
      [980_106, 9801, 'stalled.gpx', 2, gpx_counts(1), 2, { 'started_at' => 25_200 }, nil, 0],
      [980_107, 9801, 'failed.gpx', 2, gpx_counts(1), 4, { 'error_message' => 'Bad <b>waypoint</b> & more' },
       nil, 0],
      [980_108, 9801, 'legacy.gpx', 2, nil, 0, {}, nil, 0],
      [980_109, 9801, 'wrapped.gpx', 2, gpx_counts(1), 0, {}, ['wrapped.gpx.zip', 'wrapped.gpx'], 0],
      [980_110, 9801, 'unsupported flag.gpx', 3, gpx_counts(1), 5, {}, nil, 0],
      [980_201, 9802, 'trial one.gpx', 2, gpx_counts(1), 0, {}, nil, 0],
      [980_202, 9802, 'trial two.gpx', 2, gpx_counts(1), 0, {}, nil, 0],
      [980_111, 9801, 'normal.csv', 2, {}, 5, {}, nil, 0, 10]
    ].each_with_index.map do |(id, user_id, name, status, raw, extraction, data, file, points, source), index|
      { id:, user_id:, name:, source: source || 4, status:, raw_data: raw,
        additional_data_extraction_status: extraction, additional_data_extraction: data,
        created_at: (now - (index + 1).hours).iso8601, file:, points: }
    end
  end

  def extraction_data(row)
    data = row[:additional_data_extraction].dup
    data['started_at'] = (now - data['started_at']).iso8601 if data.key?('started_at')
    data
  end

  def pages
    [
      ['new_en', 9801, '/imports/new', 200],
      ['new_trial_en', 9802, '/imports/new', 200],
      ['show_not_attempted', 9801, '/imports/980101', 200],
      ['show_no_waypoints', 9801, '/imports/980102', 200],
      ['show_completed', 9801, '/imports/980103', 200],
      ['show_running', 9801, '/imports/980104', 200],
      ['show_pending', 9801, '/imports/980105', 200],
      ['show_stalled', 9801, '/imports/980106', 200],
      ['show_failed', 9801, '/imports/980107', 200],
      ['show_legacy_raw', 9801, '/imports/980108', 200],
      ['show_unsupported_flag', 9801, '/imports/980110', 200],
      ['download_preparing', 9801, '/imports/980109/download', 202],
      ['show_csv_en', 9801, '/imports/980111', 200],
      ['edit_csv_en', 9801, '/imports/980111/edit', 200],
      ['show_csv_de', 9801, '/imports/980111?locale=de', 200],
      ['edit_csv_de', 9801, '/imports/980111/edit?locale=de', 200]
    ] + %w[es fr pl ca zh].flat_map do |locale|
      [["show_csv_#{locale}", 9801, "/imports/980111?locale=#{locale}", 200],
       ["edit_csv_#{locale}", 9801, "/imports/980111/edit?locale=#{locale}", 200]]
    end
  end

  def create_users!
    users.map do |u|
      user = create(:user, id: u[:id], email: u[:email], changelog_consent: :declined)
      user.update_columns(settings: user.settings.merge(u[:settings]).merge('onboarding_completed' => true))
      { id: u[:id], email: u[:email], status: User.statuses[u[:status]], settings: user.reload.settings }
    end
  end

  def create_imports!
    imports.each do |row|
      import = Import.new(row.slice(:id, :user_id, :name, :raw_data)
                             .merge(source: Import.sources.key(row[:source]), status: Import.statuses.key(row[:status]),
                                    additional_data_extraction: extraction_data(row),
                                    created_at: Time.iso8601(row[:created_at]), updated_at: now))
      import.skip_background_processing = true
      import.save!(validate: false)
      import.update_columns(additional_data_extraction_status: row[:additional_data_extraction_status])
      attach!(import, *row[:file]) if row[:file]
      row[:points].times { |n| create(:point, user: import.user, import:, timestamp: now.to_i - (n * 60)) }
    end
  end

  def attach!(import, filename, original)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('PK'), filename:, content_type: 'application/zip',
      metadata: { 'dawarich_client_wrapped' => true, 'dawarich_original_filename' => original }
    )
    import.file.attach(blob)
    { blob_id: blob.id, filename:, byte_size: blob.byte_size, checksum: blob.checksum }
  end

  def source_http(error = nil)
    body = error ? nil : response.body
    if body
      doc = Nokogiri::HTML5(body)
      doc.css('input[name="authenticity_token"]').each { _1['value'] = 'CSRF' }
      doc.css('meta[name="csrf-token"], meta[name="csp-nonce"]').each { _1['content'] = 'CSRF' }
      doc.css('[nonce]').each { _1['nonce'] = 'NONCE' }
      doc.css('[signed-stream-name]').each { _1['signed-stream-name'] = 'SIGNED' }
      doc.css('a[href*="/rails/active_storage/"]').each { _1['href'] = 'ORIGINAL' }
      body = doc.to_html unless response.body.empty?
    end
    { 'status' => error ? nil : response.status, 'body' => FixtureRecording.normalize(body),
      'media_type' => error ? nil : response.media_type, 'location' => error ? nil : response.location,
      'headers' => error ? {} : response.headers.slice('Content-Type', 'Vary', 'Cache-Control', 'Refresh'),
      'set_cookie' => !error && response.headers['Set-Cookie'].present?, 'flash' => error ? {} : flash.to_hash,
      'error' => error && { 'class' => error.class.name, 'message' => FixtureRecording.normalize(error.message) } }
  end

  def import_state(user)
    attachments = ActiveStorage::Attachment.where(record_type: 'Import', record_id: user.import_ids)
    blobs = ActiveStorage::Blob.where(id: attachments.select(:blob_id))
    { imports: user.imports.order(:id).map { _1.attributes.except('processing_started_at') },
      attachments: attachments.order(:id).map(&:attributes),
      blobs: blobs.order(:id).map { _1.attributes.except('key') } }
  end

  def capture_import_actions
    rows = Hash.new { |h, k| h[k] = {} }
    user = User.find(9801)
    user.update_columns(plan: User.plans[:pro], status: User.statuses[:active], active_until: Time.utc(3026, 1, 1))
    recipes = %w[upload_empty upload_raw upload_signed upload_invalid upload_descriptor upload_duplicate
                 patch_valid put_valid put_blank put_unknown put_nil_source put_blank_source foreign missing guest
                 destroy_html destroy_turbo download_original download_missing download_preparing download_prepared]
    recipes += Import.sources.keys.map { "put_source_#{_1}" }
    recipes += (0..5).flat_map { |phase| ["extract_#{phase}", "unextract_#{phase}"] }
    [true, false].each do |hosted|
      RSpec::Mocks.with_temporary_scope do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(hosted)
        stub_const('SELF_HOSTED', hosted)
        recipes.each_with_index do |name, index|
          id = 981_000 + index + (hosted ? 0 : 1000)
          %w[imports active_storage_blobs active_storage_attachments].each do |table|
            sequence = "SELECT setval(pg_get_serial_sequence('#{table}','id'),#{id * 10 + 1_000_000},false)"
            ActiveRecord::Base.connection.execute(sequence)
          end
          import = Import.new(id:, user:, name: "source-#{id}.gpx", source: :gpx, status: :completed,
                              raw_data: gpx_counts(1), created_at: now, updated_at: now)
          import.skip_background_processing = true
          import.save!(validate: false)
          blob = ActiveStorage::Blob.create_and_upload!(key: "a12f3a-import-#{id}", io: StringIO.new('<gpx/>'),
                                                        filename: "source-#{id}.gpx",
                                                        content_type: 'application/gpx+xml')
          import.file.attach(blob) unless name == 'download_missing'
          reset!
          sign_in user unless name == 'guest'
          get(name == 'guest' ? '/users/sign_in' : '/imports/new')
          token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
          method = :put
          path = "/imports/#{id}"
          params = { import: { name: "renamed-#{id}.gpx" } }
          accept = 'text/html'
          task = '03'
          if name.start_with?('upload_')
            method = :post
            path = '/imports'
            task = '02'
            files = case name
                    when 'upload_empty' then ['']
                    when 'upload_raw' then [Rack::Test::UploadedFile.new(StringIO.new('<gpx/>'), 'application/gpx+xml',
                                                                         original_filename: 'raw.gpx')]
                    when 'upload_invalid' then ['invalid-signed-id']
                    when 'upload_descriptor' then [{ signed_id: blob.signed_id, client_wrapped: true,
original_filename: 'mismatch.gpx' }.to_json]
                    when 'upload_duplicate' then [blob.signed_id, blob.signed_id]
                    else [blob.signed_id]
                    end
            params = { import: { source: 'csv', files: } }
          elsif name.start_with?('extract_', 'unextract_')
            phase = name.split('_').last.to_i
            import.update_columns(additional_data_extraction_status: phase,
                                  additional_data_extraction: { 'started_at' => now.iso8601 })
            method = name.start_with?('unextract_') ? :delete : :post
            path = "/imports/#{id}/extraction"
            task = '04'
            params = { trust_source: 'false' }
            accept = 'text/vnd.turbo-stream.html'
          elsif name.start_with?('download_')
            method = :get
            path = "/imports/#{id}/download"
            params = {}
            task = '05'
            if %w[download_preparing download_prepared].include?(name)
              blob.update!(filename: 'source.gpx.zip', metadata: { 'dawarich_client_wrapped' => true,
                                                               'dawarich_original_filename' => 'source.gpx' })
              import.prepared_download.attach(blob) if name == 'download_prepared'
            end
          elsif name.start_with?('destroy_')
            method = :delete
            params = {}
            task = '04'
            accept = 'text/vnd.turbo-stream.html' if name == 'destroy_turbo'
          else
            method = :patch if name == 'patch_valid'
            params[:import][:name] = '' if name == 'put_blank'
            params[:import][:source] = 'unknown' if name == 'put_unknown'
            params[:import][:source] = nil if name == 'put_nil_source'
            params[:import][:source] = '' if name == 'put_blank_source'
            params[:import][:source] = name.delete_prefix('put_source_') if name.start_with?('put_source_')
            path = '/imports/99999999' if name == 'missing'
            import.update_columns(user_id: 9802) if name == 'foreign'
          end
          before = import_state(user)
          clear_enqueued_jobs
          error = nil
          begin
            public_send(method, path, params:, headers: { 'X-CSRF-Token' => token, 'Accept' => accept })
          rescue StandardError => e
            error = e
          end
          actual = source_http(error)
          expect(actual['status']).to eq(422) if name == 'upload_raw'
          expect(actual['status']).to eq(303) if %w[put_valid patch_valid upload_signed].include?(name)
          recipe = params.deep_dup
          if name.start_with?('upload_')
            recipe[:import][:files] = files.map do
              _1.is_a?(String) ? _1 : 'RAW_UPLOADED_FILE'
            end
          end
          jobs = enqueued_jobs.map { { class: _1[:job].name, args: _1[:args], queue: _1[:queue], at: _1[:at] } }
          rows[task]["#{hosted}-#{name}"] = actual.merge(
            'request' => { method:, path:, params: recipe, accept: }, 'self_hosted' => hosted,
            'before' => before, 'after' => import_state(user), 'jobs' => jobs
          )
        end
      end
    end
    rows.each { |task, cases| write_json("a12f3a-i#{task}.json", cases) }
  end

  it 'writes the pages and the seed they render' do
    expect(Rails.application.secret_key_base).to eq(secret)

    travel_to now do
      seeded_users = create_users!
      create_imports!
      users.each { |u| User.where(id: u[:id]).update_all(status: User.statuses[u[:status]]) }
      manifest = pages.map do |name, user_id, path, status|
        sign_in User.find(user_id)
        get path
        expect(response).to have_http_status(status)
        doc = Nokogiri::HTML5(response.body)
        doc.css('input[name="authenticity_token"]').each { |node| node['value'] = 'CSRF' }
        doc.css('a[href*="/rails/active_storage/"]').each { |node| node['href'] = 'ORIGINAL' }
        html = doc.at_css('body > div.container > div.w-full > div.flex').inner_html
        if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
          File.write(dir.join("pages/#{name}.html"), html)
        else
          expect(dir.join("pages/#{name}.html").read).to eq(html)
        end
        (@closure_pages ||= {})[name] = source_http.merge('path' => path)
        sign_out :user
        { name:, user_id:, path:, status:, title: doc.at_css('title').text }
      end
      write_json('pages.json', manifest)
      write_json('a12f3a-i01.json', @closure_pages)
      write_json('a12f3a-i06.json', @closure_pages)
      capture_import_actions
      write_json('seed.json', { now: now.iso8601, users: seeded_users,
                                imports: })
      %w[en de es fr pl ca zh].each do |locale|
        User.find(9801).update!(settings: User.find(9801).settings.merge('locale' => locale))
        sign_in User.find(9801)
        get '/imports/980111/edit'
        token = Nokogiri::HTML5(response.body).at_css('input[name="authenticity_token"]')['value']
        patch '/imports/980111',
              params: { authenticity_token: token, import: { name: 'changed.csv', source: 'unknown' } }
        expect(response).to have_http_status(:unprocessable_content)
        doc = Nokogiri::HTML5(response.body)
        doc.css('input[name="authenticity_token"]').each { |node| node['value'] = 'CSRF' }
        html = doc.at_css('body > div.container > div.w-full > div.flex').inner_html
        if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
          File.write(dir.join("pages/invalid_source_#{locale}.html"), html)
        else
          expect(dir.join("pages/invalid_source_#{locale}.html").read).to eq(html)
        end
        expect(Import.find(980_111).name).to eq('normal.csv')
        sign_out :user
      end
    end
  end
end
