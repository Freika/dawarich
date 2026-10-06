defmodule DawarichWeb.A12f3aRClosureTest do
  use Dawarich.JobsCase

  alias Dawarich.{MapGallery, RailsMessages, RouteVideos}
  alias Dawarich.RouteVideos.{AttachmentEffects, Retention}
  alias Dawarich.Test.{FrameSeeds, ParityHTML}
  import Phoenix.LiveViewTest, only: [render_component: 2]
  import Plug.Conn

  @now ~U[2026-10-03 10:00:00Z]

  setup do
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(route_videos))
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    :ok
  end

  @tag a12f3a_r05: true
  test "R05: native video attachment jobs and cron leaf matches current Rails contract without a native-owner Rails effect" do
    state = capture("r05", "shared_blob")
    user = seed(state)
    blob = hd(state["before"]["active_storage_blobs"])["id"]
    attachment = hd(state["before"]["active_storage_attachments"])

    payload = %{
      "user_id" => user.id,
      "blob_id" => blob,
      "action" => "purge_detached",
      "attachment" => Map.take(attachment, ~w(id name record_type record_id blob_id))
    }

    assert :ok = AttachmentEffects.enqueue!(ScratchRepo, payload)
    assert rows("SELECT count(*) FROM active_storage_blobs WHERE id=$1", [blob]) == [[1]]
    assert rows("SELECT id FROM oban.oban_jobs") == []
    rows("DELETE FROM active_storage_attachments WHERE blob_id=$1", [blob])
    replacement = Map.put(hd(state["before"]["active_storage_blobs"]), "id", blob + 10)
    replacement = Map.update!(replacement, "key", &(&1 <> "-replacement"))

    Dawarich.Test.ApiGolden.insert!(
      "active_storage_blobs",
      Map.update!(replacement, "metadata", &Jason.encode!/1),
      ScratchRepo
    )

    Dawarich.Test.ApiGolden.insert!(
      "active_storage_attachments",
      Map.put(attachment, "blob_id", blob + 10),
      ScratchRepo
    )

    assert :ok = AttachmentEffects.enqueue!(ScratchRepo, payload)
    assert rows("SELECT count(*) FROM active_storage_blobs WHERE id=$1", [blob]) == [[1]]
    rows("DELETE FROM active_storage_attachments WHERE id=$1", [attachment["id"]])
    assert :ok = AttachmentEffects.enqueue!(ScratchRepo, payload)
    assert :ok = AttachmentEffects.enqueue!(ScratchRepo, payload)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob]) == []

    assert [[%{"objects" => [%{"key" => key, "service_name" => "test"}]}]] =
             rows("SELECT args FROM oban.oban_jobs")

    assert key == hd(state["before"]["active_storage_blobs"])["key"]
    assert rows("SELECT id FROM phoenix.rails_commands") == []
    assert rows("SELECT count(*) FROM active_storage_blobs WHERE id=$1", [blob + 10]) == [[1]]
  end

  @tag a12f3a_r02: true
  test "R02: rejected and failed upload cleanup matches current Rails contract without a native-owner Rails effect" do
    for name <- ~w(wrong_mime over_ceiling pre_attach_error post_commit_cap_error) do
      state = capture("r02", name)
      user = seed(state)
      blob = state["request"]["blob_id"]

      if name in ~w(wrong_mime over_ceiling) do
        assert {:error, %{phase: :rejected}} =
                 RouteVideos.create(ScratchRepo, user, params(state), @now, "en", %{
                   max_per_user: 0
                 })

        assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob]) == []
        assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
      else
        assert :ok = AttachmentEffects.cleanup_failed_save!(ScratchRepo, user.id, blob)
        assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob]) == []
      end

      assert rows("SELECT id FROM phoenix.rails_commands") == []
    end

    state = capture("r02", "shared_blob")
    user = seed(state)
    blob = hd(state["before"]["active_storage_blobs"])["id"]
    assert :ok = AttachmentEffects.cleanup_failed_save!(ScratchRepo, user.id, blob)
    assert rows("SELECT count(*) FROM active_storage_blobs WHERE id=$1", [blob]) == [[1]]
    assert rows("SELECT id FROM oban.oban_jobs") == []
  end

  @tag a12f3a_r01: true
  test "R01: route-video signed upload and recipe matches current Rails contract without a native-owner Rails effect" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    previous = System.get_env("SELF_HOSTED")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    for mode <- ["true", "false", nil],
        name <-
          ~w(all_recipe_keys unknown_recipe unicode_recipe_65 untitled exact_ceiling invalid_signature metadata_unidentified metadata_preidentified metadata_shared_preidentified) do
      if mode, do: System.put_env("SELF_HOSTED", mode), else: System.delete_env("SELF_HOSTED")
      state = capture("r01", name)
      user = seed(state)
      actor = state["before"]["user"]
      Dawarich.Repo.query!("DELETE FROM users WHERE id=$1", [user.id], log: false)
      FrameSeeds.seed!(%{"user" => actor, "rows" => %{}}, Dawarich.Repo)
      session = Dawarich.Test.RailsUser.session(user.id)
      request = params(state)

      request =
        if name == "invalid_signature",
          do: put_in(request, ["route_video", "file"], "invalid"),
          else: request

      body = Plug.Conn.Query.encode(request)

      conn =
        Dawarich.Test.RailsFormRequests.post_form(
          session,
          body,
          [
            {"accept", "text/vnd.turbo-stream.html"},
            {"x-csrf-token", DawarichWeb.RailsCsrf.masked_token(session)}
          ],
          "/route_videos"
        )

      assert conn.status == state["status"], inspect({mode, name, conn.status, conn.resp_body})

      assert get_resp_header(conn, "content-type") == [
               "text/vnd.turbo-stream.html; charset=utf-8"
             ]

      if name != "invalid_signature" do
        before_ids = Enum.map(state["before"]["route_videos"], & &1["id"])
        expected = Enum.find(state["after"]["route_videos"], &(&1["id"] not in before_ids))

        assert [[owner, saved_name, settings]] =
                 rows("SELECT user_id,name,settings FROM route_videos ORDER BY id DESC LIMIT 1")

        assert owner == user.id
        assert saved_name == expected["name"]
        assert settings == expected["settings"]
        assert conn.resp_body =~ "route-video-gallery-list"
      else
        assert rows("SELECT id FROM route_videos") == []
      end

      assert rows("SELECT id FROM phoenix.rails_commands") == []
    end

    alias Dawarich.RouteVideos.Recipe

    assert Recipe.read(%{
             "duration_sec" => 15,
             "show_route" => true,
             "source" => ["trip"],
             "unknown" => "discard"
           }) ==
             {:ok, %{"duration_sec" => "15", "show_route" => "true", "source" => "[\"trip\"]"}}
  end

  @tag a12f3a_r03: true
  test "R03: route-video retention and gallery replacement matches current Rails contract without a native-owner Rails effect" do
    for name <- ~w(cap_one cap_zero aged_boundary) do
      state = capture("r03", name)
      user = seed(state)

      if name == "aged_boundary" do
        assert :ok = Retention.run(ScratchRepo, @now, %{retention_days: 30, max_per_user: 0})
      else
        expected = state["after"]["route_videos"] |> Enum.find(&(&1["name"] == "Saved route"))

        rows("SELECT setval(pg_get_serial_sequence('route_videos', 'id'),$1,false)", [
          expected["id"]
        ])

        assert {:ok, %{id: id, evicted: evicted}} =
                 RouteVideos.create(ScratchRepo, user, params(state), @now, "en", %{
                   max_per_user: if(name == "cap_one", do: 1, else: 0)
                 })

        video = MapGallery.route_video(user.id, id, "Europe/Berlin", ScratchRepo)

        expired =
          Enum.map(evicted, &MapGallery.route_video(user.id, &1, "Europe/Berlin", ScratchRepo))

        html = DawarichWeb.RouteVideoStreams.save(video, expired, "en")
        assert ParityHTML.normalize(normalize_urls(html)) == ParityHTML.normalize(state["body"])
      end

      assert rows("SELECT id,status,name,settings FROM route_videos ORDER BY id") ==
               Enum.map(
                 state["after"]["route_videos"],
                 &[&1["id"], &1["status"], &1["name"], &1["settings"]]
               )

      assert rows("SELECT id FROM phoenix.rails_commands") == []
    end
  end

  defp normalize_urls(html),
    do:
      Regex.replace(
        ~r{(/rails/active_storage/blobs/(?:redirect|proxy)/)[^/]+/},
        html,
        "\\1BLOB_SIGNED_ID/"
      )

  defp params(state) do
    put_in(
      state["request"]["params"],
      ["route_video", "file"],
      RailsMessages.blob_id(state["request"]["blob_id"])
    )
  end

  defp capture(task, name) do
    "test/fixtures/a8vv/videos/a12f3a-#{task}.json"
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("video_" <> name)
  end

  defp seed(state) do
    Dawarich.JobsCase.reset!(ScratchRepo)
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(route_videos))
    before = state["before"]

    FrameSeeds.seed!(
      %{"user" => before["user"], "rows" => Map.drop(before, ["user"])},
      ScratchRepo
    )
  end
end
