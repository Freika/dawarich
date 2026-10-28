# frozen_string_literal: true

class TagsController < ApplicationController
  PER_PAGE = 20

  before_action :authenticate_user!
  before_action :set_tag, only: %i[show edit update destroy add_place remove_place]

  def index
    @tags = policy_scope(Tag).ordered.page(params[:page]).per(PER_PAGE)
    @place_counts = current_user.places.joins(:taggings).where(taggings: { tag_id: @tags.map(&:id) })
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
      redirect_to tag_path(@tag), notice: I18n.t('controllers.tags.tag_was_successfully_created')
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    authorize @tag
    prepare_list
  end

  def edit
    authorize @tag

    if params[:confirm_delete] == '1' && @tag.privacy_zone?
      @place_count = tag_places.count
      @shared_link_count = current_user.shared_links.active.count
      render :confirm_delete
    else
      prepare_list
      render :show
    end
  end

  def update
    authorize @tag

    if @tag.update(tag_params)
      @tag.adopt!
      redirect_to tag_path(@tag), notice: I18n.t('controllers.tags.tag_was_successfully_updated')
    else
      prepare_list
      render :show, status: :unprocessable_entity
    end
  end

  def add_place
    authorize @tag, :update?
    place = current_user.places.find(params[:place_id])
    place.add_tag(@tag)
    place.adopt!
    @tag.adopt!

    redirect_to tag_path(@tag, q: params[:q].presence),
                notice: I18n.t('tags.list.added', name: place.name)
  end

  def remove_place
    authorize @tag, :update?
    place = current_user.places.find(params[:place_id])
    place.remove_tag(@tag)

    redirect_to tag_path(@tag), notice: I18n.t('tags.list.removed', name: place.name)
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

  def prepare_list
    load_tag_places
    @place_query = params[:q].to_s.strip
    @place_candidates = place_candidates
  end

  def place_candidates
    return Place.none if @place_query.blank?

    current_user.places
                .where.not(id: @places.select(:id))
                .where('places.name ILIKE ?', "%#{Place.sanitize_sql_like(@place_query)}%")
                .order(:name)
                .limit(8)
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
