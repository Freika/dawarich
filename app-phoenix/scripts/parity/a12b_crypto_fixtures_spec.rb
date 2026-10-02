# frozen_string_literal: true

require 'rails_helper'
require_relative 'a12b_fixture_support'

RSpec.describe 'Phoenix fixture: A12b crypto', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  def fx = A12bFixtureSupport

  def archive_envs = { 'absent' => nil, 'phrase' => fx::ARCHIVE_PHRASE, 'empty' => '' }
  def archive_bases = { 'secret' => fx::SECRET, 'rotated' => fx::ROTATED_BASE }
  def archive_cases = [%w[absent secret], %w[phrase secret], %w[empty secret], %w[phrase rotated], %w[absent rotated]]

  def with_archive_env(value, base)
    previous = ENV.fetch('ARCHIVE_ENCRYPTION_KEY', nil)
    value.nil? ? ENV.delete('ARCHIVE_ENCRYPTION_KEY') : (ENV['ARCHIVE_ENCRYPTION_KEY'] = value)
    allow(Rails.application).to receive(:secret_key_base).and_return(base)
    Points::RawData::Encryption.reset!
    yield
  ensure
    previous.nil? ? ENV.delete('ARCHIVE_ENCRYPTION_KEY') : (ENV['ARCHIVE_ENCRYPTION_KEY'] = previous)
    allow(Rails.application).to receive(:secret_key_base).and_call_original
    Points::RawData::Encryption.reset!
  end

  def outcome(content, metadata = { 'format_version' => 2 })
    result = Points::RawData::Encryption.decrypt_if_needed(content, Points::RawDataArchive.new(metadata: metadata))
    { 'outcome' => result.equal?(content) ? 'plain' : 'ok', 'gzip' => Base64.strict_encode64(result) }
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    { 'outcome' => 'invalid' }
  rescue StandardError => e
    { 'outcome' => 'error', 'class' => e.class.name }
  end

  def flip(text)
    text.dup.tap { |copy| copy[4] = copy[4] == 'A' ? 'B' : 'A' }
  end

  def raw_points
    user = create(:user, id: 970_401)
    raws = [{ 'lat' => 1.5, 'lon' => 2.5, 'note' => "</script>&<b>#{0x2028.chr(Encoding::UTF_8)}" },
            { 'nested' => { 'a' => [1, 2.5, nil, true], 'é' => 'café 😀' } },
            { 'empty_string' => '', 'big' => 12_345_678_901_234 }]
    raws.each_with_index.map { |raw, i| create(:point, id: 970_411 + i, user: user, raw_data: raw) }
  end

  def readability(message)
    archive_cases.to_h do |env, base|
      ["#{env}+#{base}", with_archive_env(archive_envs[env], archive_bases[base]) { outcome(message)['outcome'] }]
    end
  end

  def versions(gzip, encrypted)
    metadatas = [nil, {}, { 'format_version' => 1 }, { 'format_version' => '1' }, { 'format_version' => 2 },
                 { 'format_version' => '2' }, { 'format_version' => ' 2' }, { 'format_version' => '2abc' },
                 { 'format_version' => 2.9 }, { 'format_version' => '1_0' }, { 'format_version' => '' },
                 { 'format_version' => nil }]
    with_archive_env(nil, fx::SECRET) do
      metadatas.flat_map do |metadata|
        [['plain', gzip], ['encrypted', encrypted]].map do |kind, content|
          { 'metadata' => metadata, 'content' => kind }.merge(outcome(content, metadata).slice('outcome'))
        end
      end
    end
  end

  def tampered(message, gzip)
    key = ActiveSupport::KeyGenerator.new(fx::SECRET).generate_key(Points::RawData::Encryption::SALT, 32)
    encoded = Base64.strict_encode64(gzip)
    data, iv, tag = message.split('--')
    short = Base64.strict_encode64(Base64.strict_decode64(tag).byteslice(0, 12))
    cases = {
      'ciphertext_flip' => "#{flip(data)}--#{iv}--#{tag}", 'iv_flip' => "#{data}--#{flip(iv)}--#{tag}",
      'tag_flip' => "#{data}--#{iv}--#{flip(tag)}", 'tag_truncated' => "#{data}--#{iv}--#{short}",
      'separator_missing' => "#{data}#{iv}--#{tag}", 'separator_extra' => "#{data}--#{iv}--#{tag}--#{tag}",
      'not_base64' => "#{data}!--#{iv}--#{tag}", 'empty' => '',
      'non_string_payload' => ActiveSupport::MessageEncryptor.new(key).encrypt_and_sign(12_345),
      'purpose_envelope' => ActiveSupport::MessageEncryptor.new(key).encrypt_and_sign(encoded, purpose: 'other'),
      'expiry_envelope' => ActiveSupport::MessageEncryptor.new(key).encrypt_and_sign(encoded, expires_in: 1.hour),
      'marshal_payload' => ActiveSupport::MessageEncryptor.new(key, serializer: Marshal).encrypt_and_sign(encoded)
    }
    with_archive_env(nil, fx::SECRET) do
      cases.map { |name, value| { 'case' => name, 'message' => value }.merge(outcome(value).slice('outcome', 'class')) }
    end
  end

  def stored_archive
    with_archive_env(nil, fx::SECRET) do
      user = create(:user, id: 970_402)
      start = Time.utc(2026, 5, 10, 8).to_i
      points = Array.new(3) do |i|
        create(:point, id: 970_421 + i, user: user, timestamp: start + i, raw_data: { 'i' => i, 'note' => 'a&b' })
      end
      Points::RawData::Archiver.new.archive_specific_month(user.id, 2026, 5)
      archive = Points::RawDataArchive.find_by!(user_id: user.id, year: 2026, month: 5)
      { 'metadata' => archive.metadata, 'point_ids_checksum' => archive.point_ids_checksum,
        'storage_path' => archive.file.blob.key, 'message' => archive.file.download, 'ids' => points.map(&:id) }
    end
  end

  def archives
    points = raw_points
    gzip = Points::RawData::ChunkCompressor.new(Point.where(id: points.map(&:id))).compress[:data]
    written = archive_cases.map do |env, base|
      message = with_archive_env(archive_envs[env], archive_bases[base]) { Points::RawData::Encryption.encrypt(gzip) }
      { 'env' => env, 'base' => base, 'message' => message, 'gzip' => Base64.strict_encode64(gzip),
        'readable' => readability(message) }
    end
    { 'lines' => Zlib.gunzip(gzip).lines.map(&:chomp), 'written' => written,
      'versions' => versions(gzip, written.first['message']), 'tampered' => tampered(written.first['message'], gzip),
      'stored' => stored_archive }
  end

  def storage_samples
    separator = 0x2028.chr(Encoding::UTF_8)
    [{ 'key' => "a12b#{'a' * 24}", 'disposition' => 'attachment; filename="a.json"; filename*=UTF-8\'\'a.json',
       'content_type' => 'application/json', 'service_name' => 'local' },
     { 'key' => "a12b#{'b' * 24}", 'disposition' => "inline; filename=\"<a&b>#{separator}\"",
       'content_type' => nil, 'service_name' => 'test' },
     { 'key' => "a12b#{'c' * 24}", 'content_type' => 'image/png', 'content_length' => 1024,
       'checksum' => 'q9ZjDNBzwqk4oC0nGfX6Kw==', 'service_name' => 'local' }]
  end

  def messages
    verifier = ActiveStorage.verifier
    legacy = ActiveSupport::MessageVerifier.new(Rails.application.key_generator.generate_key('ActiveStorage'),
                                                serializer: :json_allow_marshal, force_legacy_metadata_serializer: true)
    expiry = (fx::NOW + 300).iso8601(3)
    storage = storage_samples.product(%w[blob_key blob_token]).map do |data, purpose|
      signed = verifier.generate(data, expires_in: 5.minutes, purpose: purpose)
      expect(verifier.verified(signed, purpose: purpose)).to eq(data)
      { 'data' => data, 'purpose' => purpose, 'expires_at' => expiry, 'signed' => signed }
    end
    blob_ids = [1, 62, 6_910_997].map { |id| { 'id' => id, 'signed' => verifier.generate(id, purpose: :blob_id) } }
    blob_ids << { 'id' => 8, 'signed' => verifier.generate(8, purpose: :blob_id, expires_in: 5.minutes),
                  'expires_at' => expiry }
    legacy_ids = [9, 10].map { |id| { 'id' => id, 'signed' => legacy.generate(id, purpose: :blob_id) } }
    legacy_ids.each { |entry| expect(ActiveStorage::Blob.signed_id_verifier.verified(entry['signed'], purpose: :blob_id)).to eq(entry['id']) }
    refused = { 'other_purpose' => verifier.generate(5, purpose: :blob_key), 'no_purpose' => verifier.generate(5),
                'expired' => verifier.generate(5, purpose: :blob_id, expires_at: fx::NOW) }
    refused.each_value { |signed| expect(verifier.verified(signed, purpose: :blob_id)).to be_nil }
    { 'storage' => storage, 'blob_ids' => blob_ids, 'legacy_blob_ids' => legacy_ids,
      'refused' => refused.map { |name, signed| { 'case' => name, 'signed' => signed, 'purpose' => 'blob_id' } } }
  end

  def turbo
    user = create(:user, id: 970_403)
    trip = create(:trip, id: 970_404, user: user)
    special = "a&b<c>#{0x2028.chr(Encoding::UTF_8)}"
    sources = [[user, :notifications], [user, :imports], [user, :posters], [trip], ['import_42_extraction'], [special]]
    sources.map do |streamables|
      signed = Turbo::StreamsChannel.signed_stream_name(streamables)
      name = Turbo::StreamsChannel.send(:stream_name_from, streamables)
      expect(Turbo::StreamsChannel.verified_stream_name(signed)).to eq(name)
      { 'parts' => streamables.map { |s| s.is_a?(ActiveRecord::Base) ? [s.class.name.underscore, s.id] : s.to_s },
        'name' => name, 'signed' => signed }
    end
  end

  def unlock_as(link, visitor)
    sign_in(visitor) if visitor
    post unlock_public_shared_link_path(link.id), params: { phrase: 'open sesame' }
    expect(response).to have_http_status(:redirect)
    sign_out(visitor) if visitor
    fx.set_cookie_line(response, "shared_link_#{link.id}")
  end

  def shared_link
    owner = create(:user, id: 970_405)
    tokyo = create(:user, id: 970_410, settings: { 'timezone' => 'Asia/Tokyo' })
    [['00000000-0000-4000-8000-000000970406', fx::NOW + 3.days, nil],
     ['00000000-0000-4000-8000-000000970407', nil, nil],
     ['00000000-0000-4000-8000-000000970410', nil, tokyo]].map do |id, expires_at, visitor|
      link = create(:shared_link, id: id, user: owner, magic_phrase: 'open sesame', expires_at: expires_at)
      { 'id' => link.id, 'magic_phrase' => 'open sesame', 'expires_at' => link.expires_at&.utc&.iso8601(6),
        'set_cookie' => unlock_as(link, visitor), 'unlock' => link.unlock_token,
        'visitor_timezone' => visitor&.timezone, 'time_zone_env' => ENV.fetch('TIME_ZONE', nil) }
    end
  end

  def crypto_settings
    {
      'key_generator_digest' => ActiveSupport::KeyGenerator.hash_digest_class.name,
      'key_generator_iterations' => ActiveSupport::KeyGenerator.new('x').instance_variable_get(:@iterations),
      'message_serializer' => Rails.application.config.active_support.message_serializer.to_s,
      'metadata_in_serializer' => ActiveSupport::Messages::Metadata.use_message_serializer_for_metadata,
      'encryptor_cipher' => ActiveSupport::MessageEncryptor.default_cipher,
      'archive_salt' => Points::RawData::Encryption::SALT,
      'turbo_key_from_app_generator' => Turbo.signed_stream_verifier_key == turbo_key,
      'global_id_app' => GlobalID.app
    }
  end

  def turbo_key = Rails.application.key_generator.generate_key('turbo/signed_stream_verifier_key')

  def expect_cookie_readable(entry)
    cookie = "shared_link_#{entry['id']}=#{fx.cookie_value(entry['set_cookie'])}"
    jar = ActionDispatch::Request.new(Rails.application.env_config.merge('HTTP_COOKIE' => cookie)).cookie_jar
    expect(jar.encrypted["shared_link_#{entry['id']}"]).to eq(entry['unlock'])
  end

  it 'writes or verifies test/fixtures/a12b/crypto.json from what Rails writes' do
    expect(Rails.application.secret_key_base).to eq(fx::SECRET)
    travel_to(fx::NOW) do
      stable = { 'now' => fx::NOW.iso8601(3), 'settings' => crypto_settings, 'messages' => messages, 'turbo' => turbo }
      if fx.write?
        previous = fx::DIR.join('crypto.json').exist? ? fx.read('crypto.json') : {}
        fx.write('crypto.json', previous.merge(stable, 'archives' => archives, 'shared_link' => shared_link))
      else
        recorded = fx.read('crypto.json')
        expect(recorded.slice(*stable.keys)).to eq(fx.normalized(stable))
        recorded['archives']['written'].each do |entry|
          entry['readable'].each do |label, expected|
            env, base = label.split('+')
            got = with_archive_env(archive_envs[env], archive_bases[base]) { outcome(entry['message'])['outcome'] }
            expect(got).to eq(expected), label
          end
        end
        recorded['shared_link'].each { |entry| expect_cookie_readable(entry) }
      end
    end
  end

  def phoenix_crypto_code(lines)
    <<~ELIXIR
      alias Dawarich.RawData.ArchiveFormat
      alias Dawarich.{RailsCookies, RailsMessages}
      fx = "test/fixtures/a12b/crypto.json" |> File.read!() |> Jason.decode!()
      ordered = "test/fixtures/a12b/crypto.json" |> File.read!() |> Jason.decode!(objects: :ordered_objects)
      secret = Application.fetch_env!(:dawarich, :rails_secret)
      envs = %{"absent" => %{}, "phrase" => %{"ARCHIVE_ENCRYPTION_KEY" => "#{fx::ARCHIVE_PHRASE}"}, "empty" => %{"ARCHIVE_ENCRYPTION_KEY" => ""}}
      bases = %{"secret" => secret, "rotated" => "#{fx::ROTATED_BASE}"}
      gzip = ArchiveFormat.build(fx["archives"]["lines"])
      archives = for %{"env" => e, "base" => b} <- fx["archives"]["written"], do: %{"env" => e, "base" => b, "gzip" => Base.encode64(gzip), "message" => ArchiveFormat.encrypt(gzip, ArchiveFormat.key(envs[e], bases[b]))}
      stored_lines = "#{Base64.strict_encode64(lines.to_json)}" |> Base.decode64!() |> Jason.decode!()
      stored_message = ArchiveFormat.encrypt(ArchiveFormat.build(stored_lines), ArchiveFormat.key(%{}, secret))
      stored_ids = Enum.map(stored_lines, &Jason.decode!(&1)["id"])
      stored = %{"message" => stored_message, "content_checksum" => ArchiveFormat.sha256(stored_message), "ids_checksum" => ArchiveFormat.ids_checksum(stored_ids)}
      turbo = for %{"parts" => parts} <- fx["turbo"], do: RailsMessages.stream_name(Enum.map(parts, fn [m, id] -> {String.to_atom(m), id}; p -> p end), secret)
      exp = ~U[2026-10-02 12:05:00.000Z]
      storage = for {entry, data} <- Enum.zip(fx["messages"]["storage"], Enum.map(ordered["messages"]["storage"], & &1["data"])), do: RailsMessages.sign_storage(data, entry["purpose"], exp, secret)
      cookies = for e <- fx["shared_link"], do: %{"id" => e["id"], "live" => RailsCookies.encrypt(e["unlock"], "shared_link_\#{e["id"]}", secret, ~U[2026-10-02 13:00:00.000Z]), "expired" => RailsCookies.encrypt(e["unlock"], "shared_link_\#{e["id"]}", secret, ~U[2026-10-02 11:59:59.000Z])}
      IO.puts(Jason.encode!(%{"archives" => archives, "stored" => stored, "turbo" => turbo, "storage" => storage, "cookies" => cookies}))
    ELIXIR
  end

  def expect_stored_archive_from_phoenix(points, stored)
    with_archive_env(nil, fx::SECRET) do
      archive = Points::RawDataArchive.create!(
        user: points.first.user, year: 2026, month: 6, chunk_number: 1, point_count: points.size,
        point_ids_checksum: stored['ids_checksum'], archived_at: Time.current,
        metadata: { 'format_version' => 2, 'compression' => 'gzip', 'encryption' => 'aes-256-gcm',
                    'content_checksum' => stored['content_checksum'], 'expected_count' => points.size,
                    'actual_count' => points.size }
      )
      archive.file.attach(io: StringIO.new(stored['message']), filename: '001.jsonl.gz.enc',
                          content_type: 'application/octet-stream',
                          key: "raw_data_archives/#{archive.user_id}/2026/06/001.jsonl.gz.enc")
      originals = points.to_h { |point| [point.id, point.raw_data] }
      ids = points.map(&:id)
      Point.where(id: ids).update_all(raw_data_archived: true, raw_data_archive_id: archive.id)
      Points::RawData::Verifier.new.verify_specific_archive(archive.id)
      expect(archive.reload.verified_at).to be_present
      Point.where(id: ids).update_all(raw_data: {})
      Points::RawData::Restorer.new.restore_to_database(archive.user_id, 2026, 6)
      expect(Point.where(id: ids).to_h { |point| [point.id, point.raw_data] }).to eq(originals)
    end
  end

  it 'reads what Phoenix writes (archives, Turbo names, storage messages, cookies) and records it' do
    recorded = fx.read('crypto.json')
    travel_to(fx::NOW) do
      user = create(:user, id: 970_408)
      points = Array.new(3) do |i|
        create(:point, id: 970_431 + i, user: user, raw_data: { 'n' => i, 's' => "x&<#{i}>" })
      end
      lines = Point.where(id: points.map(&:id)).order(:id).pluck(:id, Arel.sql('raw_data::text AS raw_text'))
                   .map { |id, raw| format('{"id":%<id>s,"raw_data":%<raw>s}', id: id, raw: raw) }
      out = fx.phoenix(phoenix_crypto_code(lines))

      out['archives'].each do |entry|
        pair = entry.values_at('env', 'base')
        recorded_entry = recorded['archives']['written'].find { |e| e.values_at('env', 'base') == pair }
        recorded_entry['readable'].each do |label, expected|
          env, base = label.split('+')
          got = with_archive_env(archive_envs[env], archive_bases[base]) { outcome(entry['message']) }
          expect(got['outcome']).to eq(expected), "phoenix #{entry['env']}+#{entry['base']} under #{label}"
          expect(got['gzip']).to eq(entry['gzip']) if expected == 'ok'
        end
      end
      expect_stored_archive_from_phoenix(points, out['stored'])

      out['turbo'].zip(recorded['turbo']).each do |signed, entry|
        expect(Turbo::StreamsChannel.verified_stream_name(signed)).to eq(entry['name'])
      end
      out['storage'].zip(recorded['messages']['storage']).each do |signed, entry|
        expect(ActiveStorage.verifier.verified(signed, purpose: entry['purpose'])).to eq(entry['data'])
      end

      owner = create(:user, id: 970_409)
      out['cookies'].each do |cookie|
        entry = recorded['shared_link'].find { |e| e['id'] == cookie['id'] }
        create(:shared_link, id: cookie['id'], user: owner, magic_phrase: entry['magic_phrase'],
                             expires_at: fx::NOW + 3.days)
        name = "shared_link_#{cookie['id']}"
        get public_shared_link_path(cookie['id']), headers: { 'Cookie' => "#{name}=#{cookie['live']}" }
        expect(response).to have_http_status(:ok)
        get public_shared_link_path(cookie['id']), headers: { 'Cookie' => "#{name}=#{cookie['expired']}" }
        expect(response).to have_http_status(:unauthorized)
      end

      fx.write('crypto.json', recorded.merge('phoenix' => out)) if fx.write?
    end
  end
end
