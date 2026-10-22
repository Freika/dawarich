# frozen_string_literal: true

class Exports::LegacyFilePath
  def initialize(url)
    @url = url
  end

  def call
    return if @url.blank? || @url.include?('\\')

    uri = URI.parse(@url)
    return if uri.scheme || uri.host || uri.query || uri.fragment

    segments = uri.path.split('/').reject(&:empty?)
    return if segments.empty? || segments.any? { |segment| %w[. ..].include?(segment) }

    path = Rails.public_path
    return if path.symlink?

    unsafe = segments.any? do |segment|
      path = path.join(segment)
      path.symlink?
    end
    return if unsafe

    path if path.file?
  rescue URI::InvalidURIError, ArgumentError
    nil
  end
end
