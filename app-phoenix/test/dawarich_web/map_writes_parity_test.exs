defmodule DawarichWeb.MapWritesParityTest do
  use Dawarich.JobsCase, async: false
  import Plug.Conn
  import Plug.Test
  alias Dawarich.Repo
  alias Dawarich.Test.{ApiGolden, FrameSeeds, ParityHTML, RailsUser}
  alias DawarichWeb.{TagWriteResponse, SegmentWriteResponse, PointListActions}
  @dir "test/fixtures/map_writes"
  @tags ~w(create_full create_omitted create_foreign_name blank_name unicode_blank_name duplicate_name
    icon_ten icon_eleven icon_ascii icon_symbol icon_blank color_short color_bad color_blank
    radius_blank radius_one radius_limit radius_zero radius_negative radius_over radius_nonnumeric
    radius_decimal_small radius_decimal_over radius_prefix radius_exponent radius_space radius_plus radius_hex
    multi_error partial_update update_self update_empty update_nondemo_noop failed_demo_update update_put
    override_patch override_put delete override_delete foreign_update missing_update foreign_delete guest_create prior_flash_invalid
    radius_unicode_space radius_precision_limit radius_precision_exponent radius_unicode_blank)
  @segments ~w(override_condensed override_raw override_unchanged override_tied disabled reset_changed reset_unchanged
    reset_preserved reset_empty reset_failure html_referer html_root html_disabled html_reset_failure
    override_post reset_post foreign_track wrong_nested missing_track missing_segment guest
    accept_turbo_only accept_html_first accept_turbo_q accept_html_q accept_wildcard)
  @points ~w(empty blank duplicate unmatched foreign mixed all untracked import_one timezone_month year_boundary
    lite_old filter_start filter_end filter_order filter_import query_precedence override_delete guest)

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)

    on_exit(fn ->
      try do
        Dawarich.MapMatchingTasks.await!()
      after
        Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
      end
    end)

    Repo.query!("CREATE SCHEMA IF NOT EXISTS phoenix")

    Repo.query!(File.read!("priv/repo/sql/20260928130000_rails_commands.sql"), [],
      query_type: :text
    )

    :ok
  end

  test "literal declared write cases exist exactly" do
    for {kind, names} <- [{"tags", @tags}, {"segments", @segments}, {"points", @points}] do
      expected = for name <- names, ext <- ~w(json html), do: "#{name}.#{ext}"
      assert Enum.sort(File.ls!("#{@dir}/#{kind}")) == Enum.sort(expected)
    end
  end

  test "tag state validation HTML response metadata match Rails" do
    for name <- @tags do
      {state, user, ctx, conn} = seed("tags", name)
      request = state["request"]
      attrs = Map.drop(request["params"]["tag"] || %{}, ["ignored"])
      id = request["path"] |> String.split("/") |> List.last() |> Integer.parse()
      method = request["params"]["_method"] || request["method"]

      action =
        cond do
          method in ~w(delete DELETE) -> :tag_destroy
          id == :error -> :tag_create
          true -> :tag_update
        end

      ctx = Map.put(ctx, :render, &TagWriteResponse.prepare(conn, action, &1, ctx))

      if state["validation"] && user do
        current =
          case id do
            {id, ""} -> state["before"]["tags"] |> Enum.find(&(&1["id"] == id)) |> atom_keys()
            :error -> %{}
          end

        valid = Dawarich.Tags.Validation.validate(Repo, user, attrs, current)
        oracle = state["validation"]
        assert valid.valid == oracle["valid"], name
        assert valid.raw_radius == oracle["raw_radius"], name
        assert valid.tag.privacy_radius_meters == oracle["cast_radius"], name
        assert valid.errors == oracle["errors"], name

        assert Map.new(oracle["attributes"], fn {key, _} ->
                 {key, Map.fetch!(valid.tag, String.to_existing_atom(key))}
               end) == oracle["attributes"],
               name
      end

      result =
        if user do
          case action do
            :tag_create -> Dawarich.Tags.Writes.create(Repo, user, attrs, ctx)
            :tag_update -> Dawarich.Tags.Writes.update(Repo, user, elem(id, 0), attrs, ctx)
            :tag_destroy -> Dawarich.Tags.Writes.destroy(Repo, user, elem(id, 0), ctx)
          end
        else
          :rails
        end

      if result in [:rails, :not_found] do
        assert state["status"] == if(result == :not_found, do: 404, else: 302), name
        assert_state(state["before"], name)
      else
        {_, result} = result
        response = result.response
        assert_metadata(response, state, name)

        if response.status == 422 do
          native =
            response.body
            |> IO.iodata_to_binary()
            |> LazyHTML.from_document()
            |> LazyHTML.query("body > div.container > div.w-full > div.flex")
            |> LazyHTML.to_tree()

          [{"div", _, native}] = native
          expected = html(File.read!("#{@dir}/tags/#{name}.html"))

          assert html(native) == expected,
                 name <> ": " <> ParityHTML.first_difference(html(native), expected)
        end

        assert_state(state["after"], name)
        assert commands() == [], name
      end
    end
  end

  test "segment stream reset state and rollback match Rails" do
    for name <- @segments do
      {state, user, ctx, conn} = seed("segments", name)
      [_, track, segment] = Regex.run(~r{/tracks/(\d+)/segments/(\d+)}, state["request"]["path"])
      {track, segment} = {String.to_integer(track), String.to_integer(segment)}

      Repo.query!("SELECT setval(pg_get_serial_sequence('track_segments','id'),$1,false)", [
        segment + 5
      ])

      ctx = Map.merge(ctx, %{csrf: "CSRF", unit: "km", location: state["location"]})

      conn =
        assign(
          conn,
          :map_write_format,
          if(state["content_type"] == "text/html", do: :html, else: :turbo_stream)
        )

      ctx = Map.put(ctx, :render, &SegmentWriteResponse.prepare(conn, &1, ctx))

      repo =
        if name in ~w(reset_failure html_reset_failure),
          do: DetectorFailureRepo,
          else: Repo

      params = state["request"]["params"]

      result =
        cond do
          is_nil(user) ->
            :rails

          params["reset"] == "true" ->
            Dawarich.Tracks.SegmentEditor.reset_to_auto(repo, user, track, segment, ctx)

          true ->
            Dawarich.Tracks.SegmentEditor.apply_override(
              repo,
              user,
              track,
              segment,
              params["track_segment"]["transportation_mode"],
              ctx
            )
        end

      if result in [:rails, :not_found] do
        assert state["status"] == if(result == :not_found, do: 404, else: 302), name
        assert_state(state["before"], name)
      else
        response =
          case result do
            {_, %{response: response}} ->
              response

            error ->
              {:ok, response} = SegmentWriteResponse.prepare(conn, error, ctx)
              response
          end

        assert_metadata(response, state, name)

        if state["content_type"] != "text/html" do
          actual =
            response.body
            |> IO.iodata_to_binary()
            |> String.replace(~r{</?template>}, "")
            |> html()

          expected =
            File.read!("#{@dir}/segments/#{name}.html")
            |> String.replace(~r{</?template>}, "")
            |> html()

          assert actual == expected, name <> ": " <> ParityHTML.first_difference(actual, expected)
        end

        assert_state(state["after"], name)
        expected = Enum.map(state["epochs"], fn [uid, min, max] -> {uid, min, max} end)

        actual =
          Enum.map(commands(), fn ["tracks_changed", payload] ->
            assert payload["updated"] == [track], name
            {payload["user_id"], payload["min_ts"], payload["max_ts"]}
          end)

        assert actual == expected, name

        assert Enum.map(state["broadcasts"], & &1["data"]["track"]["id"]) ==
                 Enum.map(actual, fn _ -> track end),
               name
      end
    end
  end

  test "points redirects counters and intent projection match Rails" do
    for name <- @points do
      {state, user, ctx, conn} = seed("points", name)

      if user do
        response = PointListActions.call(conn, :destroy)

        assert_metadata(
          %{conn: response, status: response.status, body: response.resp_body},
          state,
          name
        )

        assert_state(state["after"], name)

        case commands() do
          [] ->
            assert state["epochs"] == [] and state["achievements"] == [], name

          [["points.web_destroy_follow_up", payload]] ->
            assert state["epochs"] == [
                     %{"user_id" => user.id, "timestamps" => payload["timestamps"]}
                   ],
                   name

            assert state["achievements"] == [
                     %{"user_id" => user.id, "oldest_timestamp" => payload["oldest_timestamp"]}
                   ],
                   name

            tracks =
              for job <- state["jobs"],
                  job["job"] == "Tracks::RecalculateJob",
                  do: hd(job["args"])

            months =
              Enum.map(payload["timestamps"], fn stamp ->
                local =
                  Dawarich.UserTimeZone.local(
                    %{"timezone" => payload["timezone"]},
                    DateTime.from_unix!(stamp) |> DateTime.to_naive()
                  ).local

                [user.id, local.year, local.month]
              end)
              |> Enum.uniq()

            expected_months =
              for job <- state["jobs"], job["job"] == "Stats::CalculatingJob", do: job["args"]

            assert Enum.sort(months) == Enum.sort(expected_months), name
            assert payload["track_ids"] == tracks, name
            assert payload["locale"] == ctx.locale, name
            assert payload["timezone"] == Dawarich.UserTimeZone.iana(Repo, user.settings), name
        end
      else
        assert state["status"] == 302
        assert_state(state["before"], name)
      end
    end
  end

  defmodule DetectorFailureRepo do
    defdelegate transaction(fun), to: Dawarich.Repo
    defdelegate rollback(reason), to: Dawarich.Repo

    def query!(sql, params, opts \\ []) do
      if String.contains?(sql, "p.id AS point_id"),
        do: raise("synthetic detector failure"),
        else: Dawarich.Repo.query!(sql, params, opts)
    end
  end

  test "write cookie metadata preserves session changes and declares unchanged session exceptions" do
    for name <- ~w(blank_name prior_flash_invalid) do
      {state, user, ctx, conn} = seed("tags", name)
      attrs = state["request"]["params"]["tag"]

      current =
        if name == "prior_flash_invalid", do: atom_keys(hd(state["before"]["tags"])), else: %{}

      invalid = Dawarich.Tags.Validation.validate(Repo, user, attrs, current)
      {:ok, response} = TagWriteResponse.prepare(conn, :tag_create, {:invalid, invalid}, ctx)
      assert_metadata(response, state, name)
    end

    {state, _, ctx, conn} = seed("segments", "disabled")
    conn = assign(conn, :map_write_format, :turbo_stream)

    {:ok, response} =
      SegmentWriteResponse.prepare(conn, {:error, %{error_code: :mode_not_enabled}}, ctx)

    assert_metadata(response, state, "disabled")
  end

  defp seed(kind, name) do
    Dawarich.FixtureCleanup.delete!(
      Repo,
      ~w(users imports points places tags taggings visits tracks track_segments)
    )

    Repo.query!("DELETE FROM phoenix.rails_commands")
    state = File.read!("#{@dir}/#{kind}/#{name}.json") |> Jason.decode!()
    {:ok, now, _} = DateTime.from_iso8601(state["now"])

    users =
      state["before"]
      |> Map.values()
      |> List.flatten()
      |> Enum.map(& &1["user_id"])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    for id <- users do
      attrs =
        if state["user"] && state["user"]["id"] == id,
          do: atom_keys(state["user"]),
          else: %{email: "a6s4-parity-#{id}@example.invalid"}

      attrs =
        Map.merge(attrs, %{
          id: id,
          plan: 0,
          status: 0,
          changelog_consent: 0,
          created_at: DateTime.to_naive(now),
          updated_at: DateTime.to_naive(now)
        })

      FrameSeeds.user!(id, attrs[:settings] || %{}, Map.delete(attrs, :settings))
    end

    for table <- ~w(imports tracks places visits tags taggings track_segments points),
        row <- state["before"][table] || [] do
      row =
        if is_map(row["original_path"]) do
          [[hex]] =
            Repo.query!("SELECT encode(ST_AsEWKB(ST_GeomFromGeoJSON($1)), 'hex')", [
              Jason.encode!(row["original_path"])
            ]).rows

          Map.put(row, "original_path", hex)
        else
          row
        end

      ApiGolden.insert!(table, row)
    end

    for row <- state["before"]["users"] || [],
        do:
          Repo.query!("UPDATE users SET points_count=$2 WHERE id=$1", [
            row["id"],
            row["points_count"]
          ])

    if kind == "tags" do
      id = hd(state["before"]["tags"])["id"]
      Repo.query!("SELECT setval(pg_get_serial_sequence('tags','id'),$1,false)", [id + 2])
    end

    user =
      if state["user"] && name not in ~w(guest guest_create),
        do: Dawarich.Accounts.get(state["user"]["id"])

    session = if user, do: RailsUser.session(user.id), else: %{}

    session =
      if state["session_before"]["flash"],
        do: Map.put(session, "flash", state["session_before"]["flash"]),
        else: session

    params = state["request"]["params"]
    query = URI.parse(state["request"]["path"]).query || ""
    params = Map.merge(params, URI.decode_query(query))

    conn =
      conn(state["request"]["method"], state["request"]["path"])
      |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> assign(:current_user, user)
      |> assign(:rails_session, session)
      |> assign(:api_params, params)

    ctx = %{user: user, now: now, locale: "en", default_emoji: "☕"}
    {state, user, ctx, conn}
  end

  defp assert_metadata(response, state, name) do
    assert response.status == state["status"], name
    assert get_resp_header(response.conn, "location") == List.wrap(state["location"]), name
    assert get_resp_header(response.conn, "vary") == List.wrap(state["vary"]), name

    assert response.conn |> get_resp_header("content-type") |> hd() |> String.split(";") |> hd() ==
             state["content_type"],
           name

    unchanged = state["session_before"] == state["session_after"]

    exception =
      unchanged and
        (response.status == 422 or state["content_type"] == "text/vnd.turbo-stream.html")

    expected_cookie = state["set_cookie"] and not exception
    assert Map.has_key?(response.conn.resp_cookies, "_dawarich_session") == expected_cookie, name

    session =
      if response.conn.resp_cookies["_dawarich_session"],
        do: Dawarich.Test.RailsFormRequests.rails_session(response.conn),
        else: response.conn.assigns.rails_session

    assert session["flash"] == state["session_after"]["flash"], name
    assert is_binary(session["_csrf_token"]) == state["session_after"]["csrf_present"], name
    assert session["user_return_to"] == state["session_after"]["user_return_to"], name
  end

  defp assert_state(expected, name) do
    for {table, rows} <- expected do
      projection =
        cond do
          table == "tracks" ->
            "to_jsonb(t) || jsonb_build_object('original_path',ST_AsGeoJSON(original_path,15,2)::jsonb)"

          table == "users" ->
            "jsonb_build_object('id',id,'points_count',points_count,'updated_at',to_char(updated_at,'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'))"

          true ->
            "to_jsonb(t)"
        end

      actual =
        Repo.query!("SELECT (#{projection})::text FROM #{table} t ORDER BY id").rows
        |> Enum.map(fn [json] -> Jason.decode!(json) end)

      rows = Enum.map(rows, &Dawarich.Test.ApiGolden.column_defaults(table, &1))
      assert actual == rows, "#{name}: #{table}: " <> ParityHTML.first_difference(actual, rows)
    end
  end

  defp atom_keys(row), do: Map.new(row, fn {key, value} -> {String.to_atom(key), value} end)

  defp commands,
    do: Repo.query!("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id").rows

  defp html(html) when is_binary(html),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> html()

  defp html(nodes) when is_list(nodes),
    do: nodes |> Enum.flat_map(&island/1) |> ParityHTML.normalize()

  defp island({"fieldset", attrs, children}) do
    if Map.has_key?(Map.new(attrs), "data-rails-form-ready") do
      assert Enum.sort(attrs) ==
               Enum.sort([{"disabled", ""}, {"data-rails-form-ready", ""}, {"class", "contents"}])

      Enum.flat_map(children, &island/1)
    else
      [{"fieldset", attrs, Enum.flat_map(children, &island/1)}]
    end
  end

  defp island({"div", attrs, children}) do
    if Map.new(attrs)["phx-hook"] == "RailsStimulus",
      do: Enum.flat_map(children, &island/1),
      else: [{"div", attrs, Enum.flat_map(children, &island/1)}]
  end

  defp island({tag, attrs, children}), do: [{tag, attrs, Enum.flat_map(children, &island/1)}]
  defp island(node), do: [node]
end
