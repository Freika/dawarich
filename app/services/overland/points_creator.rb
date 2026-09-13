# frozen_string_literal: true

class Overland::PointsCreator
  attr_reader :params, :user_id

  def initialize(params, user_id)
    @params = params
    @user_id = user_id
  end

  def call
    parsed_params = Overland::Params.new(params).call
    return [] if parsed_params.blank?

    Points::Intake.call(user_id: user_id, payloads: parsed_params)
  end
end
