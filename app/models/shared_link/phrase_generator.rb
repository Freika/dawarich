# frozen_string_literal: true

class SharedLink
  class PhraseGenerator
    WORDLIST_PATH = Rails.root.join('config/shared_link_wordlist.txt')

    def self.call(word_count: 3)
      new.call(word_count: word_count)
    end

    def call(word_count:)
      Array.new(word_count) { wordlist[SecureRandom.random_number(wordlist.size)] }.join('-')
    end

    private

    def wordlist
      @wordlist ||= File.readlines(WORDLIST_PATH, chomp: true).freeze
    end
  end
end
