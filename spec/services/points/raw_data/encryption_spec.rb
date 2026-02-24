# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::Encryption do
  after { described_class.reset! }

  describe '.encrypt and .decrypt' do
    it 'round-trips binary data' do
      original = "test data with binary \x00\x01\xFF".b
      encrypted = described_class.encrypt(original)

      expect(encrypted).not_to eq(original)

      decrypted = described_class.decrypt(encrypted)
      expect(decrypted).to eq(original)
    end

    it 'round-trips gzip compressed data' do
      io = StringIO.new
      gz = Zlib::GzipWriter.new(io)
      gz.puts({ id: 1, raw_data: { lon: 13.4, lat: 52.5 } }.to_json)
      gz.close
      compressed = io.string.b

      encrypted = described_class.encrypt(compressed)
      decrypted = described_class.decrypt(encrypted)

      expect(decrypted).to eq(compressed)

      # Verify decompression still works
      result_io = StringIO.new(decrypted)
      result_gz = Zlib::GzipReader.new(result_io)
      parsed = JSON.parse(result_gz.readline)
      result_gz.close

      expect(parsed['id']).to eq(1)
      expect(parsed['raw_data']).to eq({ 'lon' => 13.4, 'lat' => 52.5 })
    end

    it 'raises on tampered data' do
      encrypted = described_class.encrypt('test data')
      tampered = encrypted.reverse

      expect { described_class.decrypt(tampered) }.to raise_error(StandardError)
    end

    it 'produces different ciphertext for the same plaintext' do
      plaintext = 'same data'
      encrypted1 = described_class.encrypt(plaintext)
      encrypted2 = described_class.encrypt(plaintext)

      # AES-GCM uses random nonces, so ciphertexts should differ
      expect(encrypted1).not_to eq(encrypted2)

      # But both should decrypt to the same plaintext
      expect(described_class.decrypt(encrypted1)).to eq(plaintext)
      expect(described_class.decrypt(encrypted2)).to eq(plaintext)
    end
  end

  describe '.decrypt_if_needed' do
    let(:plaintext_gzip) do
      io = StringIO.new
      gz = Zlib::GzipWriter.new(io)
      gz.puts({ id: 1, raw_data: { lon: 13.4 } }.to_json)
      gz.close
      io.string.b
    end

    context 'with format_version 1 (unencrypted) archive' do
      let(:archive) do
        instance_double(Points::RawDataArchive, metadata: { 'format_version' => 1, 'compression' => 'gzip' })
      end

      it 'returns content as-is without decrypting' do
        result = described_class.decrypt_if_needed(plaintext_gzip, archive)

        expect(result).to eq(plaintext_gzip)
      end

      it 'content remains valid gzip after passthrough' do
        result = described_class.decrypt_if_needed(plaintext_gzip, archive)

        gz = Zlib::GzipReader.new(StringIO.new(result))
        parsed = JSON.parse(gz.readline)
        gz.close

        expect(parsed['id']).to eq(1)
      end
    end

    context 'with format_version 2 (encrypted) archive' do
      let(:encrypted_content) { described_class.encrypt(plaintext_gzip) }
      let(:archive) do
        instance_double(Points::RawDataArchive, metadata: { 'format_version' => 2, 'encryption' => 'aes-256-gcm' })
      end

      it 'decrypts the content' do
        result = described_class.decrypt_if_needed(encrypted_content, archive)

        expect(result).to eq(plaintext_gzip)
      end
    end

    context 'with nil metadata' do
      let(:archive) { instance_double(Points::RawDataArchive, metadata: nil) }

      it 'returns content as-is' do
        result = described_class.decrypt_if_needed(plaintext_gzip, archive)

        expect(result).to eq(plaintext_gzip)
      end
    end
  end
end
