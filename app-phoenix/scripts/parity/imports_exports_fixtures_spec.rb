# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: the imports and exports lists as Rails renders them', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/imports_exports') }
  let(:now) { Time.utc(2026, 9, 26, 12, 0, 0) }
  let(:secret) { 'phoenix-a2-cookie-fixture-secret-not-for-production' }
  let(:helper) { ApplicationController.helpers }

  before { FileUtils.mkdir_p(dir.join('pages')) }

  def write_json(name, data)
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      File.write(dir.join(name), "#{JSON.pretty_generate(data)}\n")
    else
      expect(JSON.parse(dir.join(name).read)).to eq(data.as_json)
    end
  end

  def stamp(hours_ago) = (now - hours_ago.hours).utc.iso8601

  def user_settings
    immich = { 'immich_url' => 'https://immich.example', 'immich_api_key' => 'fixture' }
    photoprism = { 'photoprism_url' => 'https://photos.example', 'photoprism_api_key' => 'fixture' }
    {
      9701 => { 'timezone' => 'Europe/Berlin' },
      9703 => { 'timezone' => 'UTC' },
      9704 => { 'timezone' => 'America/New_York' },
      9705 => { 'timezone' => 'UTC' },
      9707 => immich,
      9708 => photoprism,
      9709 => immich.merge(photoprism),
      9710 => { 'immich_url' => 'https://immich.example', 'immich_api_key' => '  ' },
      9711 => { 'timezone' => 'UTC' }
    }
  end

  def import_row(id, user_id, name, source, status, hours_ago, opts = {})
    { id:, user_id:, name:, source:, status:, processed: opts.fetch(:processed, hours_ago * 10),
      doubles: opts.fetch(:doubles, 0), demo: opts.fetch(:demo, false), error_message: opts[:error],
      additional_data_extraction_status: opts.fetch(:extraction, 0), created_at: stamp(hours_ago),
      updated_offset: opts.fetch(:updated, 60), file: opts[:file], prepared: opts[:prepared] }
  end

  def export_row(id, user_id, name, file_format, status, hours_ago, opts = {})
    { id:, user_id:, name:, file_format:, file_type: opts.fetch(:type, 0), status:, url: opts[:url],
      error_message: opts[:error], created_at: stamp(hours_ago), file: opts[:file] }
  end

  def state_imports(user_id, base)
    [
      ['Semantic 2024.json', 0, 2, { processed: 1_234_567, doubles: 12, extraction: 3, file: 5_368_709 }],
      ['owntracks.rec', 1, 1, { processed: 250, file: 1023 }],
      ['Records.json', 2, 0, { processed: nil, doubles: nil, extraction: 5 }],
      ['phone.json', 3, 3, { processed: 0, error: 'Bad <b>file</b> & more', extraction: 4, file: 2048 }],
      ['ride.gpx', 4, 3, { extraction: 1, file: 1_048_576 }],
      ['immich', 5, 2, { demo: true, extraction: 2, file: 1536 }],
      ['shapes.geojson', 6, 4, { updated: 600, file: 100 }],
      ['photoprism', 7, 4, { updated: 7200 }],
      ['backup.zip', 8, 2, { file: 1_073_741_824 }],
      ['places.kml', 9, 2, { doubles: 1, file: 999_999 }],
      ['points.csv', 10, 2, { file: 10_240 }],
      ['run.tcx', 11, 2, {}],
      ['ride.fit', 12, 2, {}],
      ['trip.zip', 13, 2, { extraction: 3 }],
      ['Photos.json', 14, 2, {}],
      ['library', 15, 2, {}],
      ['unknown source', nil, 2, { processed: 1_000_000 }],
      ['prepared only.gpx', 4, 2, { prepared: 4096 }],
      ['stalled at an hour', 6, 4, { updated: 3600, file: 512 }],
      ['blank error', 4, 3, { error: '   ' }]
    ].each_with_index.map do |(name, source, status, opts), index|
      import_row(base + index + 1, user_id, name, source, status, index + 1, opts)
    end
  end

  def state_exports(user_id, base)
    [
      ['export_from_2024-03-01_to_2024-03-31.json', 0, 2,
       { file: [2_048_000, 'export_from_2024-03-01_to_2024-03-31.json.zip'] }],
      ['legacy.gpx', 1, 2, { url: 'exports/legacy.gpx' }],
      ['backup.zip', 2, 2, { type: 1 }],
      ['queued.json', 0, 0, {}],
      ['running.gpx', 1, 1, {}],
      ['broken.json', 0, 3, { error: 'Timeout <x>' }],
      ['broken.zip', 2, 3, { type: 1 }],
      ['odd name', nil, 2, { file: [3000, 'a b ü?.zip'] }],
      ['padded.json', 0, 2, { file: [1023, '  padded;name.json.zip '] }],
      ['blank url.json', 0, 2, { url: '  ' }],
      ['processing with file.json', 0, 1, { file: [42, 'early.json.zip'] }]
    ].each_with_index.map do |(name, file_format, status, opts), index|
      export_row(base + index + 1, user_id, name, file_format, status, index + 1, opts)
    end
  end

  def many_imports
    (1..27).map { |n| import_row(970_300 + n, 9703, format('Many %02d', n), 4, 2, n, { file: n * 1000 }) }
  end

  def many_exports
    (1..26).map do |n|
      export_row(970_350 + n, 9703, format('many_%02d.json', n), 0, 2, n,
                 { file: [n * 2000, format('many_%02d.json.zip', n)] })
    end
  end

  def sort_imports
    rows = [['Sort C', 0, 30, 300, 6], ['Sort A', 1, 10, nil, 5], ['Sort E', 2, 50, 100, 7],
            ['Sort B', 3, nil, 500, 4], ['Sort D', 4, 20, 200, 8]]
    rows.each_with_index.map do |(name, status, processed, file, hours), index|
      import_row(970_401 + index, 9704, name, 4, status, hours, { processed:, file: })
    end
  end

  def sort_exports
    [['Sort C', 0, 300, 6], ['Sort A', 1, nil, 5], ['Sort D', 2, 100, 7], ['Sort B', 3, 500, 4]]
      .each_with_index.map do |(name, status, size, hours), index|
        export_row(970_451 + index, 9704, name, 0, status, hours, { file: size && [size, "#{name}.json.zip"] })
      end
  end

  def foreign_imports
    [import_row(971_101, 9711, 'Foreign import', 4, 2, 1, { file: 777 }),
     import_row(970_154, 9711, 'Import record-type trap', 4, 2, 2, { file: 888 })]
  end

  def foreign_exports
    [export_row(971_151, 9711, 'Foreign export', 0, 2, 1, { file: [999, 'foreign.json.zip'] }),
     export_row(970_103, 9711, 'Export record-type trap', 0, 2, 2, { file: [555, 'trap.json.zip'] })]
  end

  def storage(imports, exports)
    originals = imports.filter_map do |r|
      r[:file] && ['Import', r[:id], 'file', 100_000_000, r[:file], "#{r[:name]}.bin"]
    end
    prepared = imports.filter_map do |r|
      r[:prepared] && ['Import', r[:id], 'prepared_download', 200_000_000, r[:prepared], "#{r[:name]}.zip"]
    end
    exported = exports.filter_map { |r| r[:file] && ['Export', r[:id], 'file', 300_000_000, *r[:file]] }
    files = originals + prepared + exported
    blobs = files.map { |_type, id, _name, shift, size, filename| { id: id + shift, filename:, byte_size: size } }
    attachments = files.map do |type, id, name, shift, _size, _filename|
      { id: id + shift, name:, record_type: type, record_id: id, blob_id: id + shift }
    end
    [blobs, attachments]
  end

  def create_users!
    user_settings.map do |id, settings|
      user = create(:user, id:, email: "a7-#{id}@dawarich.test", changelog_consent: :declined)
      user.update_columns(settings: user.settings.merge(settings).merge('onboarding_completed' => true))
      { id:, email: user.email, settings: user.reload.settings }
    end
  end

  def insert!(imports, exports, blobs, attachments)
    Import.insert_all(imports.map do |r|
      r.slice(:id, :user_id, :name, :processed, :doubles, :demo, :error_message)
       .merge(source: r[:source] && Import.sources.key(r[:source]), status: Import.statuses.key(r[:status]),
              additional_data_extraction_status:
                Import.additional_data_extraction_statuses.key(r[:additional_data_extraction_status]),
              created_at: Time.iso8601(r[:created_at]), updated_at: now - r[:updated_offset])
    end)
    Export.insert_all(exports.map do |r|
      r.slice(:id, :user_id, :name, :url, :error_message)
       .merge(status: Export.statuses.key(r[:status]),
              file_format: r[:file_format] && Export.file_formats.key(r[:file_format]),
              file_type: Export.file_types.key(r[:file_type]),
              created_at: Time.iso8601(r[:created_at]), updated_at: Time.iso8601(r[:created_at]))
    end)
    ActiveStorage::Blob.insert_all(blobs.map do |b|
      b.merge(key: "a7s1-#{b[:id]}", content_type: 'application/octet-stream', metadata: {}, service_name: 'test',
              checksum: 'a7s1', created_at: now)
    end)
    ActiveStorage::Attachment.insert_all(attachments.map { |a| a.merge(created_at: now) })
  end

  def pages
    [
      ['imports_states_en', 9701, '/imports'], ['exports_states_en', 9701, '/exports'],
      ['imports_empty_en', 9705, '/imports'], ['exports_empty_en', 9705, '/exports'],
      ['imports_immich_en', 9707, '/imports'], ['imports_photoprism_en', 9708, '/imports'],
      ['imports_both_en', 9709, '/imports'], ['imports_blank_key_en', 9710, '/imports'],
      ['imports_many_page1', 9703, '/imports'], ['imports_many_page2', 9703, '/imports?page=2'],
      ['imports_many_page3', 9703, '/imports?page=3'], ['imports_many_page0', 9703, '/imports?page=0'],
      ['imports_many_page_negative', 9703, '/imports?page=-1'],
      ['imports_many_page_2abc', 9703, '/imports?page=2abc'],
      ['imports_many_page_space', 9703, '/imports?page=%202'],
      ['imports_many_sorted_page2', 9703, '/imports?order_by=asc&page=2&sort_by=name'],
      ['imports_many_extra_param', 9703, '/imports?page=2&view=compact'],
      ['exports_many_page1', 9703, '/exports'], ['exports_many_page2', 9703, '/exports?page=2'],
      ['imports_sort_name_asc', 9704, '/imports?order_by=asc&sort_by=name'],
      ['imports_sort_byte_size_desc', 9704, '/imports?order_by=desc&sort_by=byte_size'],
      ['imports_sort_byte_size_asc', 9704, '/imports?order_by=asc&sort_by=byte_size'],
      ['imports_sort_processed_asc', 9704, '/imports?order_by=asc&sort_by=processed'],
      ['imports_sort_processed_desc', 9704, '/imports?order_by=desc&sort_by=processed'],
      ['imports_sort_status_asc', 9704, '/imports?order_by=asc&sort_by=status'],
      ['imports_sort_created_asc', 9704, '/imports?order_by=asc&sort_by=created_at'],
      ['imports_sort_bogus_asc', 9704, '/imports?order_by=asc&sort_by=bogus'],
      ['imports_sort_name_sideways', 9704, '/imports?order_by=sideways&sort_by=name'],
      ['imports_sort_bare', 9704, '/imports?sort_by'],
      ['imports_sort_empty', 9704, '/imports?sort_by='],
      ['imports_sort_array', 9704, '/imports?sort_by%5B%5D=name'],
      ['imports_sort_upcase', 9704, '/imports?sort_by=NAME'],
      ['exports_sort_name_asc', 9704, '/exports?order_by=asc&sort_by=name'],
      ['exports_sort_byte_size_desc', 9704, '/exports?order_by=desc&sort_by=byte_size'],
      ['exports_sort_byte_size_asc', 9704, '/exports?order_by=asc&sort_by=byte_size'],
      ['exports_sort_status_desc', 9704, '/exports?order_by=desc&sort_by=status'],
      ['exports_sort_processed', 9704, '/exports?sort_by=processed']
    ]
  end

  it 'writes the list pages and the seed they render' do
    expect(Rails.application.secret_key_base).to eq(secret)
    imports = state_imports(9701, 970_100) + many_imports + sort_imports + foreign_imports
    exports = state_exports(9701, 970_150) + many_exports + sort_exports + foreign_exports
    blobs, attachments = storage(imports, exports)

    travel_to now do
      users = create_users!
      insert!(imports, exports, blobs, attachments)
      manifest = pages.map do |name, user_id, path|
        sign_in User.find(user_id)
        get path
        expect(response).to have_http_status(:ok)
        doc = Nokogiri::HTML5(response.body)
        html = doc.at_css('body > div.container > div.w-full > div.flex').inner_html
        if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
          File.write(dir.join("pages/#{name}.html"), html)
        else
          expect(dir.join("pages/#{name}.html").read).to eq(html)
        end
        sign_out :user
        { name:, user_id:, path:, title: doc.at_css('title').text }
      end
      write_json('pages.json', manifest)
      write_json('seed.json', { users:, imports: imports.map { |r| r.except(:file, :prepared) },
                                exports: exports.map { |r| r.except(:file) }, blobs:, attachments: })
    end
  end

  it 'writes the human size corpus' do
    sizes = [0, 1, 2, 100, 1023, 1024, 1025, 1536, 2048, 10_240, 102_400, 999_999, 1_047_552, 1_048_552,
             1_048_575, 1_048_576, 1_572_864, 5_368_709, 10_485_760, 1_073_741_823, 1_073_741_824, 5_368_709_120,
             1_099_511_627_775, 1_099_511_627_776, 1_125_899_906_842_624, 1_152_921_504_606_846_976]
    corpus = sizes.map do |bytes|
      { locale: 'en', bytes:, text: I18n.with_locale(:en) { helper.number_to_human_size(bytes) } }
    end
    write_json('human_size.json', corpus)
  end

  it 'writes the human datetime corpus' do
    times = %w[2026-01-05T08:07:00Z 2026-03-29T00:30:00Z 2026-03-29T01:30:00Z 2026-07-15T23:59:00Z
               2026-10-25T00:30:00Z 2026-12-31T23:30:00Z] + (1..12).map { |m| format('2026-%02d-09T12:00:00Z', m) }
    zones = %w[UTC Etc/UTC Europe/London Etc/GMT Europe/Berlin Asia/Kathmandu America/St_Johns Pacific/Chatham]
    corpus = zones.product(times, %w[en]).map do |zone, time, locale|
      html = I18n.with_locale(locale) do
        Time.use_zone(zone) { helper.human_datetime(Time.iso8601(time).in_time_zone, zone) }
      end
      { zone:, time:, locale:, html: html.to_s }
    end
    write_json('human_datetime.json', corpus)
  end

  it 'writes the blob path corpus' do
    previous_host = Rails.application.routes.default_url_options[:host]
    expect(Rails.application.secret_key_base).to eq(secret)
    Rails.application.routes.default_url_options[:host] = 'www.example.com'
    names = ['export_from_2024-03-01_to_2024-03-31.json.zip', 'a b.gpx.zip', 'ümlaut ß.json.zip', 'q?x.zip',
             '  padded.zip  ', 'semi;colon:pipe|.zip', 'per%cent.zip', 'plus+eq=amp&.zip', 'at@tilde~.zip',
             "tab\tnew\nline.zip", 'back\\slash.zip', 'quote"lt<gt>.zip', 'star*dollar$.zip',
             'rtl‮override.zip', '#hash.zip', '[brackets].zip', "emoji \u{1F600}.zip", "apos'(paren)!.zip"]
    rows = names.each_with_index.map do |filename, index|
      { id: [1, 42, 123_456_789, 5_000_000_001][index % 4] + index, key: "a7s1-path-#{index}", filename:,
        content_type: 'application/zip', metadata: {}, service_name: 'test', byte_size: 1, checksum: 'a7s1',
        created_at: now }
    end
    ActiveStorage::Blob.insert_all(rows)
    corpus = ActiveStorage::Blob.where(id: rows.pluck(:id)).order(:id).map do |blob|
      { blob_id: blob.id, filename: blob[:filename],
        path: Rails.application.routes.url_helpers.rails_blob_path(blob, disposition: 'attachment') }
    end
    write_json('blob_paths.json', corpus)
  ensure
    Rails.application.routes.default_url_options[:host] = previous_host
  end
end
