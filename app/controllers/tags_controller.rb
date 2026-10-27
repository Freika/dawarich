# frozen_string_literal: true

class TagsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_tag, only: %i[edit update destroy]

  def index
    @tags = policy_scope(Tag).ordered
    @place_counts = current_user.places.joins(:taggings).where(taggings: { tag_id: @tags.select(:id) })
                                .group('taggings.tag_id').count

    authorize Tag
  end

  def new
    @tag = current_user.tags.build

    authorize @tag
  end

  def create
    @tag = current_user.tags.build(inline_context ? inline_tag_params : tag_params)

    authorize @tag

    if inline_context
      render_inline_tag
    elsif @tag.save
      redirect_to tags_path, notice: I18n.t('controllers.tags.tag_was_successfully_created')
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @tag

    if params[:confirm_delete] == '1' && @tag.privacy_zone?
      @place_count = tag_places.count
      @shared_link_count = current_user.shared_links.active.count
      render :confirm_delete
    else
      load_tag_places
    end
  end

  def update
    authorize @tag

    if @tag.update(tag_params)
      @tag.adopt!
      redirect_to tags_path, notice: I18n.t('controllers.tags.tag_was_successfully_updated')
    else
      load_tag_places
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @tag

    @tag.destroy!

    redirect_to tags_path, notice: I18n.t('controllers.tags.tag_was_successfully_deleted'), status: :see_other
  end

  private

  def tag_places
    @tag.places.where(user: current_user).order(:name)
  end

  def load_tag_places
    @places = tag_places
    @visit_counts = current_user.visits.active.where(place: @places).group(:place_id).count
  end

  def inline_context
    params[:inline].presence_in(%w[editor creation])
  end

  def inline_tag_params
    params.require(:tag).permit(:name, :icon).merge(color: '#6ab0a4')
  end

  def render_inline_tag
    if @tag.save
      streams = %w[editor creation].map do |surface|
        turbo_stream.append("#{surface}-place-tags", partial: 'shared/place_tag',
                            locals: { tag: @tag, checked: surface == inline_context, surface: })
      end
      streams << turbo_stream.update("#{inline_context}-tag-errors", '')
      render turbo_stream: streams
    else
      render turbo_stream: turbo_stream.update("#{inline_context}-tag-errors", @tag.errors.full_messages.join(', ')),
             status: :unprocessable_content
    end
  end

  def set_tag
    @tag = current_user.tags.find(params[:id])
  end

  def tag_params
    params.require(:tag).permit(:name, :icon, :color, :privacy_radius_meters)
  end
end
