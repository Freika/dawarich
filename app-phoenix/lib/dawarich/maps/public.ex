defmodule Dawarich.Maps.Public do
  @moduledoc false
  alias Dawarich.{Accounts, Maps, SharedLinks, TripSettings, UserTimeZone, Repo}
  alias Dawarich.SharedLinks.FamilyAudience
  alias Dawarich.SharedApi.{Points, Photos}
  alias DawarichWeb.SharedLinkCookie
  @false_flags [nil, false, "", "0", "false", "FALSE", "f", "F", "off", "OFF"]

  def config(capability, opts \\ []) do
    with {:ok, bound} <- Dawarich.Maps.PublicGrant.bind(capability, opts),
         do: with_link(bound, opts, &project(&1, bound))
  end

  def presentation(capability, opts \\ []) do
    opts = delivery_options(opts)

    with {:ok, bound} <- Dawarich.Maps.PublicGrant.bind(capability, opts) do
      with_link(bound, opts, fn link ->
        with {:ok, page} <-
               Dawarich.Sharing.Pages.resource(bound.grant, Keyword.get(opts, :params, %{}), opts) do
          page =
            if page.resource,
              do: put_in(page.resource.photos, Photos.gallery(link)),
              else: page

          {:ok, Dawarich.Maps.PublicPresentation.project(page, FamilyAudience.family_only?(link))}
        end
      end)
    end
  end

  def navigation(capability, opts \\ []) do
    with_link(
      capability,
      opts,
      fn link ->
        if FamilyAudience.family_only?(link) do
          with {:ok, scope} <- Maps.admit(capability.viewer_scope, opts) do
            navbar =
              Maps.with_actor(
                scope,
                fn user ->
                  Dawarich.Navbar.load(user,
                    now: Keyword.get(opts, :now, DateTime.utc_now()),
                    self_hosted:
                      Keyword.get(opts, :self_hosted, DawarichWeb.LayoutAssigns.self_hosted?())
                  )
                end,
                opts
              )

            if is_map(navbar),
              do: {:ok, %{scope: scope, navbar: navbar}},
              else: {:error, :unavailable}
          end
        else
          {:ok, nil}
        end
      end,
      false
    )
  end

  def record_visit(capability, opts \\ []) do
    with_link(
      capability,
      opts,
      fn link ->
        SharedLinks.touch!(link.id, Keyword.get(opts, :now, DateTime.utc_now()))
        :ok
      end,
      false
    )
  end

  def read(capability, action, params, opts \\ []) do
    with_link(capability, opts, fn link ->
      result =
        case action do
          :points ->
            if link.type == "live" or route?(link) do
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

  defp with_link(capability, opts, fun, resource? \\ true)

  defp with_link(capability, opts, fun, resource?) when is_map(capability) do
    opts = delivery_options(opts)

    with {:ok, bound} <- Dawarich.Maps.PublicGrant.bind(capability, opts),
         {:ok, link} <- admitted(bound, opts, resource?),
         {:ok, admission} <-
           Dawarich.Sharing.Public.admit(bound.grant, Dawarich.Sharing.Delivery.now(opts)) do
      snapshot = Dawarich.Sharing.Delivery.resource_snapshot({:ok, admission})
      result = fun.(link)

      case Dawarich.Sharing.Delivery.deliver({:resource, bound.grant}, snapshot, result, opts) do
        {:ok, result} -> result
        error -> error
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp with_link(_, _, _, _), do: {:error, :not_found}

  defp delivery_options(opts) do
    Keyword.put_new_lazy(opts, :clock, fn ->
      Dawarich.Families.Clock.ticking(Keyword.get_lazy(opts, :now, &DateTime.utc_now/0))
    end)
  end

  defp admitted(capability, opts, resource?),
    do: Dawarich.Maps.PublicGrant.admit(capability, opts, resource?)

  defp route?(link),
    do:
      if(link.type == "live" or FamilyAudience.family_only?(link),
        do: link.settings["show_route"] not in @false_flags,
        else: link.settings["show_route"] not in (@false_flags -- [nil])
      )

  defp valid_until(link, capability) do
    cookie =
      if not FamilyAudience.family_only?(link) and
           SharedLinkCookie.unlock_token(link.id, link.magic_phrase),
         do: (capability[:proof] || %{})["expires_at"]

    [
      link.expires_at,
      cookie,
      capability[:grant] && DateTime.from_unix!(capability.grant.expires_at)
    ]
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
         "byDay" => link.type == "trip" and link.settings["show_days"] != false,
         "routeOptions" => %{
           "distanceThresholdMeters" => display.meters,
           "timeThresholdMinutes" => display.minutes
         },
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
