# frozen_string_literal: true

class OwnTracks::RecParser
  attr_reader :file

  def initialize(file)
    @file = file
  end

  def call
    file.split("\n").map do |line|
      parts = line.split("\t")
      if parts.size > 2 && parts[1].strip == '*'
        JSON.parse(parts[2])
      else
        nil
      end
    end.compact
  end
end
