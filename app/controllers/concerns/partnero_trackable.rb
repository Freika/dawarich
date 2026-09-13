# frozen_string_literal: true

# Carries a Partnero affiliate key from a referral link through to the account it
# creates.
#
# PartneroJS scopes its cookie to the host that set it, so a key captured on
# dawarich.app never reaches this app. The marketing site forwards it as a query
# param instead (see site/src/utils/utm.js); this concern parks that key in the
# session until a signup actually happens, on whichever page the visitor lands.
module PartneroTrackable
  extend ActiveSupport::Concern

  # Partnero's referral param is configured per program — their docs describe
  # `via`, the snippet generated for this program emits `aff`. Both are read so
  # a dashboard setting cannot silently cost every commission; `aff` wins because
  # that is what the program's own snippet writes.
  REFERRAL_PARAMS = %i[aff via].freeze
  MAX_KEY_LENGTH = 255

  included do
    before_action :store_partnero_referral, unless: -> { DawarichSettings.self_hosted? }
  end

  def store_partnero_referral
    key = REFERRAL_PARAMS.filter_map { |param| params[param].presence }.first
    return if key.blank?

    # truncate, not byteslice: cutting a multi-byte character in half yields a
    # string the JSON cookie serializer refuses, which would 500 the page.
    session[:partnero_referral] = key.to_s.truncate(MAX_KEY_LENGTH, omission: '')
  end

  # Spends the referral: a key credits exactly one account, so it is deleted from
  # the session whether or not the enqueue happens.
  def attribute_partnero_signup(user)
    partner_key = session.delete(:partnero_referral)
    return if partner_key.blank? || user.nil?

    Partnero::CustomerSignupJob.perform_later(user.id, partner_key)
  end
end
