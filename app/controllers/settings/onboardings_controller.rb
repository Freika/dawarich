# frozen_string_literal: true

module Settings
  class OnboardingsController < ApplicationController
    before_action :authenticate_user!

    def update
      current_user.settings['onboarding_completed'] = true
      current_user.save!
      head :ok
    end
  end
end
