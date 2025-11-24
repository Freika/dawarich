# frozen_string_literal: true

class TagsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_tag, only: [:edit, :update, :destroy]

  def index
    @tags = policy_scope(Tag).ordered

    authorize Tag
  end

  def new
    @tag = current_user.tags.build

    authorize @tag
  end

  def create
    @tag = current_user.tags.build(tag_params)

    authorize @tag

    if @tag.save
      redirect_to tags_path, notice: 'Tag was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @tag
  end

  def update
    authorize @tag

    if @tag.update(tag_params)
      redirect_to tags_path, notice: 'Tag was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @tag

    @tag.destroy!

    redirect_to tags_path, notice: 'Tag was successfully deleted.', status: :see_other
  end

  private

  def set_tag
    @tag = current_user.tags.find(params[:id])
  end

  def tag_params
    params.require(:tag).permit(:name, :icon, :color, :privacy_radius_meters)
  end
end
