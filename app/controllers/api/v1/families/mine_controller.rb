# frozen_string_literal: true

class Api::V1::Families::MineController < Api::V1::Families::BaseController
  def show
    render json: Api::FamilySerializer.new(current_api_user).call
  end
end
