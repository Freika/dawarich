# frozen_string_literal: true

class OwnTracks::RecParser
  attr_reader :file

  def initialize(file)
    @file = file
  end

  def call
    file.split("\n").map do |line|
      # Try tab-separated first, then fall back to whitespace-separated
      parts = line.split("\t")

      # If tab splitting didn't work (only 1 part), try whitespace splitting
      parts = line.split(/\s+/) if parts.size == 1

      Oj.load(parts[2]) if parts.size > 2 && parts[1].strip == '*'
    end.compact
  end
end
