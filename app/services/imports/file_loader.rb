# frozen_string_literal: true

module Imports
  module FileLoader
    extend ActiveSupport::Concern

    private

    def load_json_data
      if file_path && File.exist?(file_path)
        Oj.load_file(file_path, mode: :compat)
      else
        file_content = Imports::SecureFileDownloader.new(import.file).download_with_verification
        Oj.load(file_content, mode: :compat)
      end
    end

    def load_file_content
      if file_path && File.exist?(file_path)
        File.read(file_path)
      else
        Imports::SecureFileDownloader.new(import.file).download_with_verification
      end
    end
  end
end
