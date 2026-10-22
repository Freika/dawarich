# frozen_string_literal: true

class FamiliesController < ApplicationController
  before_action :authenticate_user!
  # #new doubles as the landing page for users without the plan: it renders the
  # upgrade CTA instead of the create form, so it must stay reachable. #destroy
  # stays open so a lapsed owner can still dissolve the family.
  before_action :ensure_family_feature_available!, except: %i[new destroy]
  before_action :set_family, only: %i[show edit update destroy]

  def show
    authorize @family

    @members = @family.members.includes(:family_membership).order(:email)
    @pending_invitations = @family.active_invitations.order(:created_at)

    @member_count = @family.member_count
    @can_invite = @family.can_add_members?
    @pending_requests = current_user.sent_location_requests.pending
                                    .where('expires_at > ?', Time.current)
                                    .index_by(&:target_user_id)

    @member_locations = @members.filter_map(&:latest_location_for_family)
  end

  def new
    # Members of a lapsed family fall through to the lapsed panel: sending them
    # to #show would bounce them straight back here in a redirect loop.
    redirect_to family_path and return if current_user.in_family? && family_feature_available?

    if current_user.in_family?
      @family = current_user.family

      if current_user.family_owner?
        @members = @family.members.includes(:family_membership).order(:email)
        @family_upgrade_url = helpers.family_upgrade_url(utm_medium: 'family', utm_content: 'renew_family')
      end

      render :lapsed and return
    end

    @family = Family.new
    @can_create_family = FamilyPolicy.new(current_user, @family).create?
    return if @can_create_family

    @family_upgrade_url = helpers.family_upgrade_url(utm_medium: 'family', utm_content: 'create_family')
  end

  def create
    @family = Family.new(family_params)
    authorize @family

    service = Families::Create.new(
      user: current_user,
      name: family_params[:name]
    )

    if service.call
      redirect_to family_path, notice: I18n.t('controllers.families.family_created_successfully')
    else
      @family = Family.new(family_params)

      if service.errors.any?
        service.errors.each do |error|
          @family.errors.add(error.attribute, error.message)
        end
      end

      @family.errors.add(:base, service.error_message) if service.error_message.present?

      flash.now[:alert] = service.error_message || I18n.t('controllers.families.failed_to_create_family')
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @family
  end

  def update
    authorize @family

    if @family.update(family_params)
      redirect_to family_path, notice: I18n.t('controllers.families.family_updated_successfully')
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @family

    if @family.members.count > 1
      redirect_to family_home_path,
                  alert: I18n.t('controllers.families.cannot_delete_family_with_members_remove_all_members_first')
    else
      @family.destroy
      redirect_to new_family_path, notice: I18n.t('controllers.families.family_deleted_successfully')
    end
  end

  private

  def set_family
    @family = current_user.family
    redirect_to new_family_path, alert: I18n.t('controllers.families.you_are_not_in_a_family') unless @family
  end

  def family_params
    params.require(:family).permit(:name)
  end
end
