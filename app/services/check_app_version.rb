# frozen_string_literal: true

class CheckAppVersion
  def initialize
    @repo_url = 'https://api.github.com/repos/Freika/dawarich/tags'
    @app_version = File.read('.app_version').strip
  end

  def call
    latest_version = JSON.parse(Net::HTTP.get(URI.parse(@repo_url)))[0]['name']
    latest_version == @app_version
  end
end
