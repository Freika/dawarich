# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  include UtmTrackable
  include PendingImportClaimable
  include AccountDeletionConfirmable

  prepend_before_action :handle_logged_in_with_ticket, only: :new
  before_action :set_invitation, only: %i[new create]
  before_action :check_registration_allowed, only: %i[new create]
  before_action :store_utm_params, only: %i[new], unless: -> { DawarichSettings.self_hosted? }
  before_action :store_gads_linker, only: %i[new], unless: -> { DawarichSettings.self_hosted? }

  def new
    session[:pending_import_ticket] = params[:import_ticket] if params[:import_ticket].present?

    build_resource({})

    resource.email = @invitation.email if @invitation

    yield resource if block_given?

    respond_with resource
  end

  def create
    build_resource(sign_up_params)
    resource.save
    yield resource if block_given?

    if resource.persisted?
      persist_signup_locale(resource)
      post_signup_setup(resource)

      # The claim happens in every branch (not in after_sign_up_path_for):
      # the reverse-trial redirect below never consults the sign-up path, and
      # the ticket must not outlive the signup that owns it. It runs after
      # each flash decision so the "Importing..." notice isn't overwritten.
      if @signup_variant == 'reverse_trial'
        resource.update!(status: :pending_payment)
        claim_pending_import_for(resource)
        redirect_to manager_checkout_url(resource), allow_other_host: true
      elsif resource.active_for_authentication?
        set_flash_message!(:notice, :signed_up)
        sign_up(resource_name, resource)
        claim_pending_import_for(resource)
        respond_with(resource, location: after_sign_up_path_for(resource))
      else
        set_flash_message!(:notice, :"signed_up_but_#{resource.inactive_message}")
        expire_data_after_sign_in!
        claim_pending_import_for(resource)
        respond_with(resource, location: after_inactive_sign_up_path_for(resource))
      end
    else
      clean_up_passwords(resource)
      set_minimum_password_length
      respond_with(resource)
    end
  end

  def destroy
    unless resource.can_delete_account?
      set_flash_message! :alert, :cannot_delete
      redirect_to edit_user_registration_path
      return
    end

    DawarichSettings.self_hosted? ? destroy_self_hosted : destroy_cloud
  end

  protected

  def destroy_self_hosted
    unless account_deletion_confirmed?(resource)
      log_failed_account_deletion(resource)
      redirect_to edit_user_registration_path, alert: account_deletion_confirmation_error(resource)
      return
    end

    Users::DestroyJob.perform_later(resource.id) if resource.mark_as_deleted_atomically!

    Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)

    redirect_to after_sign_out_path_for(resource_name),
                notice: I18n.t('controllers.users.registrations.your_account_has_been_scheduled_for_deletion')
  end

  def destroy_cloud
    result = Users::RequestAccountDestroy.new(
      resource,
      host: default_mailer_host,
      protocol: default_mailer_protocol
    ).call

    flash_key = result.status == :sent ? :notice : :alert
    redirect_to edit_user_registration_path, flash_key => result.message
  end

  def build_resource(hash = nil)
    super
    return if resource.email.to_s.strip.empty?

    @signup_variant = Signup::BucketVariant.new(resource).call
    resource.signup_variant = @signup_variant
    resource.skip_auto_trial = true if @signup_variant == 'reverse_trial'
  end

  def update_resource(resource, params)
    return super unless resource.oauth_user?

    if params[:password].present?
      resource.update(params.except(:current_password))
    else
      resource.update_without_password(params)
    end
  end

  def after_sign_up_path_for(resource)
    return family_path if @invitation&.family

    super(resource)
  end

  def after_inactive_sign_up_path_for(resource)
    return family_path if @invitation&.family

    super(resource)
  end

  private

  def handle_logged_in_with_ticket
    return unless user_signed_in? && params[:import_ticket].present?

    session[:pending_import_ticket] = params[:import_ticket]
    claim_pending_import_for(current_user)

    redirect_to imports_path
  end

  def post_signup_setup(resource)
    assign_utm_params(resource)
    store_signup_intent(resource)
    accept_invitation_for_user(resource) if @invitation
  end

  # Only a language the reader actually picked is worth pinning to the account.
  # Recording the default here would answer `suggested_locale`'s "has the reader
  # chosen?" question for every new account, so someone signing up from a French
  # browser would never be offered French again.
  def persist_signup_locale(resource)
    return if supported_locale(params[:locale]).nil? && session[:locale].blank?

    resource.settings = (resource.settings || {}).merge('locale' => I18n.locale.to_s)
    resource.save!
  end

  def manager_checkout_url(user)
    url = "#{MANAGER_URL}/checkout?token=#{user.generate_subscription_token(variant: 'reverse_trial')}"
    linker = session.delete(:gads_linker)
    url += "&_gl=#{CGI.escape(linker)}" if linker.present?
    url
  end

  def store_gads_linker
    return if params[:_gl].blank?

    session[:gads_linker] = params[:_gl].to_s.byteslice(0, 1024)
  end

  def default_mailer_host
    ActionMailer::Base.default_url_options[:host] || request.host
  end

  def default_mailer_protocol
    ActionMailer::Base.default_url_options[:protocol] || (request.ssl? ? 'https' : 'http')
  end

  def check_registration_allowed
    return unless self_hosted_mode?

    # When OIDC is enabled and email/password registration is disabled,
    # block all email/password registration including family invitations
    if oidc_only_mode?
      alert = I18n.t('controllers.users.registrations.email_password_registration_is_disabled_please_use_oidc_to_sign')
      redirect_to root_path,
                  alert: alert
      return
    end

    return if valid_invitation_token?
    return if email_password_registration_allowed?

    alert = I18n.t(
      'controllers.users.registrations.registration_is_not_available_please_contact_your_administrator_for_acce'
    )
    redirect_to root_path, alert: alert
  end

  def set_invitation
    return if invitation_token.blank?

    @invitation = Family::Invitation.find_by(token: invitation_token)
  end

  def self_hosted_mode?
    DawarichSettings.self_hosted?
  end

  def valid_invitation_token?
    @invitation&.can_be_accepted?
  end

  def invitation_token
    @invitation_token ||= params[:invitation_token] ||
                          params.dig(:user, :invitation_token) ||
                          session[:invitation_token]
  end

  def accept_invitation_for_user(user)
    return unless @invitation&.can_be_accepted?

    service = Families::AcceptInvitation.new(
      invitation: @invitation,
      user: user
    )

    if service.call
      flash[:notice] =
        I18n.t('controllers.users.registrations.welcome_to_name_you_re_now_part_of_the_family',
               name: @invitation.family.name)
    else
      flash[:alert] =
        I18n.t('controllers.users.registrations.account_created_successfully_but_there_was_an_issue_accepting_the',
               error_message: service.error_message)
    end
  rescue StandardError => e
    Rails.logger.error "Error accepting invitation during registration: #{e.message}"
    flash[:alert] =
      I18n.t('controllers.users.registrations.account_created_successfully_but_there_was_an_issue_accepting_the_2')
  end

  def sign_up_params
    super
  end

  def store_signup_intent(user)
    return if DawarichSettings.self_hosted?

    intent = params.dig(:user, :signup_intent)
    return unless intent.in?(%w[cloud self_hosted_demo])

    user.update_columns(
      settings: user.settings.merge('signup_intent' => intent)
    )
  end

  def email_password_registration_allowed?
    DawarichSettings.registration_enabled?
  end

  def oidc_only_mode?
    DawarichSettings.oidc_enabled? && !email_password_registration_allowed?
  end
end
