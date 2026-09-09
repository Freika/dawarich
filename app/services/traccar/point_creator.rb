# frozen_string_literal: true

class Traccar::PointCreator
  attr_reader :params, :user_id

  def initialize(params, user_id)
    @params = params
    @user_id = user_id
  end

  def call
    parsed_params = Traccar::Params.new(params).call
    return [] if parsed_params.blank?

    Points::Intake.call(user_id: user_id, payloads: [parsed_params])
  end
end
