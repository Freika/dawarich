# frozen_string_literal: true

require 'rails_helper'
require 'aws-sdk-s3'
require_relative 'a12b_fixture_support'

RSpec.describe 'Phoenix fixture: A12b Active Storage', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  def fx = A12bFixtureSupport
  def payload = ((0..255).map(&:chr).join * 4).b

  def compared
    %w[content-type content-disposition content-length content-range last-modified cache-control location etag
       set-cookie]
  end

  def mtime = (fx::NOW - 1.day).to_time
  def url_options = { protocol: 'http://', host: 'dawarich.example', port: 80 }

  def frozen(&) = travel_to(fx::NOW, &)

  def with_urls(&) = ActiveStorage::Current.set(url_options: url_options, &)

  def blob_specs
    [["a12b#{'a' * 24}", 'export_from_2024-03-01_to_2024-03-31.json', 'application/json'],
     ["a12b#{'b' * 24}", 'Bewegungsdaten März ü ß Æ.gpx', 'application/gpx+xml'],
     ["a12b#{'c' * 24}", ' a&b <c> "q" 😀.png ', 'image/png'],
     ["a12b#{'d' * 24}", "page#{0xa0.chr(Encoding::UTF_8)}.html", 'text/html'],
     ["a12b#{'e' * 24}", 'no type', nil]]
  end

  def make_blob(id, key, filename, type, stored:, checksum: Digest::MD5.base64digest(payload))
    blob = ActiveStorage::Blob.create!(id: id, key: key, filename: filename, content_type: type,
                                       byte_size: payload.bytesize, checksum: checksum, service_name: 'test',
                                       metadata: {})
    if stored
      blob.service.upload(key, StringIO.new(payload), checksum: blob.checksum)
      File.utime(mtime, mtime, blob.service.path_for(key))
    end
    blob
  end

  def stored_blobs
    blob_specs.each_with_index.map { |(key, name, type), i| make_blob(970_501 + i, key, name, type, stored: true) }
  end

  def fresh_blobs
    [make_blob(970_511, "a12b#{'f' * 24}", 'upload.gpx', 'application/gpx+xml', stored: false),
     make_blob(970_512, "a12b#{'g' * 24}", 'mismatch.gpx', 'application/gpx+xml', stored: false,
                                                                               checksum: Digest::MD5.base64digest('other'))]
  end

  def row(blob, stored)
    blob.attributes.transform_values { |v| v.respond_to?(:utc) ? v.utc.iso8601(6) : v }.merge('stored' => stored)
  end

  def with_env(values)
    previous = values.keys.index_with { |k| ENV.fetch(k, nil) }
    values.each { |k, v| v.nil? ? ENV.delete(k) : (ENV[k] = v) }
    yield
  ensure
    previous&.each { |k, v| v.nil? ? ENV.delete(k) : (ENV[k] = v) }
  end

  def s3_service(endpoint)
    with_env('AWS_ACCESS_KEY_ID' => 'a' * 20, 'AWS_SECRET_ACCESS_KEY' => 'b' * 40, 'AWS_REGION' => 'eu-central-1',
             'AWS_BUCKET' => 'dawarich-a12b', 'AWS_ENDPOINT_URL' => endpoint, 'AWS_ENDPOINT' => nil) do
      allow(Rails.env).to receive(:test?).and_return(false)
      config = YAML.safe_load(ERB.new(Rails.root.join('config/storage.yml').read).result, aliases: true)
      ActiveStorage::Service.configure(:s3, config)
    ensure
      allow(Rails.env).to receive(:test?).and_call_original
    end
  end

  def services
    @services ||= { 'aws' => s3_service(nil), 'custom' => s3_service('https://minio.example:9000'),
                    'ip' => s3_service('http://127.0.0.1:9000') }
  end

  def urls(blobs)
    with_urls do
      blobs.product([nil, 'attachment', 'inline', 'bogus']).map do |blob, disposition|
        type = blob.forced_disposition_for_serving || disposition
        { 'blob_id' => blob.id, 'disposition' => disposition, 'disk_url' => blob.url(disposition: disposition),
          's3' => services.transform_values do |s|
            s.url(blob.key, expires_in: 300, filename: blob.filename, content_type: blob.content_type_for_serving,
                            disposition: type)
          end }
      end
    end
  end

  def direct_uploads(blobs)
    with_urls do
      blobs.map do |blob|
        args = { content_type: blob.content_type, content_length: blob.byte_size, checksum: blob.checksum,
custom_metadata: {} }
        { 'blob_id' => blob.id,
          'disk' => { 'url' => blob.service_url_for_direct_upload,
'headers' => blob.service_headers_for_direct_upload },
          's3' => services.transform_values do |s|
            { 'url' => s.url_for_direct_upload(blob.key, expires_in: 300, **args),
              'headers' => s.headers_for_direct_upload(blob.key, filename: blob.filename, **args) }
          end }
      end
    end
  end

  def dispositions
    nbsp = 0xa0.chr(Encoding::UTF_8)
    names = blob_specs.map(&:second) + ['100%.zip', 'semi;colon/slash.zip', "tab\tname.zip", 'Ærøskøbing.zip',
                                        "#{nbsp}edge.zip#{nbsp}"]
    names.product(%w[attachment inline]).map do |name, type|
      sanitized = ActiveStorage::Filename.new(name).sanitized
      { 'type' => type, 'filename' => name, 'sanitized' => sanitized,
        'header' => ActionDispatch::Http::ContentDisposition.format(disposition: type, filename: sanitized) }
    end
  end

  def approximations
    table = I18n::Backend::Transliterator::HashTransliterator::DEFAULT_APPROXIMATIONS
    probe = "Ærøskøbing ß ü #{0x2028.chr(Encoding::UTF_8)} 😀"
    expect(I18n.available_locales.map do |locale|
      I18n.with_locale(locale) do
        I18n.transliterate(probe)
      end
    end.uniq.size).to eq(1)
    table
  end

  def record(name, method, path, headers: {}, body: nil, at: fx::NOW, csrf: false)
    travel_to(at) { send(method, path, headers: headers, params: body) }
    { 'name' => name, 'method' => method.to_s.upcase, 'path' => path, 'headers' => headers.except('X-CSRF-Token'),
      'csrf' => csrf, 'body' => body && Base64.strict_encode64(body), 'now' => at.iso8601(3),
      'status' => response.status, 'response_headers' => response.headers.to_h.slice(*compared),
      'response_body' => Base64.strict_encode64(response.body.to_s) }
  end

  def blob_key_path(signed, filename)
    "/rails/active_storage/disk/#{ERB::Util.url_encode(signed)}/#{ERB::Util.url_encode(filename)}"
  end

  def blob_key_message(key)
    ActiveStorage.verifier.generate({ key: key, disposition: 'inline', content_type: nil, service_name: 'test' },
                                    expires_in: 5.minutes, purpose: :blob_key)
  end

  def disk_requests(blob, missing)
    path, upload_path, traversal, missing_key = frozen do
      with_urls do
        [URI(blob.url(disposition: 'attachment')).path, URI(blob.service_url_for_direct_upload).path,
         blob_key_message('../a12b'), blob_key_message(missing.key)]
      end
    end
    stamp = mtime.httpdate
    [record('disk_plain', :get, path), record('disk_head', :head, path),
     record('disk_range', :get, path, headers: { 'Range' => 'bytes=0-9' }),
     record('disk_suffix', :get, path, headers: { 'Range' => 'bytes=-5' }),
     record('disk_open', :get, path, headers: { 'Range' => 'bytes=1000-' }),
     record('disk_clamped', :get, path, headers: { 'Range' => 'bytes=1020-99999' }),
     record('disk_unsatisfiable', :get, path, headers: { 'Range' => 'bytes=999999-' }),
     record('disk_backwards', :get, path, headers: { 'Range' => 'bytes=9-0' }),
     record('disk_multi', :get, path, headers: { 'Range' => 'bytes=0-1,4-5' }),
     record('disk_ims_equal', :get, path, headers: { 'If-Modified-Since' => stamp }),
     record('disk_ims_later', :get, path, headers: { 'If-Modified-Since' => (mtime + 3600).httpdate }),
     record('disk_ims_earlier', :get, path, headers: { 'If-Modified-Since' => (mtime - 3600).httpdate }),
     record('disk_expired', :get, path, at: fx::NOW + 301),
     record('disk_wrong_purpose', :get, "#{upload_path}/x.json"),
     record('disk_traversal', :get, blob_key_path(traversal, 'x')),
     record('disk_missing_file', :get, blob_key_path(missing_key, 'x'))]
  end

  def upload_requests(fresh, mismatch)
    urls = frozen { with_urls { [fresh, mismatch].map { |b| URI(b.service_url_for_direct_upload).path } } }
    type = { 'CONTENT_TYPE' => 'application/gpx+xml' }
    [record('put_wrong_type', :put, urls[0], headers: { 'CONTENT_TYPE' => 'text/plain' }, body: payload),
     record('put_wrong_length', :put, urls[0], headers: type, body: payload.byteslice(0, 1000)),
     record('put_length_header', :put, urls[0], headers: type.merge('CONTENT_LENGTH' => '1000'), body: payload),
     record('put_expired', :put, urls[0], headers: type, body: payload, at: fx::NOW + 301),
     record('put_mismatch', :put, urls[1], headers: type, body: payload),
     record('put_ok', :put, urls[0], headers: type, body: payload)]
  end

  def redirect_requests(blobs)
    helpers = Rails.application.routes.url_helpers
    first = blobs.first
    signed = ERB::Util.url_encode(first.signed_id)
    missing = ActiveStorage.verifier.generate(999_999_999, purpose: :blob_id)
    [record('redirect_attachment', :get,
            helpers.rails_service_blob_path(first.signed_id, first.filename, disposition: 'attachment')),
     record('redirect_inline', :get, helpers.rails_service_blob_path(blobs[2].signed_id, blobs[2].filename)),
     record('redirect_legacy', :get, "/rails/active_storage/blobs/#{signed}/x.json"),
     record('redirect_bad_signature', :get, "/rails/active_storage/blobs/redirect/#{signed}x/x"),
     record('redirect_missing_row', :get, helpers.rails_service_blob_path(missing, 'x'),
            headers: { 'Accept' => 'text/html' })]
  end

  def session_data(value)
    env = Rails.application.env_config.merge('HTTP_COOKIE' => "_dawarich_session=#{value}")
    ActionDispatch::Request.new(env).cookie_jar.encrypted['_dawarich_session']
  end

  def direct_upload_requests
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    sign_in create(:user, id: 970_520)
    get '/notifications'
    csrf_meta = response.body[/<meta name="csrf-token" content="([^"]+)"/, 1]
    session_cookie = cookies['_dawarich_session']
    allow(ActiveStorage::Blob).to receive(:generate_unique_secure_token).and_return("a12b#{'h' * 24}")
    ActiveRecord::Base.connection.execute("SELECT setval('active_storage_blobs_id_seq', 970599)")
    json = { 'CONTENT_TYPE' => 'application/json', 'Accept' => 'application/json' }
    blank = { blob: { filename: 'a.gpx', content_type: 'application/gpx+xml', byte_size: 1, checksum: '' } }.to_json
    good = { blob: { filename: 'track (1) ü.gpx', content_type: 'application/gpx+xml', byte_size: 1024,
                     checksum: Digest::MD5.base64digest(payload) } }.to_json
    requests = [record('upload_ok', :post, '/rails/active_storage/direct_uploads',
                       headers: json.merge('X-CSRF-Token' => csrf_meta), body: good, csrf: true),
                record('upload_no_csrf_json', :post, '/rails/active_storage/direct_uploads', headers: json, body: good),
                record('upload_no_csrf_html', :post, '/rails/active_storage/direct_uploads',
                       headers: { 'CONTENT_TYPE' => 'application/json', 'Accept' => 'text/html' }, body: good),
                record('upload_missing_blob', :post, '/rails/active_storage/direct_uploads',
                       headers: json.merge('X-CSRF-Token' => csrf_meta), body: '{}', csrf: true),
                record('upload_blank_checksum', :post, '/rails/active_storage/direct_uploads',
                       headers: json.merge('X-CSRF-Token' => csrf_meta), body: blank, csrf: true),
                record('upload_bad_json', :post, '/rails/active_storage/direct_uploads',
                       headers: json.merge('X-CSRF-Token' => csrf_meta), body: '{"blob":', csrf: true)]
    rewritten = requests.first['response_headers']['set-cookie']
    expect(rewritten.split('; ', 2).last).to eq('path=/; httponly; samesite=lax')
    expect(session_data(fx.cookie_value(rewritten)))
      .to eq(session_data(ERB::Util.url_encode(session_cookie))).and be_present
    { 'csrf_meta' => csrf_meta, 'session_cookie' => session_cookie,
      'time_zone' => Time.zone.tzinfo.name, 'row' => row(ActiveStorage::Blob.find(970_600), false),
      'requests' => requests }
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  def approximations_path = Rails.root.join('app-phoenix/priv/i18n_approximations.json')
  def unrecorded = %w[direct_upload upload_requests phoenix]

  def storage_settings
    { 'service_urls_expire_in' => ActiveStorage.service_urls_expire_in.to_i,
      'binary_content_types' => ActiveStorage.content_types_to_serve_as_binary,
      'inline_content_types' => ActiveStorage.content_types_allowed_inline,
      'binary_content_type' => ActiveStorage.binary_content_type,
      'routes_prefix' => ActiveStorage.routes_prefix,
      'verifier_digest' => ActiveStorage.verifier.instance_variable_get(:@digest) }
  end

  it 'writes or verifies test/fixtures/a12b/storage.json and priv/i18n_approximations.json from what Rails does' do
    expect(Rails.application.secret_key_base).to eq(fx::SECRET)
    detailed = Rails.application.env_config['action_dispatch.show_detailed_exceptions']
    Rails.application.env_config['action_dispatch.show_detailed_exceptions'] = false
    host! 'dawarich.example'
    stored, fresh, mismatch, missing, stable = frozen do
      blobs = stored_blobs
      upload, other = fresh_blobs
      gone = make_blob(970_513, "a12b#{'i' * 24}", 'gone.json', 'application/json', stored: false)
      [blobs, upload, other, gone,
       { 'now' => fx::NOW.iso8601(3), 'settings' => storage_settings, 'dispositions' => dispositions,
         'urls' => urls(blobs), 'direct_uploads' => direct_uploads(blobs + [upload]),
         'blob_ids' => blobs.map { |b| { 'id' => b.id, 'signed' => b.signed_id } } }]
    end
    requests = disk_requests(stored.first, missing) + upload_requests(fresh, mismatch) + redirect_requests(stored)
    expect(fresh.service.exist?(fresh.key)).to be(true)
    expect(mismatch.service.exist?(mismatch.key)).to be(false)
    uploads = direct_upload_requests
    rows = stored.map { |b| row(b, true) } + [fresh, mismatch, missing].map { |b| row(b, false) }
    data = stable.merge('blobs' => rows, 'requests' => requests, 'direct_upload' => uploads.except('requests'),
                        'upload_requests' => uploads['requests'])
    if fx.write?
      previous = fx::DIR.join('storage.json').exist? ? fx.read('storage.json') : {}
      fx.write('storage.json', previous.merge(data))
      approximations_path.write("#{Oj.dump(approximations, mode: :strict, indent: 2)}\n")
    else
      recorded = fx.read('storage.json')
      expect(recorded.except(*unrecorded)).to eq(fx.normalized(data.except(*unrecorded)))
      expect(JSON.parse(approximations_path.read)).to eq(fx.normalized(approximations))
    end
  ensure
    Rails.application.env_config['action_dispatch.show_detailed_exceptions'] = detailed
  end
end
