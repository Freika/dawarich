# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Achievement return URL safety', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  %w[javascript data vbscript file].each do |scheme|
    it "uses the achievement fallback for a same-host #{scheme} referer" do
      patch toggle_sharing_achievement_path('country_de'),
            headers: { 'HTTP_REFERER' => "#{scheme}://www.example.com/unsafe" }

      expect(response).to redirect_to(achievement_path('country_de'))
      expect(user.achievement_progresses.find_by!(achievement_key: 'country_de').sharing_enabled).to be true
    end
  end

  ['http://www.example.com/achievements', 'https://www.example.com/achievements', '/achievements'].each do |url|
    it "retains the safe return target #{url}" do
      patch toggle_sharing_achievement_path('country_de'), headers: { 'HTTP_REFERER' => url }

      expect(response).to redirect_to(url)
    end
  end

  ['//outside.example/achievements', 'https://outside.example/achievements', 'http://[invalid'].each do |url|
    it "uses the fallback for #{url}" do
      patch toggle_sharing_achievement_path('country_de'), headers: { 'HTTP_REFERER' => url }

      expect(response).to redirect_to(achievement_path('country_de'))
    end
  end
end
