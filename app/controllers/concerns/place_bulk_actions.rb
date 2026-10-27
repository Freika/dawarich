# frozen_string_literal: true

module PlaceBulkActions
  private

  def perform_place_bulk_action(operation)
    count = Places::BulkAction.new(user: current_user, place_ids: params[:place_ids]).call(
      operation:, tag_id: params[:tag_id], survivor_id: params[:survivor_id]
    )
    redirect_to places_url(place_list_params), notice: I18n.t('places.management.bulk_success', count:),
                                             status: :see_other
  rescue Places::BulkAction::InvalidSelection
    redirect_to places_url(place_list_params), alert: I18n.t('places.management.invalid_selection'), status: :see_other
  rescue Places::Merge::VisitConflict => e
    conflict = e.conflicts.first
    message = I18n.t('controllers.places.merge_visit_conflict', first_id: conflict[:survivor_id],
                    second_id: conflict[:duplicate_id], started_at: I18n.l(conflict[:started_at], format: :long))
    redirect_to places_url(place_list_params), alert: message, status: :see_other
  end

  def place_list_params
    params.permit(:q, :sort, :filter, :view, :page, :locale, tag_ids: []).to_h
  end
end
