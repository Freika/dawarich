# frozen_string_literal: true

require 'rails_helper'

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
    ]
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
        sign_out :user
        { name:, user_id:, path:, status:, title: doc.at_css('title').text }
      end
      write_json('pages.json', manifest)
      write_json('seed.json', { now: now.iso8601, users: seeded_users,
                                imports: })
      %w[en de].each do |locale|
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
