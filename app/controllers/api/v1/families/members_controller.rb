# frozen_string_literal: true

class Api::V1::Families::MembersController < Api::V1::Families::BaseController
  include Api::FamilyErrorRendering

  # Leaving and removing stay open after the family plan lapses, as on the web.
  skip_before_action :ensure_family_feature_available!

  # Deleting your own id leaves the family; the owner deleting another id
  # removes that member. A user outside the caller's family reads as missing.
  def destroy
    target = current_api_user.family.members.find_by(id: params[:user_id])
    return render_family_error(:member_not_found) unless target

    service = Families::Memberships::Destroy.new(user: current_api_user, member_to_remove: target)
    return render_family_service_error(service) unless service.call

    head :no_content
  end
end
