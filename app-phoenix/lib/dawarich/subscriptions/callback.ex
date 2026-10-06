defmodule Dawarich.Subscriptions.Callback do
  @moduledoc false
  import Ecto.Query
  require Logger
  alias Dawarich.Auth.Account
  alias Dawarich.Subscriptions.Cache
  alias Dawarich.Repo
  @statuses %{"inactive" => 0, "active" => 1, "trial" => 2, "pending_payment" => 3}
  @plans %{"lite" => 0, "pro" => 1, "family" => 2}
  @sources %{"none" => 0, "paddle" => 1, "apple_iap" => 2, "google_play" => 3}

  def call(token, provided, context) do
    env = Map.get_lazy(context, :env, &System.get_env/0)
    secret = env["SUBSCRIPTION_WEBHOOK_SECRET"]

    cond do
      secret in [nil, ""] ->
        response(503, "configuration_error")

      not is_binary(provided) or not Plug.Crypto.secure_compare(secret, provided) ->
        response(401, "invalid_webhook_secret")

      true ->
        case decode(token, context) do
          {:ok, claims} -> apply_event(claims, context)
          _ -> response(401, "failed_to_verify_subscription_update")
        end
    end
  end

  def decode(token, context) do
    env = Map.get_lazy(context, :env, &System.get_env/0)
    now = Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_unix()

    with secret when is_binary(secret) and secret != "" <- env["JWT_SECRET_KEY"],
         true <- is_binary(token) and byte_size(token) <= 16384,
         [header, payload, signed] <- String.split(token, "."),
         {:ok, %{"alg" => "HS256"}} <- Dawarich.Auth.Providers.Jwks.decode(header),
         {:ok, signature} <- Base.url_decode64(signed, padding: false),
         true <-
           Plug.Crypto.secure_compare(
             signature,
             :crypto.mac(:hmac, :sha256, secret, header <> "." <> payload)
           ),
         {:ok, claims} when is_map(claims) <- Dawarich.Auth.Providers.Jwks.decode(payload),
         true <- is_number(claims["exp"]) and claims["exp"] > now,
         true <- is_nil(claims["nbf"]) or (is_number(claims["nbf"]) and claims["nbf"] <= now) do
      {:ok, claims}
    else
      _ -> {:error, :token}
    end
  end

  defp apply_event(claims, context) do
    cond do
      claims["event_id"] in [nil, "", false] ->
        response(422, "missing_event_id")

      not Cache.claim(claims["event_id"], context) ->
        response(200, "stale_event")

      Cache.older?(claims, context) ->
        Cache.release(claims["event_id"], context)
        response(200, "stale_event")

      true ->
        persist(claims, context)
    end
  end

  defp persist(claims, context) do
    repo = Map.get(context, :repo, Repo)

    case repo.one(eligible(claims["user_id"]), log: false) do
      nil ->
        {:error, 404, %{"error" => "unknown_dawarich_user_id", "user_id" => claims["user_id"]}}

      _ ->
        transaction(repo, claims, context)
    end
  end

  defp eligible(id), do: from(u in Account, where: u.id == ^id and is_nil(u.deleted_at))

  defp transaction(repo, claims, context) do
    result =
      try do
        repo.transaction(fn ->
          user =
            repo.one(from(u in eligible(claims["user_id"]), lock: "FOR UPDATE"),
              log: false
            )

          if is_nil(user), do: repo.rollback(:unknown_user)

          if Cache.older?(claims, context) do
            Cache.release(claims["event_id"], context)
            repo.rollback(:stale)
          end

          if is_function(context[:before_update], 0), do: context.before_update.()
          attrs = attrs(claims)
          changes = Ecto.Changeset.change(user, attrs)

          changes =
            if map_size(changes.changes) > 0,
              do:
                Ecto.Changeset.put_change(
                  changes,
                  :updated_at,
                  Map.get(context, :clock, &DateTime.utc_now/0).()
                ),
              else: changes

          user = repo.update!(changes, log: false)

          if Map.has_key?(changes.changes, :plan) do
            Cache.invalidate(user.api_key, context)

            repo.query!(
              "UPDATE users SET settings=COALESCE(settings,'{}'::jsonb)-'archival_warnings'-'lite_since' WHERE id=$1",
              [user.id],
              log: false
            )
          end

          Cache.advance(claims, context)
          {user, changes.changes}
        end)
      rescue
        error ->
          Cache.release(claims["event_id"], context)
          reraise error, __STACKTRACE__
      end

    case result do
      {:error, :unknown_user} ->
        {:error, 404, %{"error" => "unknown_dawarich_user_id", "user_id" => claims["user_id"]}}

      {:error, :stale} ->
        response(200, "stale_event")

      {:ok, {user, changes}} ->
        if map_size(changes) > 0, do: Cache.invalidate(user.api_key, context)
        callbacks(repo, user, changes, context)
        committed_response(context)
    end
  rescue
    _ in [ArgumentError, Ecto.CastError] -> response(422, "invalid_subscription_data_received")
  end

  defp committed_response(context) do
    if is_function(context[:after_commit], 0), do: context.after_commit.()
    response(200, "subscription_updated_successfully")
  rescue
    _ -> {:error, 503, %{"error" => "subscription_response_unavailable"}}
  end

  defp attrs(claims) do
    attrs = %{
      status: enum(claims["status"], @statuses),
      active_until: date(claims["active_until"])
    }

    attrs =
      if claims["plan"] in Map.keys(@plans),
        do: Map.put(attrs, :plan, @plans[claims["plan"]]),
        else: attrs

    if claims["plan"] not in [nil, ""] and not Map.has_key?(@plans, claims["plan"]),
      do: Logger.warning("Unknown plan in subscription callback")

    if claims["subscription_source"] in [nil, ""],
      do: attrs,
      else: Map.put(attrs, :subscription_source, enum(claims["subscription_source"], @sources))
  end

  defp enum(value, values) when is_integer(value) do
    if value in Map.values(values),
      do: value,
      else: raise(ArgumentError, "Unknown subscription value")
  end

  defp enum(value, values) do
    case Map.fetch(values, value) do
      {:ok, number} -> number
      :error -> raise(ArgumentError, "Unknown subscription value")
    end
  end

  defp date(nil), do: nil

  defp date(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _} -> at
      _ -> raise(ArgumentError, "Invalid subscription date")
    end
  end

  defp callbacks(repo, user, changes, context) do
    if context[:self_hosted] == false do
      membership =
        repo.query!("SELECT family_id FROM family_memberships WHERE user_id=$1", [user.id],
          log: false
        ).rows

      if Map.has_key?(changes, :plan) and user.plan == 2 and membership == [],
        do:
          enqueue(
            repo,
            "families.auto_create",
            %{"user_id" => user.id, "time_zone" => Map.get(context, :timezone, "Europe/Berlin")},
            user.id,
            context
          )

      if Enum.any?([:plan, :status, :active_until], &Map.has_key?(changes, &1)) and
           membership != [] do
        [[id]] = membership

        enqueue(
          repo,
          "families.member_sync",
          %{
            "family_id" => id,
            "locale" => Map.get(context, :locale, "en"),
            "time_zone" => Map.get(context, :timezone, "Europe/Berlin")
          },
          id,
          context
        )
      end
    end
  end

  defp enqueue(repo, command, payload, id, context) do
    repo.query!(
      "INSERT INTO job_outbox(event_id,command_type,command_version,payload,aggregate_id,scheduled_at,metadata) VALUES($1,$2,1,$3,$4,$5,$6)",
      [
        Ecto.UUID.dump!(Ecto.UUID.generate()),
        command,
        payload,
        id,
        Map.get(context, :clock, &DateTime.utc_now/0).(),
        %{"producer" => "Subscriptions#callback"}
      ],
      log: false
    )
  end

  defp response(status, key), do: {:message, status, "controllers.api.v1.subscriptions." <> key}
end
