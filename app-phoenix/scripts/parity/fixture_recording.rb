# frozen_string_literal: true

module FixtureRecording
  def self.verify(path, bytes)
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, bytes)
    else
      raise "#{path} differs from Rails" unless File.binread(path) == bytes.b
    end
  end
end
