# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::Encryption do
  describe '.encrypt and .decrypt' do
    it 'round-trips binary data' do
      original = "test data with binary \x00\x01\xFF".b
      encrypted = described_class.encrypt(original)

      expect(encrypted).not_to eq(original)

      decrypted = described_class.decrypt(encrypted)
      expect(decrypted).to eq(original)
      expect(decrypted.encoding).to eq(Encoding::ASCII_8BIT)
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
end
