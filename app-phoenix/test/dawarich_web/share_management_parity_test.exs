defmodule DawarichWeb.ShareManagementParityTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.{Sharing, Repo}
  alias Dawarich.Test.FrameSeeds

  @dir "test/fixtures/share_management"
  @cases ~w(ambiguous_override hub_active_live hub_active_shared hub_active_timeline hub_active_unknown
    hub_bad_range hub_empty_live hub_empty_make hub_empty_shared hub_empty_timeline hub_empty_unknown
    hub_guest hub_range live_active live_active_frame live_delete live_delete_missing
    live_expiry_America_Havana live_expiry_Asia_Tokyo live_expiry_Europe_Berlin live_expiry_UTC
    live_expiry_blank live_expiry_dst_after live_expiry_future live_expiry_malformed live_expiry_past
    live_hub_blank live_hub_false live_hub_true live_invalid_frame live_invalid_hub live_invalid_magic_phrase
    live_invalid_name live_json_create live_new_document live_new_frame live_phrase live_phrase_missing
    live_revoke live_revoke_missing live_settings live_turbo_create live_url live_url_missing
    shared_revoke_foreign shared_revoke_live shared_revoke_missing shared_revoke_timeline shared_revoke_track
    shared_revoke_trip trip_active trip_active_frame trip_delete trip_delete_missing trip_expiry_blank
    trip_expiry_dst_after trip_expiry_future trip_expiry_malformed trip_expiry_past trip_foreign
    trip_invalid_magic_phrase trip_invalid_name trip_missing trip_new_document trip_new_frame trip_phrase
    trip_phrase_missing trip_revoke trip_revoke_missing trip_settings trip_url trip_url_missing)
  @names [
    "failed_live_replacement"
    | for(name <- @cases, locale <- ~w(en de es fr pl ca zh), do: name <> "_" <> locale)
  ]

  @domain_names for type <- ~w(track timeline),
                    action <-
                      ~w(new head empty_new create invalid url phrase revoke recreate delete),
                    do: "a12f3b/#{type}_#{action}_en"
  @domain_cases ["a12f3b/track_foreign_en" | @domain_names]

  setup do
    old = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg, bus: false)
    on_exit(fn -> Application.put_env(:dawarich, :cable, old) end)
    :ok
  end

  test "management corpus is complete" do
    actual =
      @dir |> Path.join("*.json") |> Path.wildcard() |> Enum.map(&Path.basename(&1, ".json"))

    assert Enum.sort(actual) == Enum.sort(@names)
    assert length(@names) == 505
  end

  for name <- @names ++ @domain_cases do
    @name name
    @tag management_case: name
    test "native management #{@name} preserves scoped inputs persisted rows and wire effects" do
      state = Path.join(@dir, @name <> ".json") |> File.read!() |> Jason.decode!()
      user = FrameSeeds.seed_management!(@name)

      if @name in @domain_cases do
        for {id, owner} <- [{99103, 98101}, {99104, 98102}] do
          FrameSeeds.track!(owner, id, %{
            start_at: ~N[2026-10-03 08:00:00],
            end_at: ~N[2026-10-03 09:00:00],
            distance: 1500,
            dominant_mode: 1
          })
        end
      end

      now = state["now"] |> DateTime.from_iso8601() |> elem(1)

      locale =
        DawarichWeb.Locale.resolve(
          Plug.Conn.Query.decode(URI.parse(state["path"]).query || "")["locale"],
          user,
          %{}
        )

      scope = Dawarich.Accounts.Scope.for_user(user, locale)
      resource = resource(state["path"], user && user.id)
      params = state["params"] || %{}
      query = Plug.Conn.Query.decode(URI.parse(state["path"]).query || "")

      if state["verb"] in ~w(GET HEAD) do
        result = Sharing.page(scope, resource, query, now: now, self_hosted: true)

        cond do
          user == nil ->
            assert {:error, :stale_session} = result

          state["status"] == 404 ->
            assert {:error, :not_found} = result

          state["status"] == 200 ->
            assert {:ok, page} = result
            refute inspect(page) =~ "magic_phrase"
            assert_read(page, state, user, resource, now)

          true ->
            assert {:error, _} = result
        end

        assert rows() == state["before"]
      else
        action = action(state)

        if Map.has_key?(state["headers"], "X-HTTP-Method-Override") do
          assert Phoenix.Router.route_info(
                   DawarichWeb.Router,
                   state["verb"],
                   URI.parse(state["path"]).path,
                   "www.example.com"
                 ) == :error

          assert rows() == state["before"]
          assert events() == []
        else
          result = Sharing.change(scope, resource, action, params, now: now, self_hosted: true)

          if state["after"] == state["before"] do
            assert {:error, _} = result
          else
            assert {:ok, value} = result
            refute inspect(value) =~ "magic_phrase"
          end

          assert normalize_rows(rows(), state) == normalize_rows(state["after"], state)
          assert events() == state["events"]
          assert_error_text(result, @name, locale)
        end
      end
    end
  end

  defp resource(path, owner) do
    type =
      cond do
        String.starts_with?(path, "/share_links/hub") -> :hub
        String.starts_with?(path, "/share_links/live") -> :live
        String.starts_with?(path, "/share_links/timeline") -> :timeline
        String.starts_with?(path, "/share_links/shares/") -> :shared
        String.starts_with?(path, "/tracks/") -> :track
        true -> :trip
      end

    resource = %{type: type, owner_id: owner}

    if type in [:trip, :track, :shared] do
      raw =
        URI.parse(path).path
        |> String.split("/", trim: true)
        |> Enum.at(if(type == :shared, do: 2, else: 1))

      Map.put(resource, :id, if(type == :shared, do: raw, else: String.to_integer(raw)))
    else
      resource
    end
  end

  defp action(state) do
    suffix = URI.parse(state["path"]).path |> String.split("/") |> List.last()

    cond do
      state["verb"] == "DELETE" -> :destroy
      suffix == "revoke" -> :revoke
      suffix == "regenerate" -> :regenerate
      suffix == "regenerate_phrase" -> :regenerate_phrase
      true -> :create
    end
  end

  defp assert_read(page, state, user, resource, now) do
    links = if resource.type == :hub, do: page.shares, else: List.wrap(page[:share])

    expected =
      Enum.filter(state["before"], fn row ->
        row["user_id"] == user.id and row["revoked_at"] == nil and
          (row["expires_at"] == nil or
             String.replace(row["expires_at"], " ", "T") >
               NaiveDateTime.to_iso8601(DateTime.to_naive(now)))
      end)

    if resource.type == :hub,
      do: assert(Enum.sort(Enum.map(links, & &1.id)) == Enum.sort(Enum.map(expected, & &1["id"])))

    for link <- links do
      source = Enum.find(state["before"], &(&1["id"] == link.id))
      assert source

      assert Map.take(link, [:name, :resource_type, :resource_id, :settings, :view_count])
             |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end) ==
               Map.take(source, ~w(name resource_type resource_id settings view_count))
    end

    if resource.type == :hub do
      assert page.tab in ~w(live timeline make shared unknown)

      assert Enum.map(page.shares, & &1.created_at) ==
               Enum.sort(Enum.map(page.shares, & &1.created_at), {:desc, NaiveDateTime})
    end
  end

  defp assert_error_text({:error, %{errors: errors}}, name, _locale) do
    field =
      cond do
        String.contains?(name, "expiry_past") or String.contains?(name, "invalid_frame") ->
          :expires_at

        String.contains?(name, "invalid_magic_phrase") or String.contains?(name, "invalid_hub") or
          String.contains?(name, "/track_invalid") or String.contains?(name, "/timeline_invalid") or
            name == "failed_live_replacement" ->
          :magic_phrase

        true ->
          :name
      end

    assert [{^field, message}] = errors
    assert is_binary(message) and String.trim(message) != ""
  end

  defp assert_error_text(_, _, _), do: :ok

  defp rows,
    do:
      Repo.query!("SELECT row_to_json(t) FROM shared_links t ORDER BY id").rows |> List.flatten()

  defp events do
    for [stream, payload] <-
          Repo.query!("SELECT channel,payload FROM phoenix.cable_events ORDER BY seq").rows do
      %{"stream" => stream, "message" => Jason.decode!(payload)}
    end
  end

  defp normalize_rows(rows, state) do
    before = Enum.map(state["before"], & &1["id"])

    Enum.map(rows, fn row ->
      row = if row["id"] in before, do: row, else: Map.put(row, "id", "NEW-ID")

      if String.ends_with?(state["path"], "regenerate_phrase") and
           row["magic_phrase"] not in [nil, "old-fixture-phrase"],
         do: Map.put(row, "magic_phrase", "PHRASE"),
         else: row
    end)
    |> Enum.sort_by(& &1["id"])
  end
end
