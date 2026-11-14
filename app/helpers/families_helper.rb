# frozen_string_literal: true

module FamiliesHelper
  # Opens the invitation in the mobile app. Built only from server-side values;
  # the app compares `server` with the server it is connected to and never sends
  # requests to it.
  def mobile_invitation_url(invitation)
    "dawarich://invite?#{{ server: request.base_url, token: invitation.token }.to_query}"
  end
end
