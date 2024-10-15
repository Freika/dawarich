# frozen_string_literal: true

class OwnTracks::RecParser
  attr_reader :file

  def initialize(file)
    @file = file
  end

  def call
    file.split("\n").map do |line|
      JSON.parse(line.split("\t*                 \t")[1])
    end
  end
end
