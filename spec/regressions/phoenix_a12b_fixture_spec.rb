# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix port: what Phoenix wrote in the A12b fixtures, read with the live Rails settings' do
  include ActiveSupport::Testing::TimeHelpers

  let(:secret) do
    JSON.parse(Rails.root.join('app-phoenix/test/fixtures/rails_cookies.json').read).fetch('rails_test_secret')
  end
  let(:crypto) { JSON.parse(Rails.root.join('app-phoenix/test/fixtures/a12b/crypto.json').read) }
  let(:now) { Time.iso8601(crypto['now']) }

  def turbo_salt = 'turbo/signed_stream_verifier_key'

  def verifier_for(salt, secret_key_base, **options)
    ActiveSupport::MessageVerifier.new(Rails.application.key_generator(secret_key_base).generate_key(salt), **options)
  end

  it 'still has the crypto settings Phoenix reimplements' do
    live = {
      'key_generator_digest' => ActiveSupport::KeyGenerator.hash_digest_class.name,
      'key_generator_iterations' => ActiveSupport::KeyGenerator.new('x').instance_variable_get(:@iterations),
      'message_serializer' => Rails.application.config.active_support.message_serializer.to_s,
      'metadata_in_serializer' => ActiveSupport::Messages::Metadata.use_message_serializer_for_metadata,
      'encryptor_cipher' => ActiveSupport::MessageEncryptor.default_cipher,
      'archive_salt' => Points::RawData::Encryption::SALT,
      'turbo_key_from_app_generator' =>
        Turbo.signed_stream_verifier_key == Rails.application.key_generator.generate_key(turbo_salt),
      'global_id_app' => GlobalID.app
    }
    expect(live).to eq(crypto['settings'])
    turbo = verifier_for(turbo_salt, Rails.application.secret_key_base, digest: 'SHA256', serializer: JSON)
    expect(Turbo::StreamsChannel.signed_stream_name(['x'])).to eq(turbo.generate('x'))
    expect(ActiveStorage.verifier.generate(1, purpose: :blob_id))
      .to eq(verifier_for('ActiveStorage', Rails.application.secret_key_base).generate(1, purpose: :blob_id))
  end

  it 'decrypts the archives Phoenix wrote' do
    entry = crypto['phoenix']['archives'].find { |e| e.values_at('env', 'base') == %w[absent secret] }
    allow(Rails.application).to receive(:secret_key_base).and_return(secret)
    Points::RawData::Encryption.reset!
    expect(Points::RawData::Encryption.decrypt(entry['message'])).to eq(Base64.strict_decode64(entry['gzip']))
  ensure
    Points::RawData::Encryption.reset!
  end

  it 'verifies the Turbo names and storage messages Phoenix signed' do
    turbo = verifier_for(turbo_salt, secret, digest: 'SHA256', serializer: JSON)
    crypto['phoenix']['turbo'].zip(crypto['turbo']).each { |signed, e| expect(turbo.verified(signed)).to eq(e['name']) }
    storage = verifier_for('ActiveStorage', secret)
    travel_to(now) do
      crypto['phoenix']['storage'].zip(crypto['messages']['storage']).each do |signed, e|
        expect(storage.verified(signed, purpose: e['purpose'])).to eq(e['data'])
      end
    end
  end

  it 'reads the shared-link cookies Phoenix encrypted' do
    travel_to(now) do
      crypto['phoenix']['cookies'].each do |cookie|
        entry = crypto['shared_link'].find { |e| e['id'] == cookie['id'] }
        env = Rails.application.env_config.merge(
          'action_dispatch.secret_key_base' => secret,
          'action_dispatch.key_generator' => Rails.application.key_generator(secret),
          'HTTP_COOKIE' => "shared_link_#{cookie['id']}=#{cookie['live']}"
        )
        jar = ActionDispatch::Request.new(env).cookie_jar
        expect(jar.encrypted["shared_link_#{cookie['id']}"]).to eq(entry['unlock'])
      end
    end
  end
end

RSpec.describe 'Phoenix port: the Active Storage messages and settings in the A12b storage fixture' do
  include ActiveSupport::Testing::TimeHelpers

  let(:secret) do
    JSON.parse(Rails.root.join('app-phoenix/test/fixtures/rails_cookies.json').read).fetch('rails_test_secret')
  end
  let(:storage) { JSON.parse(Rails.root.join('app-phoenix/test/fixtures/a12b/storage.json').read) }
  let(:verifier) do
    ActiveSupport::MessageVerifier.new(Rails.application.key_generator(secret).generate_key('ActiveStorage'))
  end

  it 'still has the Active Storage settings Phoenix reimplements' do
    expect(ActiveStorage.service_urls_expire_in.to_i).to eq(storage['settings']['service_urls_expire_in'])
    expect(ActiveStorage.content_types_to_serve_as_binary).to eq(storage['settings']['binary_content_types'])
    expect(ActiveStorage.content_types_allowed_inline).to eq(storage['settings']['inline_content_types'])
    expect(ActiveStorage.binary_content_type).to eq(storage['settings']['binary_content_type'])
    expect(ActiveStorage.routes_prefix).to eq(storage['settings']['routes_prefix'])
    expect(JSON.parse(Rails.root.join('app-phoenix/priv/i18n_approximations.json').read))
      .to eq(JSON.parse(I18n::Backend::Transliterator::HashTransliterator::DEFAULT_APPROXIMATIONS.to_json))
  end

  it 'verifies the disk download and upload messages and the blob id Phoenix signed' do
    travel_to(Time.iso8601(storage['now'])) do
      storage['phoenix']['downloads'].each do |download|
        signed = URI.decode_uri_component(URI(download['url']).path.split('/')[4])
        expect(verifier.verified(signed, purpose: :blob_key)).to include('key', 'disposition', 'service_name')
      end
      upload = URI.decode_uri_component(URI(storage['phoenix']['upload']['url']).path.split('/').last)
      expect(verifier.verified(upload, purpose: :blob_token)).to include('content_length' => 1024)
      expect(verifier.verified(storage['phoenix']['signed_id'], purpose: :blob_id)).to eq(970_501)
    end
  end
end
