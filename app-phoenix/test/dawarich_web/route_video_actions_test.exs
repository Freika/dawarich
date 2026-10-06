defmodule DawarichWeb.RouteVideoActionsTest do
  use Dawarich.IngestCase

  import Dawarich.Test.RailsFormRequests
  import Plug.Conn

  alias Dawarich.{MapGallery, RailsMessages, RouteVideos, ScratchRepo}
  alias Dawarich.Test.{ParityHTML, RailsUser}
  alias DawarichWeb.{RailsCsrf, RouteVideoStreams}

  @now ~U[2026-10-03 10:00:00Z]
  @stamp ~N[2026-10-03 10:00:00.000000]

  setup do
    Dawarich.JobsCase.reset!(ScratchRepo)

    actor =
      RailsUser.insert!(%{
        id: 8860,
        email: "a8-actions@dawarich.test",
        settings: %{"timezone" => "Europe/Berlin"}
      })

    ScratchRepo.insert_all("users", [actor])
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :jobs_repo, previous),
        else: Application.delete_env(:dawarich, :jobs_repo)
    end)

    session = RailsUser.session(actor.id)
    %{session: session, token: RailsCsrf.masked_token(session), user: actor}
  end

  defp blob!(id) do
    ScratchRepo.insert_all("active_storage_blobs", [
      %{
        id: id,
        key: "a8-actions-#{id}",
        filename: "synthetic-route.mp4",
        content_type: "video/mp4",
        byte_size: 32,
        checksum: "oAK5kDPivtZCT48Age7VqQ==",
        service_name: "test",
        created_at: @stamp,
        metadata: ~s({"identified":true,"analyzed":true})
      }
    ])
  end

  defp direct(ctx, body, accept, id) do
    post_form(
      ctx.session,
      body,
      [{"accept", accept}, {"x-csrf-token", ctx.token}],
      "/route_videos/#{id}"
    )
  end

  test "save returns prepend then evicted replacements then notice", %{user: user} = ctx do
    fixture = "test/fixtures/a8vv/videos/cap_one.json" |> File.read!() |> Jason.decode!()
    recipe = fixture["request"]["params"]["route_video"]["settings"]
    blob!(886_100)
    blob!(886_101)

    ScratchRepo.insert_all("route_videos", [
      %{
        id: 886_102,
        user_id: user.id,
        name: "Synthetic route",
        status: 0,
        settings: recipe,
        created_at: ~N[2026-10-03 08:00:00],
        updated_at: @stamp
      }
    ])

    ScratchRepo.insert_all("active_storage_attachments", [
      %{
        name: "file",
        record_type: "RouteVideo",
        record_id: 886_102,
        blob_id: 886_100,
        created_at: @stamp
      }
    ])

    params = %{
      "route_video" => %{
        "name" => "Saved route",
        "file" => RailsMessages.blob_id(886_101),
        "settings" => recipe
      }
    }

    ScratchRepo.query!("SELECT setval(pg_get_serial_sequence('route_videos','id'),8,false)")

    assert {:ok, %{id: id, evicted: [886_102]}} =
             RouteVideos.create(ScratchRepo, user, params, @now, "en", %{max_per_user: 1})

    video = MapGallery.route_video(user.id, id, "Europe/Berlin", ScratchRepo)
    expired = MapGallery.route_video(user.id, 886_102, "Europe/Berlin", ScratchRepo)
    html = RouteVideoStreams.save(video, [expired], "en")
    streams = LazyHTML.from_fragment(html) |> LazyHTML.query("turbo-stream")
    assert LazyHTML.attribute(streams, "action") == ["prepend", "replace", "append"]

    assert LazyHTML.attribute(streams, "target") == [
             "route-video-gallery-list",
             "route_video_886102",
             "flash-messages"
           ]

    flash =
      LazyHTML.from_fragment(html)
      |> LazyHTML.query("turbo-stream[target=flash-messages]")
      |> LazyHTML.to_html()

    oracle = File.read!("test/fixtures/a8vv/videos/all_recipe_keys.html")

    assert ParityHTML.fragment(flash, "template") ==
             ParityHTML.fragment(oracle, "turbo-stream[target=flash-messages] template")

    assert html =~ "Video saved to your gallery."

    normalized =
      Regex.replace(~r{(/rails/active_storage/blobs/(?:redirect|proxy)/)[^/]+/}, html, fn _full,
                                                                                          prefix ->
        prefix <> "BLOB_SIGNED_ID/"
      end)

    ids = %{"886102" => "886101", Integer.to_string(id) => "886102"}

    normalized =
      Regex.replace(~r{(route_video_|/route_videos/)(\d+)\b}, normalized, fn _, prefix, value ->
        prefix <> Map.get(ids, value, value)
      end)

    assert ParityHTML.normalize(normalized) ==
             ParityHTML.normalize(File.read!("test/fixtures/a8vv/videos/cap_one.html"))

    body =
      Plug.Conn.Query.encode(%{
        "route_video" => %{"name" => "Endpoint route", "file" => RailsMessages.blob_id(886_101)}
      })

    conn =
      post_form(
        ctx.session,
        body,
        [{"accept", "text/vnd.turbo-stream.html"}, {"x-csrf-token", ctx.token}],
        "/route_videos"
      )

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/vnd.turbo-stream.html; charset=utf-8"]
    assert conn.resp_body =~ "Endpoint route"

    assert ScratchRepo.query!("SELECT count(*) FROM route_videos WHERE name='Endpoint route'").rows ==
             [[1]]
  end

  test "destroy uses Turbo removal or HTML 303 map redirect with flash", ctx do
    for {id, accept} <- [{886_110, "text/vnd.turbo-stream.html"}, {886_111, "text/html"}] do
      blob!(id)

      assert {:ok, %{id: video}} =
               RouteVideos.create(
                 ScratchRepo,
                 ctx.user,
                 %{
                   "route_video" => %{
                     "name" => "Delete route",
                     "file" => RailsMessages.blob_id(id)
                   }
                 },
                 @now,
                 "en",
                 %{max_per_user: 0}
               )

      conn = direct(ctx, "_method=delete", accept, video)

      if accept == "text/html" do
        assert conn.status == 303
        assert get_resp_header(conn, "location") == ["http://www.example.com/map/v2"]
        assert rails_session(conn)["flash"]["flashes"]["notice"] == "Video deleted."
      else
        assert conn.status == 200
        streams = LazyHTML.from_fragment(conn.resp_body) |> LazyHTML.query("turbo-stream")
        assert LazyHTML.attribute(streams, "action") == ["remove"]
        assert LazyHTML.attribute(streams, "target") == ["route_video_#{video}"]
      end

      assert ScratchRepo.query!("SELECT id FROM route_videos WHERE id=$1", [video]).rows == []
    end
  end

  test "unknown or nonstring video zones replay before saving", ctx do
    blob!(886_120)
    upstream = upstream!()

    body =
      Plug.Conn.Query.encode(%{
        "route_video" => %{"name" => "Refused zone", "file" => RailsMessages.blob_id(886_120)}
      })

    for zone <- ["Mars/Unknown", %{}] do
      Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [ctx.user.id, %{"timezone" => zone}])

      assert {{"POST /route_videos HTTP/1.1", ^body}, %{status: 204}} =
               forwarded(upstream, fn ->
                 post_form(
                   ctx.session,
                   body,
                   [{"accept", "text/vnd.turbo-stream.html"}, {"x-csrf-token", ctx.token}],
                   "/route_videos"
                 )
               end)

      assert ScratchRepo.query!("SELECT id FROM route_videos").rows == []
      assert ScratchRepo.query!("SELECT id FROM phoenix.rails_commands").rows == []
    end
  end
end
