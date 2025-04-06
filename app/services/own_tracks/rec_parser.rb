# frozen_string_literal: true

class OwnTracks::RecParser
  attr_reader :file

  def initialize(file)
    @file = file
  end

  def call
    file.split("\n").map do |line|
      parts = line.split("\t")

      Oj.load(parts[2]) if parts.size > 2 && parts[1].strip == '*'
    end.compact
  end
end
