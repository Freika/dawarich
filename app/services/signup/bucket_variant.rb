# frozen_string_literal: true

require 'digest'

module Signup
  # Decides which signup flow variant (legacy_trial / reverse_trial) a user
  # belongs to.
  #
  # Self-hosted installations always receive `legacy_trial` regardless of the
  # Flipper flag — the pending-payment experiment is a Dawarich Cloud concern.
  #
  # For cloud signups, bucketing is delegated to Flipper's feature gates on the
  # `reverse_trial_signup` flag. The user may not yet be persisted at bucketing
  # time (we need the variant before `resource.save` in the registrations
  # controller to gate `skip_auto_trial`), so unpersisted users are wrapped in
  # a StableActor whose `flipper_id` is a SHA-256 hash of their downcased
  # email. This keeps `percentage_of_actors` gating deterministic even before
  # the User record has an `id`.
  class BucketVariant
    # Wraps a stable string identifier (derived from the user's email) so
    # Flipper's percentage-of-actors gate can bucket the user deterministically
    # before a database id exists.
    StableActor = Struct.new(:flipper_id)

    def initialize(user)
      @user = user
    end

    def call
      return 'legacy_trial' if DawarichSettings.self_hosted?

      raise ArgumentError, 'user is required' if @user.nil?

      email = @user.email.to_s.strip
      raise ArgumentError, 'user email must be present for bucketing' if email.empty?

      return 'reverse_trial' if flipper_enabled?(email)

      'legacy_trial'
    end

    private

    # Wrap the Flipper check so a transient adapter failure (DB hiccup, Redis
    # outage, network blip) cannot 500 the signup endpoint. Falling back to
    # `legacy_trial` keeps signups functional; bucketing is the degraded arm,
    # not the user-visible flow.
    #
    # Surface the underlying exception to ExceptionReporter so on-call gets
    # paged on the actual outage instead of finding it via a reverse-trial
    # KPI dip a week later. The signup itself still succeeds.
    def flipper_enabled?(email)
      Flipper.enabled?(:reverse_trial_signup, actor_for(@user, email))
    rescue StandardError => e
      Rails.logger.warn(
        "[Signup::BucketVariant] Flipper unavailable, falling back to legacy_trial: #{e.class}: #{e.message}"
      )
      ExceptionReporter.call(e, '[Signup::BucketVariant] Flipper unavailable, falling back to legacy_trial')
      false
    end

    # Return the user directly when Flipper can derive a stable `flipper_id`
    # from a persisted primary key; otherwise wrap the user in a StableActor
    # keyed off the downcased email hash.
    #
    # The two flipper_ids ("User;email-<sha>" pre-save and "User;<id>" post-save)
    # are different actors, so a percentage_of_actors gate would technically
    # bucket the same user differently across the save boundary. In practice
    # we bucket exactly once during registration and persist the result on
    # User#signup_variant — we never re-bucket the same user, so the discrepancy
    # never materialises. Don't reuse this helper outside the registration path.
    def actor_for(user, email)
      return user if user.respond_to?(:id) && !user.id.nil?

      StableActor.new(stable_key(email))
    end

    def stable_key(email)
      "User;email-#{Digest::SHA256.hexdigest(email.downcase)}"
    end
  end
end
