# frozen_string_literal: true

class Settings::SubscriptionsController < ApplicationController
  before_action :authenticate_user!

  def index; end
end
