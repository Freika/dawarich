defmodule DawarichWeb.A8VideosVisitsParityTest do
  use Dawarich.JobsCase

  import Plug.Conn
  import Phoenix.LiveViewTest, only: [render_component: 2]
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.{Repo, ScratchRepo, Entitlements}
  alias Dawarich.Test.{FrameSeeds, RailsUser, ParityHTML}
  alias Dawarich.Visits.WebSettings
  alias DawarichWeb.{RailsAuth, RailsCsrf, A8Request, Locale, RailsHeaders, VisitSettingsActions}

  @dir "test/fixtures/a8vv"

  defmodule SaveFailureRepo do
    defdelegate transaction(fun), to: Dawarich.ScratchRepo

    def query!(sql, params, opts \\ []) do
      if String.starts_with?(sql, "INSERT INTO route_videos"),
        do: raise("synthetic save failure"),
        else: Dawarich.ScratchRepo.query!(sql, params, opts)
    end
  end

  defmodule CapFailureRepo do
    defdelegate transaction(fun), to: Dawarich.ScratchRepo

    def query!(sql, params, opts \\ []) do
      if String.starts_with?(sql, "UPDATE route_videos SET status"),
        do: raise("synthetic expiry status failure"),
        else: Dawarich.ScratchRepo.query!(sql, params, opts)
    end
  end

  @names ~w(
    settings/defaults settings/partial_save settings/raw_zero settings/raw_negative
    settings/raw_nonnumeric settings/cooldown_nil settings/cooldown_recent
    settings/cooldown_exact_hour settings/lite_hint settings/family_access settings/signed_out
    settings/navigation_default settings/navigation_suggested settings/navigation_declined
    settings/navigation_empty settings/redetect_allowed settings/redetect_recent
    videos/playable_card videos/expired_card videos/all_recipe_keys videos/untitled
    videos/unknown_recipe videos/unicode_recipe_65 videos/exact_ceiling videos/wrong_mime
    videos/over_ceiling videos/invalid_signature videos/pre_attach_error
    videos/post_commit_cap_error videos/cap_one videos/cap_zero videos/destroy_html
    videos/destroy_stream videos/shared_blob videos/stored_without_file videos/aged_boundary
    videos/metadata_unidentified videos/metadata_preidentified videos/metadata_shared_preidentified
    videos/blank_name_cap videos/blank_name_cron
    visits/confirm visits/rename visits/blank_name visits/decline visits/owned_place
    visits/suggested_foreign_place visits/foreign_area visits/demo_adoption visits/soft_delete
    visits/soft_delete_turbo visits/month_move visits/bulk_date visits/bulk_selection
    visits/bulk_500 visits/bulk_501 visits/bulk_foreign visits/bulk_hidden visits/bulk_archive
    visits/bulk_source visits/bulk_empty visits/bulk_no_callbacks visits/merge_points
    visits/merge_cross_day visits/merge_foreign visits/merge_same_place visits/merge_mixed_names
    visits/merge_noted visits/bulk_cross_day_destroy
    visits/missing_timezone_midnight visits/missing_timezone_dst visits/fractional_final_second
    visits/lite_cutoff_move visits/invalid_confidence_update visits/invalid_confidence_destroy
    visits/invalid_confidence_merge visits/html_update visits/html_destroy visits/html_merge
    visits/accept_html_preferred visits/accept_turbo_preferred
  )

  @tag :index
  test "the A8 corpus contains every named capture" do
    for extension <- ["json", "html"] do
      actual =
        Path.wildcard("#{@dir}/*/*.#{extension}")
        |> Enum.filter(fn path ->
          File.exists?(Path.rootname(path) <> ".json")
        end)
        |> Enum.map(&(&1 |> Path.relative_to(@dir) |> Path.rootname()))

      closure =
        if extension == "json",
          do:
            Enum.flat_map(["visits/a12f3a-v0", "videos/a12f3a-r0"], fn prefix ->
              Enum.map(1..9, &(prefix <> to_string(&1)))
            end),
          else: ["visits/a12f3a-v02"]

      assert Enum.sort(actual) == Enum.sort(@names ++ closure)
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    Dawarich.FixtureCleanup.delete!(
      ScratchRepo,
      ~w(places areas tags taggings visits place_visits notes tracks track_segments points stats route_videos)
    )

    previous =
      Map.new(
        ~w(SELF_HOSTED JWT_SECRET_KEY TIME_ZONE VIDEO_MAX_PER_USER),
        &{&1, System.get_env(&1)}
      )

    System.put_env("JWT_SECRET_KEY", "phoenix-a5-jwt-fixture-secret-not-for-production")
    System.put_env("TIME_ZONE", "UTC")

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    :ok
  end

  @settings_cases [
    {"settings/defaults", "default radius 100 to 99"},
    {"settings/partial_save", "replace settings instead of merge"},
    {"settings/raw_zero", "clamp submitted zero"},
    {"settings/raw_negative", "clamp submitted negative"},
    {"settings/raw_nonnumeric", "nonnumeric radius becomes default"},
    {"settings/cooldown_nil", "nil timestamp activates cooldown"},
    {"settings/cooldown_recent", "recent timestamp enables redetection"},
    {"settings/cooldown_exact_hour", "inclusive cooldown boundary"},
    {"settings/lite_hint", "omit Lite hint"},
    {"settings/family_access", "ignore inherited access"},
    {"settings/signed_out", "bypass RequireUser"},
    {"settings/navigation_default", "default status suggested"},
    {"settings/navigation_suggested", "drop suggested status"},
    {"settings/navigation_declined", "replace declined status"},
    {"settings/navigation_empty", "replace explicit empty status"},
    {"settings/redetect_allowed", "omit redetection command"},
    {"settings/redetect_recent", "omit cooldown pre-effect replay"}
  ]

  @visit_cases [
    {"visits/confirm", "omit explicit confirmation"},
    {"visits/rename", "omit silent confirmation"},
    {"visits/blank_name", "persist stripped blank name"},
    {"visits/decline", "implicit confirmation overrides decline"},
    {"visits/owned_place", "omit selected place name"},
    {"visits/suggested_foreign_place", "require selected place owner"},
    {"visits/foreign_area", "omit area owner predicate"},
    {"visits/demo_adoption", "omit tag adoption"},
    {"visits/soft_delete", "delete instead of tombstone"},
    {"visits/soft_delete_turbo", "delete instead of tombstone"},
    {"visits/month_move", "omit old month stamp"},
    {"visits/bulk_date", "scope dates in UTC"},
    {"visits/bulk_selection", "filter explicit selection by suggested status"},
    {"visits/bulk_500", "cap selection at 100"},
    {"visits/bulk_501", "allow 501"},
    {"visits/bulk_foreign", "omit complete cardinality check"},
    {"visits/bulk_hidden", "admit tombstones"},
    {"visits/bulk_archive", "omit Lite cutoff"},
    {"visits/bulk_source", "admit unknown source"},
    {"visits/bulk_empty", "accept empty delete selection"},
    {"visits/bulk_no_callbacks", "stamp updated_at"},
    {"visits/merge_points", "delete source before reassigning points"},
    {"visits/merge_cross_day", "omit same local day guard"},
    {"visits/merge_foreign", "omit owner predicate"},
    {"visits/merge_same_place", "concatenate same-place names"},
    {"visits/merge_mixed_names", "omit case-insensitive deduplication"},
    {"visits/merge_noted", "omit polymorphic note guard"},
    {"visits/bulk_cross_day_destroy", "always update day frame"},
    {"visits/missing_timezone_midnight", "force missing timezone to UTC"},
    {"visits/missing_timezone_dst", "force missing timezone to UTC"},
    {"visits/fractional_final_second", "refilter the committed visit by day"},
    {"visits/lite_cutoff_move", "refilter the committed visit by cutoff"},
    {"visits/invalid_confidence_update", "omit confidence validation"},
    {"visits/invalid_confidence_destroy", "omit confidence validation"},
    {"visits/invalid_confidence_merge", "omit confidence validation"},
    {"visits/html_update", "stage an extra success notice"},
    {"visits/html_destroy", "stage an extra success notice"},
    {"visits/html_merge", "stage an extra success notice"},
    {"visits/accept_html_preferred", "ignore Accept preference"},
    {"visits/accept_turbo_preferred", "ignore Accept preference"}
  ]

  @video_cases [
    {"videos/playable_card", "omit controls"},
    {"videos/expired_card", "omit recipe attribute"},
    {"videos/all_recipe_keys", "omit source"},
    {"videos/untitled", "persist blank name"},
    {"videos/unknown_recipe", "keep unknown recipe key"},
    {"videos/unicode_recipe_65", "slice graphemes"},
    {"videos/exact_ceiling", "reject inclusive ceiling"},
    {"videos/wrong_mime", "permit text/plain"},
    {"videos/over_ceiling", "omit byte ceiling"},
    {"videos/invalid_signature", "accept fixture blob without verification"},
    {"videos/pre_attach_error", "omit unattached purge"},
    {"videos/post_commit_cap_error", "replay committed save"},
    {"videos/cap_one", "expire newest"},
    {"videos/cap_zero", "apply disabled cap"},
    {"videos/destroy_html", "redirect 302"},
    {"videos/destroy_stream", "replace instead of remove"},
    {"videos/shared_blob",
     "detach remaining shared reference; Rails shim guard has named RSpec proof"},
    {"videos/stored_without_file", "render missing-file download"},
    {"videos/aged_boundary", "inclusive age cutoff"},
    {"videos/metadata_unidentified", "admit unidentified metadata"},
    {"videos/metadata_preidentified", "admit unanalyzed metadata"},
    {"videos/metadata_shared_preidentified", "reject shared identified blob"},
    {"videos/blank_name_cap", "omit expiry name validation"},
    {"videos/blank_name_cron", "omit expiry name validation"}
  ]

  for {name, mutation} <- @settings_cases ++ @visit_cases ++ @video_cases do
    @name name
    @tag capture: name,
         mutation: "M-P1-#{name}: #{mutation}",
         video: String.starts_with?(name, "videos/")
    test "#{@name} is answered and persisted as Rails answered it" do
      state = load(@name)
      repo = if page_case?(@name), do: Repo, else: ScratchRepo
      seed = seed_state(state)
      if repo == ScratchRepo, do: RailsUser.insert!(actor_attrs(seed["user"]), Repo)
      user = FrameSeeds.seed!(seed, repo)
      assert_case_graph(@name, state, user, repo)
      check_response_and_rows(@name, state, user, repo)
    end
  end

  defp load(name), do: File.read!("#{@dir}/#{name}.json") |> Jason.decode!()

  defp page_case?("settings/" <> name),
    do:
      name not in ~w(partial_save raw_zero raw_negative raw_nonnumeric redetect_allowed redetect_recent)

  defp page_case?("videos/" <> name),
    do: name in ~w(playable_card expired_card stored_without_file)

  defp page_case?(_name), do: false

  defp seed_state(state) do
    before = state["before"]
    user = before["user"] || List.first(before["users"] || [])
    rows = Map.merge(before["rows"] || %{}, Map.drop(before, ["user", "users", "rows"]))
    rows = Map.put(rows, "users", Enum.drop(before["users"] || [], 1))
    %{"user" => user, "rows" => rows}
  end

  defp actor_attrs(nil), do: %{}

  defp actor_attrs(user) do
    Map.new(user, fn {key, value} ->
      value =
        if key in ~w(active_until visits_redetected_at) and value,
          do: NaiveDateTime.from_iso8601!(value),
          else: value

      {String.to_atom(key), value}
    end)
  end

  defp assert_case_graph("settings/family_access", state, user, repo) do
    assert user.plan == 0

    assert [[2]] =
             repo.query!(
               "SELECT u.plan FROM family_memberships m JOIN families f ON f.id=m.family_id JOIN users u ON u.id=f.creator_id WHERE m.user_id=$1",
               [user.id]
             ).rows

    assert Entitlements.full_access?(repo, user, false, now(state))
  end

  defp assert_case_graph("visits/suggested_foreign_place", _state, user, repo) do
    assert [[owner, 920_001]] =
             repo.query!(
               "SELECT p.user_id,pv.visit_id FROM places p JOIN place_visits pv ON pv.place_id=p.id WHERE p.id=920001"
             ).rows

    assert owner != user.id
  end

  defp assert_case_graph("visits/merge_noted", _state, user, repo) do
    assert [[921_002, id]] =
             repo.query!("SELECT attachable_id,user_id FROM notes WHERE attachable_type='Visit'").rows

    assert id == user.id
  end

  defp assert_case_graph(_name, _state, _user, _repo), do: :ok

  defp now(state), do: state["now"] |> DateTime.from_iso8601() |> elem(1)

  defp check_response_and_rows("videos/" <> kind = name, state, user, repo) do
    alias Dawarich.{MapGallery, RailsMessages}
    alias Dawarich.RouteVideos.Retention
    alias DawarichWeb.RouteVideoActions

    req = state["request"]
    graph = state["before"]

    for table <- ~w(route_videos active_storage_attachments), req["method"] == "POST" do
      repo.query!("SELECT setval(pg_get_serial_sequence($1, 'id'), $2, false)", [
        table,
        req["blob_id"] + 2
      ])
    end

    html =
      case req["operation"] do
        operation
        when operation in ["card", "expire_and_purge", "retention", "retention_failure"] ->
          id = req["video_id"] || hd(graph["route_videos"])["id"]

          case operation do
            "retention_failure" ->
              Dawarich.Jobs.Ownership.put!(repo, "cron:route_videos_purge_job", :oban)

              assert_raise RuntimeError, "route video name validation", fn ->
                Dawarich.RouteVideos.PurgeWorker.run(repo, now(state), %{
                  retention_days: req["days"],
                  max_per_user: req["cap"]
                })
              end

              assert_video_rows(state["before"], repo)
              assert repo.query!("SELECT kind,payload FROM phoenix.rails_commands").rows == []

            "expire_and_purge" ->
              assert Retention.expire(repo, id, now(state)) == [id]

            "retention" ->
              assert Retention.run(repo, now(state), %{
                       retention_days: req["days"],
                       max_per_user: req["cap"]
                     }) == :ok

            _ ->
              :ok
          end

          video = MapGallery.route_video(user.id, id, "Europe/Berlin", repo)

          if operation != "retention_failure",
            do:
              render_component(&DawarichWeb.MapGalleryCards.route_video_card/1,
                video: video,
                locale: "en"
              )

        nil ->
          params = req["params"] || %{}

          params =
            if req["method"] == "POST" do
              put_in(
                params,
                ["route_video", "file"],
                if(kind == "invalid_signature",
                  do: "invalid-signed-id",
                  else: RailsMessages.blob_id(req["blob_id"])
                )
              )
            else
              params
            end

          state = Map.merge(state, Map.put(req, "params", params))
          conn = write_conn(state, user)
          action = if req["method"] == "POST", do: :create, else: :destroy

          selected_repo =
            case req["fault"] do
              "pre_attach_error" -> SaveFailureRepo
              "post_commit_cap_error" -> CapFailureRepo
              _ -> repo
            end

          previous = Application.get_env(:dawarich, :jobs_repo)
          Application.put_env(:dawarich, :jobs_repo, selected_repo)
          on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, previous) end)

          System.put_env(
            "VIDEO_MAX_PER_USER",
            if(kind in ["cap_one", "post_commit_cap_error", "blank_name_cap"], do: "1", else: "0")
          )

          if kind in ["metadata_unidentified", "metadata_preidentified"] do
            upstream = upstream!()

            {{line, body}, result} =
              forwarded(upstream, fn -> RouteVideoActions.call(conn, action) end)

            assert line == "#{req["method"]} #{req["path"]} HTTP/1.1"
            assert body == Plug.Conn.Query.encode(params)
            assert result.status == 204
            assert_video_rows(graph, repo)
            assert repo.query!("SELECT kind,payload FROM phoenix.rails_commands").rows == []
            nil
          else
            conn = RouteVideoActions.call(conn, action)
            check_headers(conn, state)

            if state["flash"] != %{},
              do: assert(rails_session(conn)["flash"]["flashes"] == state["flash"])

            conn.resp_body
          end
      end

    if html do
      normalized =
        Regex.replace(
          ~r{(/rails/active_storage/blobs/(?:redirect|proxy)/)[^/]+/},
          html,
          "\\1BLOB_SIGNED_ID/"
        )

      assert ParityHTML.first_difference(
               ParityHTML.normalize(normalized),
               ParityHTML.normalize(File.read!("#{@dir}/#{name}.html"))
             ) == "equal"

      oracle = File.read!("#{@dir}/#{name}.html")
      selectors = "[data-controller], [data-action], [data-turbo-method]"
      assert ParityHTML.stimulus(normalized, selectors) == ParityHTML.stimulus(oracle, selectors)
      actual_streams = LazyHTML.from_fragment(normalized) |> LazyHTML.query("turbo-stream")
      expected_streams = LazyHTML.from_fragment(oracle) |> LazyHTML.query("turbo-stream")

      for attribute <- ~w(action target) do
        assert LazyHTML.attribute(actual_streams, attribute) ==
                 LazyHTML.attribute(expected_streams, attribute)
      end

      assert_video_rows(state["after"], repo)
      assert_video_effects(state, user, repo)
    end
  end

  defp check_response_and_rows("visits/" <> _ = name, state, user, repo) do
    System.put_env("SELF_HOSTED", to_string(state["self_hosted"]))
    req = state["request"]
    state = Map.merge(state, req)

    action =
      case req["path"] do
        "/visits/bulk_update" -> :bulk_update
        "/visits/bulk_destroy" -> :bulk_destroy
        "/visits/merge" -> :merge
        _ -> if req["method"] == "DELETE", do: :destroy, else: :update
      end

    conn = write_conn(state, user)

    if state["status"] >= 400 or name == "visits/merge_noted" or
         String.starts_with?(name, "visits/invalid_confidence_") do
      upstream = upstream!()

      {{line, body}, result} =
        forwarded(upstream, fn -> DawarichWeb.VisitActions.call(conn, action) end)

      assert line == "#{req["method"]} #{req["path"]} HTTP/1.1"
      assert body == Plug.Conn.Query.encode(req["params"])
      assert result.status == 204
      assert_rows(flat_graph(state["before"]), repo)
      assert repo.query!("SELECT kind,payload FROM phoenix.rails_commands").rows == []
    else
      conn = DawarichWeb.VisitActions.call(conn, action)
      check_headers(conn, state)

      assert ParityHTML.first_difference(
               ParityHTML.normalize(conn.resp_body),
               ParityHTML.normalize(File.read!("#{@dir}/#{name}.html"))
             ) == "equal"

      streams = LazyHTML.from_fragment(conn.resp_body) |> LazyHTML.query("turbo-stream")

      assert Enum.zip(
               LazyHTML.attribute(streams, "action"),
               LazyHTML.attribute(streams, "target")
             ) ==
               Enum.map(state["streams"] || [], &List.to_tuple/1)

      actual_flash =
        if Map.has_key?(conn.resp_cookies, "_dawarich_session"),
          do: get_in(rails_session(conn), ["flash", "flashes"]) || %{},
          else: %{}

      assert actual_flash == state["flash"]

      assert_rows(flat_graph(state["after"]), repo)

      for {table, rows} <- state["before"]["rows"] do
        ids = Enum.map(rows, & &1["id"])
        expected = state["after"]["rows"][table] |> Enum.map(& &1["id"]) |> Enum.sort()

        assert repo.query!("SELECT id FROM #{table} WHERE id=ANY($1) ORDER BY id", [ids]).rows
               |> Enum.map(&hd/1) == expected
      end

      assert_visit_effects(action, state, user, repo)
    end
  end

  defp check_response_and_rows(name, state, user, repo) do
    System.put_env("SELF_HOSTED", to_string(state["self_hosted"]))

    cond do
      state["status"] == 200 and state["method"] == "GET" ->
        page =
          WebSettings.page(
            user,
            WebSettings.load(repo, user.id),
            now(state),
            state["self_hosted"]
          )

        html =
          render_component(
            &DawarichWeb.SettingsLive.Visits.render/1,
            Map.merge(page, %{
              current_user: user,
              locale: "en",
              self_hosted: state["self_hosted"],
              rails_csrf_token: "CSRF"
            })
          )

        assert ParityHTML.first_difference(
                 ParityHTML.normalize(html),
                 ParityHTML.normalize(File.read!("#{@dir}/#{name}.html"))
               ) == "equal"

        assert ParityHTML.stimulus(html, "[data-controller], [data-action]") ==
                 ParityHTML.stimulus(
                   File.read!("#{@dir}/#{name}.html"),
                   "[data-controller], [data-action]"
                 )

        System.put_env("SELF_HOSTED", "true")

        conn =
          Phoenix.ConnTest.dispatch(
            RailsUser.signed_in(user.id),
            DawarichWeb.Endpoint,
            :get,
            state["path"],
            nil
          )

        check_headers(conn, state)
        System.put_env("SELF_HOSTED", to_string(state["self_hosted"]))

      state["method"] == "GET" ->
        System.put_env("SELF_HOSTED", "true")

        conn =
          Phoenix.ConnTest.dispatch(
            Phoenix.ConnTest.build_conn(),
            DawarichWeb.Endpoint,
            :get,
            state["path"],
            nil
          )

        check_headers(conn, state)

        if state["flash"] != %{},
          do: assert(rails_session(conn)["flash"]["flashes"] == state["flash"])

        assert conn.resp_body == File.read!("#{@dir}/#{name}.html")
        System.put_env("SELF_HOSTED", to_string(state["self_hosted"]))

      name == "settings/redetect_recent" ->
        conn = write_conn(state, user)
        upstream = upstream!()

        {{line, body}, result} =
          forwarded(upstream, fn -> VisitSettingsActions.call(conn, :redetect) end)

        assert line == "POST /visits/redetections HTTP/1.1"
        assert body == Plug.Conn.Query.encode(state["params"])
        assert result.status == 204
        assert_rows(state["before"], repo)
        assert repo.query!("SELECT kind,payload FROM phoenix.rails_commands").rows == []

      true ->
        action = if state["path"] == "/settings/visits", do: :update, else: :redetect
        conn = VisitSettingsActions.call(write_conn(state, user), action)
        check_headers(conn, state)
        assert rails_session(conn)["flash"]["flashes"] == state["flash"]
        assert conn.resp_body == File.read!("#{@dir}/#{name}.html")
    end

    assert_rows(state["after"], repo)

    if repo == ScratchRepo do
      expected =
        for %{"job" => "Visits::FullHistoryRedetectJob", "args" => [id]} <- state["jobs"],
            do: [
              "visits.web_redetect",
              %{"user_id" => id, "locale" => "en", "timezone" => "Europe/Berlin"}
            ]

      assert repo.query!("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id").rows ==
               expected
    end
  end

  defp assert_video_rows(graph, repo) do
    rows = Map.drop(graph, ["user"])

    rows =
      Map.update!(rows, "active_storage_blobs", fn blobs ->
        Enum.map(
          blobs,
          &Map.update!(&1, "metadata", fn metadata ->
            if is_map(metadata), do: Jason.encode!(metadata), else: metadata
          end)
        )
      end)

    assert_rows(Map.put(rows, "users", [graph["user"]]), repo)

    for table <- ~w(route_videos active_storage_blobs active_storage_attachments) do
      assert repo.query!("SELECT id FROM #{table} ORDER BY id").rows ==
               Enum.map(rows[table], &[&1["id"]])
    end
  end

  defp assert_video_effects(state, user, repo) do
    before = state["before"]["active_storage_attachments"]
    after_ids = Enum.map(state["after"]["active_storage_attachments"], & &1["id"])
    detached = Enum.reject(before, &(&1["id"] in after_ids))

    expected =
      Enum.map(detached, fn attachment ->
        [
          "route_videos.attachment_job",
          %{
            "user_id" => user.id,
            "blob_id" => attachment["blob_id"],
            "action" => "purge_detached",
            "attachment" => Map.take(attachment, ~w(id name record_type record_id blob_id))
          }
        ]
      end)

    expected =
      if expected == [] do
        for %{"job" => "ActiveStorage::PurgeJob", "args" => [%{"_aj_globalid" => gid}]} <-
              state["jobs"],
            do: [
              "route_videos.attachment_job",
              %{
                "user_id" => user.id,
                "blob_id" => gid |> String.split("/") |> List.last() |> String.to_integer(),
                "action" => "purge_unattached"
              }
            ]
      else
        jobs = state["request"]["queued"] || state["jobs"]

        assert Enum.map(jobs, & &1["job"]) ==
                 Enum.map(detached, fn _ -> "ActiveStorage::PurgeJob" end)

        assert Enum.map(jobs, & &1["args"]) ==
                 Enum.map(detached, fn attachment ->
                   [
                     %{
                       "_aj_globalid" =>
                         "gid://dawarich/ActiveStorage::Blob/#{attachment["blob_id"]}"
                     }
                   ]
                 end)

        expected
      end

    if repo == Repo do
      assert expected == []
    else
      assert repo.query!("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id").rows ==
               expected
    end
  end

  defp flat_graph(graph), do: Map.merge(Map.delete(graph, "rows"), graph["rows"] || %{})

  defp assert_visit_effects(action, state, user, repo) do
    before = state["before"]["rows"]["visits"]
    after_rows = state["after"]["rows"]["visits"]
    params = state["params"]
    ids = params["visit_ids"]

    selected =
      cond do
        action in [:update, :destroy] ->
          Enum.filter(
            before,
            &(to_string(&1["id"]) == List.last(String.split(state["path"], "/")))
          )

        is_list(ids) ->
          Enum.filter(before, &(to_string(&1["id"]) in ids))

        true ->
          Enum.filter(before, fn old -> Enum.find(after_rows, &(&1["id"] == old["id"])) != old end)
      end

    stamps =
      if action in [:update, :destroy, :merge],
        do:
          selected ++
            Enum.filter(after_rows, &(&1["id"] in Enum.map(selected, fn r -> r["id"] end))),
        else: selected

    expected_stamps = stamps |> Enum.map(&stamp(&1["started_at"])) |> Enum.uniq() |> Enum.sort()
    commands = repo.query!("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id").rows
    assert [["visit_months_changed", payload] | rest] = commands
    assert payload["user_id"] == user.id
    assert Enum.sort(Enum.map(payload["started_at"], &stamp/1)) == expected_stamps

    if map_size(state["cache"]) > 0 do
      assert Map.keys(state["cache"]) |> Enum.sort() ==
               expected_stamps
               |> Enum.map(&(String.slice(&1, 0, 7) <> "-01"))
               |> Enum.uniq()
               |> Enum.sort()
    end

    orphan_ids =
      state["jobs"]
      |> Enum.flat_map(fn job ->
        if job["job"] == "Places::DeleteIfOrphanJob", do: job["args"], else: []
      end)

    assert rest ==
             if(orphan_ids == [],
               do: [],
               else: [
                 [
                   "places_delete_if_orphan",
                   %{"user_id" => user.id, "place_ids" => Enum.uniq(orphan_ids)}
                 ]
               ]
             )
  end

  defp stamp(value),
    do:
      value
      |> NaiveDateTime.from_iso8601!()
      |> Map.update!(:microsecond, fn {value, _precision} -> {value, 6} end)
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.to_iso8601()

  defp write_conn(state, user) do
    session = RailsUser.session(user.id)
    body = Plug.Conn.Query.encode(state["params"])

    state["method"]
    |> String.downcase()
    |> String.to_atom()
    |> Plug.Test.conn(state["path"], body)
    |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("accept", state["accept"] || "text/html")
    |> put_req_header("x-csrf-token", RailsCsrf.masked_token(session))
    |> RailsAuth.call([])
    |> A8Request.call([])
    |> Locale.call([])
    |> RailsHeaders.call([])
    |> assign(:now, now(state))
    |> Map.put(:path_params, %{"id" => List.last(String.split(state["path"], "/"))})
  end

  defp check_headers(conn, state) do
    assert conn.status == state["status"]
    assert get_resp_header(conn, "content-type") == [state["headers"]["content-type"]]
    assert get_resp_header(conn, "location") == List.wrap(state["location"])
    assert get_resp_header(conn, "vary") == List.wrap(state["headers"]["vary"])

    for key <- ~w(x-frame-options referrer-policy x-content-type-options),
        value = state["headers"][key],
        not is_nil(value),
        do: assert(get_resp_header(conn, key) == [value])
  end

  defp assert_rows(graph, repo) do
    for {table, expected} <- graph, is_list(expected), row <- expected do
      row =
        if table == "family_memberships",
          do: Map.update!(row, "role", &Map.fetch!(%{"owner" => 0, "member" => 1}, &1)),
          else: row

      [[actual]] = repo.query!("SELECT to_jsonb(t) FROM #{table} t WHERE id=$1", [row["id"]]).rows

      [[typed]] =
        repo.query!("SELECT to_jsonb(json_populate_record(NULL::#{table}, $1::text::json))", [
          Jason.encode!(row)
        ]).rows

      assert Map.take(actual, Map.keys(row)) == Map.take(typed, Map.keys(row)),
             "#{table} #{row["id"]}"
    end
  end
end
