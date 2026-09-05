# frozen_string_literal: true

class Points::Create
  attr_reader :user, :params

  def initialize(user, params)
    @user = user
    @params = params.to_h
  end

  def call
    Points::Intake.call(user_id: user.id, payloads: Points::Params.new(params, user.id).call)
  end
end
