# frozen_string_literal: true

class Api::V1::DemoDataController < ApiController
  before_action :authenticate_active_api_user!

  def show
    render json: { exists: current_api_user.imports.exists?(demo: true) }
  end

  def create
    result = DemoData::Importer.new(current_api_user).call

    case result[:status]
    when :created
      render json: { status: 'created' }, status: :created
    when :exists
      render json: { status: 'exists' }, status: :ok
    else
      render json: { status: 'error' }, status: :unprocessable_content
    end
  end

  def destroy
    result = DemoData::Destroyer.new(current_api_user).call

    case result[:status]
    when :destroyed
      render json: { status: 'destroyed' }, status: :ok
    when :no_demo_data
      render json: { status: 'no_demo_data' }, status: :ok
    else
      render json: { status: 'error' }, status: :unprocessable_content
    end
  end
end
