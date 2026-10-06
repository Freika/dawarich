defmodule Dawarich.ShareManagement.Mutations do
  @moduledoc false

  alias Dawarich.ShareManagement.{Params, Read}
  alias Dawarich.{Cable, Repo}

  def run(user, type, trip_id, action, params, locale, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    resource =
      case type do
        "live" -> Read.live(user, now)
        "trip" -> Read.trip(user, trip_id, now)
        "track" -> Read.track(user, trip_id, now)
        "timeline" -> Read.timeline(user, params, now)
        "shared" -> Read.owned(user, trip_id)
        _ -> :rails
      end

    with {:ok, page} <- resource do
      cond do
        type == "shared" and action != :revoke ->
          :rails

        action != :create and is_nil(page.share) ->
          missing(page)

        true ->
          perform(user, type, action, params, locale, page, now, opts)
      end
    end
    |> outcome()
  end

  defp perform(user, type, :create, params, locale, page, now, _opts) do
    with {:ok, attrs} <- Params.create(user, type, page.trip, params, locale) do
      errors = Params.validate(attrs, now, locale)

      cond do
        type == "live" and page.share != nil and errors != [] ->
          {:ok, hub} = Read.hub(user, %{}, now)

          for share <- Enum.sort_by(hub.shares, & &1.id),
              share.type == "live",
              do: broadcast(user, share)

          {:invalid, %{attrs: attrs, errors: errors, trip: page.trip}}

        errors != [] ->
          {:invalid, %{attrs: attrs, errors: errors, trip: page.trip}}

        true ->
          Repo.transaction(fn ->
            lock(user)

            active =
              Repo.query!(
                "SELECT id::text FROM shared_links WHERE user_id = $1 AND resource_type = $2 AND resource_id IS NOT DISTINCT FROM $3::bigint AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > $4) ORDER BY id",
                [user.id, attrs.resource_type, attrs.resource_id, DateTime.to_naive(now)]
              ).rows

            for [id] <- active, do: broadcast(user, %{type: type, id: id})

            Repo.query!(
              "UPDATE shared_links SET revoked_at = $4 WHERE user_id = $1 AND resource_type = $2 AND resource_id IS NOT DISTINCT FROM $3::bigint AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > $4)",
              [user.id, attrs.resource_type, attrs.resource_id, DateTime.to_naive(now)]
            )

            %{share: insert(attrs, now), trip: page.trip, committed?: true}
          end)
      end
    end
  end

  defp perform(user, type, :regenerate, _params, locale, page, now, _opts) do
    Repo.transaction(fn ->
      lock(user)
      page = reload(user, type, page, now)
      old = page.share

      attrs =
        Map.take(old, [
          :user_id,
          :resource_type,
          :resource_id,
          :name,
          :magic_phrase,
          :settings,
          :expires_at
        ])

      attrs =
        if old.expires_at && NaiveDateTime.compare(old.expires_at, DateTime.to_naive(now)) != :gt,
          do: %{attrs | expires_at: nil},
          else: attrs

      errors = Params.validate(attrs, now, locale)

      if errors != [],
        do: Repo.rollback({:invalid, %{attrs: attrs, errors: errors, trip: page.trip}})

      share = insert(attrs, now)
      broadcast(user, old)

      Repo.query!("DELETE FROM shared_links WHERE id = $1::text::uuid AND user_id = $2", [
        old.id,
        user.id
      ])

      %{share: share, trip: page.trip, committed?: true}
    end)
  end

  defp perform(user, type, :regenerate_phrase, _params, locale, page, now, opts) do
    Repo.transaction(fn ->
      lock(user)
      page = reload(user, type, page, now)
      share = Map.put(page.share, :magic_phrase, Keyword.get(opts, :phrase, &Read.phrase/0).())
      errors = Params.validate(share, now, locale, original: page.share)

      if errors != [],
        do: Repo.rollback({:invalid, %{attrs: share, errors: errors, trip: page.trip}})

      Repo.query!(
        "UPDATE shared_links SET magic_phrase = $3, updated_at = $4 WHERE id = $1::text::uuid AND user_id = $2",
        [share.id, user.id, share.magic_phrase, DateTime.to_naive(now)]
      )

      broadcast(user, page.share)
      %{share: share, trip: page.trip, committed?: true}
    end)
  end

  defp perform(user, type, :revoke, _params, _locale, page, now, _opts) do
    Repo.transaction(fn ->
      lock(user)
      page = reload(user, type, page, now)
      share = page.share

      Repo.query!(
        "UPDATE shared_links SET revoked_at = $3, updated_at = $3 WHERE id = $1::text::uuid AND user_id = $2",
        [share.id, user.id, DateTime.to_naive(now)]
      )

      broadcast(user, share)

      %{
        share: Map.put(share, :revoked_at, DateTime.to_naive(now)),
        trip: page.trip,
        committed?: true
      }
    end)
  end

  defp perform(user, type, :destroy, _params, _locale, page, now, _opts) do
    Repo.transaction(fn ->
      lock(user)
      page = reload(user, type, page, now)

      Repo.query!("DELETE FROM shared_links WHERE id = $1::text::uuid AND user_id = $2", [
        page.share.id,
        user.id
      ])

      %{share: page.share, trip: page.trip, committed?: true}
    end)
  end

  defp lock(user), do: Repo.query!("SELECT id FROM users WHERE id = $1 FOR UPDATE", [user.id])

  defp reload(user, type, page, now) do
    result =
      case type do
        "live" -> Read.live(user, now)
        "trip" -> Read.trip(user, page.trip.id, now)
        "track" -> Read.track(user, page.trip.id, now)
        "timeline" -> Read.timeline(user, %{}, now)
        "shared" -> Read.owned(user, page.share.id)
      end

    case result do
      {:ok, %{share: nil} = page} ->
        Repo.rollback(missing(page))

      {:ok, page} ->
        page

      error ->
        Repo.rollback(error)
    end
  end

  defp missing(%{trip: nil}), do: {:missing, "/map/v2"}
  defp missing(%{trip: %{type: "track"}}), do: {:missing, "/map/v2"}
  defp missing(%{trip: trip}), do: {:missing, "/trips/#{trip.id}"}
  defp outcome({:error, value}) when value == :rails or is_tuple(value), do: value
  defp outcome(value), do: value

  defp insert(attrs, now) do
    id = Ecto.UUID.generate()

    Repo.query!(
      "INSERT INTO shared_links (id, user_id, resource_type, resource_id, name, magic_phrase, settings, expires_at, created_at, updated_at) VALUES ($1::text::uuid, $2, $3, $4, $5, $6, $7, $8, $9, $9)",
      [
        id,
        attrs.user_id,
        attrs.resource_type,
        attrs.resource_id,
        attrs.name,
        attrs.magic_phrase,
        attrs.settings,
        attrs.expires_at,
        DateTime.to_naive(now)
      ]
    )

    Map.put(attrs, :id, id)
  end

  defp broadcast(_user, %{type: "live", id: id}) do
    Cable.broadcast_to("shared_location", {:shared_link, id}, %{"revoked" => true}, repo: Repo)
  end

  defp broadcast(_user, _share), do: :ok
end
