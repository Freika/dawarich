defmodule Dawarich.Maps.Dependencies.Public do
  @moduledoc false
  alias Dawarich.{Accounts, Maps, SharedLinks, TripSettings, UserTimeZone, Repo}
  alias Dawarich.SharedLinks.FamilyAudience
  alias Dawarich.SharedApi.{Points, Photos}
  alias DawarichWeb.SharedLinkCookie
  @false_flags [nil, false, "", "0", "false", "FALSE", "f", "F", "off", "OFF"]

  def config(capability, opts \\ []), do: with_link(capability, opts, &project(&1, capability))

  def read(capability, action, params, opts \\ []) do
    with_link(capability, opts, fn link ->
      result =
        case action do
          :points ->
            if route?(link) do
              if link.type == "live",
                do: Points.live(link, Keyword.get(opts, :now, DateTime.utc_now())),
                else: Points.index(link)
            else
              {:ok, []}
            end

          :route ->
            Points.route(link)

          action when action in [:photos, :thumbnail] ->
            Photos.native_response(link, action, params)

          _ ->
            {:error, 404, "not_found"}
        end

      case result do
        {:ok, data} -> {:ok, data}
        {:image, body} -> {:ok, {:image, body}}
        {:head, _} -> {:error, :not_found}
        {:error, 404, _} -> {:error, :not_found}
        _ -> {:error, :unavailable}
      end
    end)
  end

  defp with_link(capability, opts, fun) when is_map(capability) do
    with {:ok, link} <- admitted(capability, opts) do
      result = fun.(link)
      if callback = opts[:after_read], do: callback.()

      with {:ok, fresh} <- admitted(capability, opts),
           true <-
             Map.take(link, [:id, :user_id, :type, :resource_id, :settings, :magic_phrase]) ==
               Map.take(fresh, [:id, :user_id, :type, :resource_id, :settings, :magic_phrase]) do
        result
      else
        {:error, _} = error -> error
        _ -> {:error, :changed}
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp with_link(_, _, _), do: {:error, :not_found}

  defp admitted(%{id: id} = capability, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with true <- SharedLinks.canonical?(id),
         %{type: type} = link when type in ["trip", "track", "timeline", "live"] <-
           SharedLinks.active(id, now),
         true <- SharedLinks.api_owner_available?(id),
         {:ok, viewer} <-
           if(FamilyAudience.family_only?(link),
             do: viewer(capability[:viewer_scope], now),
             else: {:ok, nil}
           ),
         true <-
           FamilyAudience.accessible?(
             link,
             viewer,
             now,
             Keyword.get(opts, :self_hosted, System.get_env("SELF_HOSTED") == "true")
           ),
         :ok <-
           if(FamilyAudience.family_only?(link),
             do: :ok,
             else: phrase(link, capability[:proof], now)
           ),
         :ok <- resource(link) do
      {:ok, link}
    else
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  defp viewer(nil, _now), do: {:ok, nil}

  defp viewer(scope, now) do
    case Maps.admit(scope, now: now) do
      {:ok, fresh} -> {:ok, fresh.user}
      _ -> {:error, :not_found}
    end
  end

  defp phrase(link, proof, now) do
    case SharedLinkCookie.unlock_token(link.id, link.magic_phrase) do
      nil ->
        :ok

      token ->
        with %{"identity" => identity, "expires_at" => expiry} <- proof,
             true <- valid_expiry?(expiry, now),
             true <- Plug.Crypto.secure_compare(identity, SharedLinkCookie.proof_identity(token)) do
          :ok
        else
          _ -> {:error, :locked}
        end
    end
  end

  defp valid_expiry?(nil, _), do: true

  defp valid_expiry?(expiry, now) do
    case DateTime.from_iso8601(expiry) do
      {:ok, at, _} -> DateTime.compare(now, at) == :lt
      _ -> false
    end
  end

  defp resource(%{type: type, resource_present: false}) when type in ["trip", "track"],
    do: {:error, :missing_resource}

  defp resource(_), do: :ok

  defp route?(link),
    do:
      if(link.type == "live" or FamilyAudience.family_only?(link),
        do: link.settings["show_route"] not in @false_flags,
        else: true
      )

  defp valid_until(link, capability) do
    cookie =
      if not FamilyAudience.family_only?(link) and
           SharedLinkCookie.unlock_token(link.id, link.magic_phrase),
         do: (capability[:proof] || %{})["expires_at"]

    [link.expires_at, cookie]
    |> Enum.map(fn
      %NaiveDateTime{} = value ->
        DateTime.from_naive!(value, "Etc/UTC")

      %DateTime{} = value ->
        value

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, at, _} -> at
          _ -> nil
        end

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort(&(DateTime.compare(&1, &2) != :gt))
    |> List.first()
    |> then(fn
      nil -> nil
      at -> DateTime.to_iso8601(at)
    end)
  end

  defp project(link, capability) do
    settings = Accounts.settings(link.user_id)

    with {:ok, display} <- TripSettings.read(settings) do
      context = Photos.grant_context(link)
      {first, last} = context.range || {nil, nil}

      {:ok,
       %{
         "shareId" => link.id,
         "validUntil" => valid_until(link, capability),
         "publicType" => link.type,
         "title" => link.name,
         "styleName" => display.style,
         "photosEnabled" => link.settings["show_photos"] == true,
         "routeEnabled" => route?(link),
         "range" => %{
           "startAt" => first,
           "endAt" => last,
           "timezone" => UserTimeZone.iana(Repo, settings)
         }
       }}
    else
      _ -> {:error, :unavailable}
    end
  end
end
