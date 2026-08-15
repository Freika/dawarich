# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SharedLink::PhraseGenerator do
  describe '.call' do
    it 'returns a three-word hyphenated phrase' do
      phrase = described_class.call
      parts = phrase.split('-')
      expect(parts.size).to eq(3)
      expect(parts).to all(match(/\A[a-z]+\z/))
    end

    it 'returns a different phrase on successive calls' do
      phrases = Array.new(20) { described_class.call }.uniq
      expect(phrases.size).to be > 15
    end

    it 'uses only words from the wordlist' do
      wordlist = File.readlines(Rails.root.join('config/shared_link_wordlist.txt'), chomp: true).to_set
      10.times do
        described_class.call.split('-').each do |word|
          expect(wordlist).to include(word)
        end
      end
    end
  end
end
