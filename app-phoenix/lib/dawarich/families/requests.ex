defmodule Dawarich.Families.Requests do
  @moduledoc false

  alias Dawarich.{I18n, Notifications, RailsTime, Repo}
  alias Dawarich.Families.{Clock, Locations, Sharing, SharingUpdate}
  alias Dawarich.Mail.ExploreFeatures
  alias Dawarich.Mail.ResidualCommands
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @max_id 9_223_372_036_854_775_807
  @cooldown_seconds 3600
  @lifetime_seconds 86_400

  def create(user, params, now) do
    case Locations.membership(user.id) do
      [_settings, nil] ->
        {:ok, 404, Locations.not_in_family()}

      [_settings, family_id] ->
        RailsTime.with_zone(user.timezone, fn ->
          create(user, family_id, target_id(params), now)
        end)
    end
  end

  def respond(user, decision, params, now) do
    case Locations.membership(user.id) do
      [_settings, nil] ->
        {:ok, 404, Locations.not_in_family()}

      [_settings, family_id] ->
        id = String.to_integer(params["id"])

        RailsTime.with_zone(user.timezone, fn ->
          respond(user.id, family_id, id, decision, params, now)
        end)
    end
  end

  defp create(_user, _family_id, nil, _now), do: not_found()

  defp create(user, family_id, target_id, now) do
    if target_id == user.id, do: raise(ArgumentError, "a request for one's own location")

    case Repo.query!(
           "SELECT u.id, u.email, u.settings FROM users u " <>
             "INNER JOIN family_memberships m ON u.id = m.user_id " <>
             "WHERE u.deleted_at IS NULL AND m.family_id = $1 AND u.id = $2 LIMIT 1",
           [family_id, target_id]
         ).rows do
      [] ->
        not_found()

      [[id, email, settings]] ->
        cond do
          Sharing.enabled?(settings, now) ->
            failure(422, "target_user_is_already_sharing_their_location")

          cooldown?(user.id, id, now) ->
            failure(429, "request_cooldown_active_please_wait_before_requesting_again")

          true ->
            insert(user, family_id, %{id: id, email: email, settings: settings}, now)
        end
    end
  end

  defp insert(user, family_id, target, now) do
    at = Clock.naive(now)
    expires = NaiveDateTime.add(at, @lifetime_seconds)

    [[id]] =
      Repo.query!(
        "INSERT INTO family_location_requests (requester_id, target_user_id, family_id, status, " <>
          "suggested_duration, expires_at, created_at, updated_at) " <>
          "VALUES ($1, $2, $3, 0, '24h', $4, $5, $5) RETURNING id",
        [user.id, target.id, family_id, expires, at]
      ).rows

    [[email]] = Repo.query!("SELECT email FROM users WHERE id = $1", [user.id]).rows
    notify(email, target, id, at)

    ResidualCommands.location(Repo, %{
      "user_id" => user.id,
      "request_id" => id
    })

    {:ok, 201,
     {:object,
      [
        {"request",
         {:object,
          [{"id", id}, {"target_user_id", target.id}, {"expires_at", Clock.iso(expires)}]}}
      ]}}
  end

  defp notify(requester_email, target, id, at) do
    locale = ExploreFeatures.locale(target.settings, "en")
    href = "/family/location_requests/#{id}"

    link =
      ~s(<a class="link link-primary" href="#{href}">#{ExploreFeatures.h(t(locale, "view_request"))}</a>)

    bindings = %{"email" => ExploreFeatures.h(requester_email), "link" => link}
    content = t(locale, "safe_email_is_requesting_your_location_link", bindings)
    Notifications.create!(Repo, target.id, :info, t(locale, "location_request"), content, at)
  end

  defp respond(user_id, family_id, id, decision, params, now) do
    case Repo.query!(
           "SELECT target_user_id FROM family_location_requests WHERE family_id = $1 AND id = $2",
           [family_id, id]
         ).rows do
      [] ->
        {:ok, 404,
         {:object,
          [{"error", I18n.en!("controllers.api.v1.families.location_requests.not_found")}]}}

      [[target]] when target != user_id ->
        response_failure(403, "not_authorized")

      [[_target]] ->
        locked(user_id, id, decision, params, now)
    end
  end

  defp locked(user_id, id, decision, params, now) do
    [[status, expires, suggested]] =
      Repo.query!(
        "SELECT status, expires_at, suggested_duration FROM family_location_requests WHERE id = $1 FOR UPDATE",
        [id]
      ).rows

    at = Clock.naive(now)

    if status == 0 and NaiveDateTime.compare(expires, at) == :gt do
      if decision == :accept, do: SharingUpdate.enable!(user_id, duration(params, suggested), now)
      code = if decision == :accept, do: 1, else: 2

      Repo.query!(
        "UPDATE family_location_requests SET status = $1, responded_at = $2, updated_at = $2 WHERE id = $3",
        [code, at, id]
      )

      {:ok, 200,
       {:object, [{"success", true}, {"status", if(code == 1, do: "accepted", else: "declined")}]}}
    else
      response_failure(422, "no_longer_actionable")
    end
  end

  defp duration(params, suggested) do
    case params["duration"] do
      value when is_binary(value) or is_nil(value) ->
        if Ruby.blank?(value), do: suggested, else: value

      _other ->
        raise ArgumentError, "duration parameter shape"
    end
  end

  defp target_id(params) do
    case params["target_user_id"] do
      nil ->
        nil

      id when is_integer(id) and id >= -@max_id - 1 and id <= @max_id ->
        id

      id when is_binary(id) ->
        if id =~ ~r/\A\d{1,18}\z/,
          do: String.to_integer(id),
          else: raise(ArgumentError, "target id shape")

      _other ->
        raise ArgumentError, "target id shape"
    end
  end

  defp cooldown?(requester, target, now) do
    since = NaiveDateTime.add(Clock.naive(now), -@cooldown_seconds)

    Repo.query!(
      "SELECT EXISTS (SELECT 1 FROM family_location_requests WHERE requester_id = $1 " <>
        "AND target_user_id = $2 AND status = 0 AND created_at > $3)",
      [requester, target, since]
    ).rows == [[true]]
  end

  defp not_found,
    do:
      {:ok, 404,
       {:object,
        [
          {"error",
           I18n.en!("controllers.family.location_requests.user_not_found_in_your_family")}
        ]}}

  defp failure(status, key),
    do:
      {:ok, status,
       {:object, [{"message", I18n.en!("services.families.create_location_request." <> key)}]}}

  defp response_failure(status, key),
    do:
      {:ok, status,
       {:object, [{"message", I18n.en!("services.families.respond_to_location_request." <> key)}]}}

  defp t(locale, key, bindings \\ %{}) do
    {:ok, text} = I18n.t(locale, "services.families.create_location_request." <> key, bindings)
    text
  end
end
