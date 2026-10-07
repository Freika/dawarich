defmodule DawarichWeb.RouteVideoParityTest do
  use Dawarich.IngestCase
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.{ScratchRepo, RailsMessages}
  alias Dawarich.Test.RailsUser

  setup do
    Dawarich.JobsCase.reset!(ScratchRepo)

    user =
      RailsUser.insert!(%{
        id: 99001,
        email: "synthetic-parity@example.test",
        settings: %{"timezone" => "Europe/Berlin"}
      })

    ScratchRepo.insert_all("users", [user])
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")
    old_repo = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")

      Application.put_env(:dawarich, :jobs_repo, old_repo)
    end)

    [[blob]] =
      ScratchRepo.query!(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES('synthetic-parity','synthetic.mp4','video/mp4',$1,'test',32,'synthetic',now()) RETURNING id",
        [~s({"identified":true,"analyzed":true})],
        log: false
      ).rows

    session = RailsUser.session(user.id)

    %{
      session: session,
      token: DawarichWeb.RailsCsrf.masked_token(session),
      signed: RailsMessages.blob_id(blob)
    }
  end

  @tag :nested_settings
  test "container form recipe matches Rails acceptance", c do
    body =
      "route_video[name]=Synthetic&route_video[file]=" <>
        URI.encode_www_form(c.signed) <>
        "&route_video[settings][theme][z]=one&route_video[settings][theme][a]=two" <>
        "&route_video[settings][source][]=trip&route_video[settings][source][]=map" <>
        "&route_video[settings][format][nested][9][Mixed-Key]=ok" <>
        "&route_video[settings][unknown][deep]=ignored"

    conn =
      post_form(
        c.session,
        body,
        [{"accept", "text/vnd.turbo-stream.html"}, {"x-csrf-token", c.token}],
        "/route_videos"
      )

    assert conn.status == 200
    [[settings]] = ScratchRepo.query!("SELECT settings FROM route_videos", [], log: false).rows

    assert settings == %{
             "theme" => ~s({"z" => "one", "a" => "two"}),
             "source" => ~s(["trip", "map"]),
             "format" => ~s({"nested" => {"9" => {"Mixed-Key" => "ok"}}})
           }
  end

  @tag :unknown_fields
  test "unknown video field matches Rails acceptance", c do
    body =
      Plug.Conn.Query.encode(%{
        "route_video" => %{
          "name" => "Synthetic",
          "file" => c.signed,
          "unexpected" => "ignored",
          "another" => %{"nested" => "ignored"}
        }
      })

    conn =
      post_form(
        c.session,
        body,
        [{"accept", "text/vnd.turbo-stream.html"}, {"x-csrf-token", c.token}],
        "/route_videos"
      )

    assert conn.status == 200
  end

  @tag :ordered_settings
  test "Ruby container string preserves source ordered hash", c do
    for fields <- [
          "&route_video[settings][theme][z]=one&route_video[settings][theme][a]=two",
          "&route_video[settings][theme][a]=two&route_video[settings][theme][z]=one"
        ] do
      body =
        "route_video[name]=Synthetic&route_video[file]=" <>
          URI.encode_www_form(c.signed) <> fields

      conn =
        post_form(
          c.session,
          body,
          [{"accept", "text/vnd.turbo-stream.html"}, {"x-csrf-token", c.token}],
          "/route_videos"
        )

      assert conn.status == 200

      [[settings]] =
        ScratchRepo.query!("SELECT settings FROM route_videos ORDER BY id DESC LIMIT 1", [],
          log: false
        ).rows

      expected =
        if String.starts_with?(fields, "&route_video[settings][theme][z]"),
          do: ~s({"z" => "one", "a" => "two"}),
          else: ~s({"a" => "two", "z" => "one"})

      assert settings["theme"] == expected
    end
  end

  @tag :zero_id
  test "zero video ID matches Rails not found status", c do
    conn =
      post_form(
        c.session,
        "_method=delete",
        [{"accept", "text/vnd.turbo-stream.html"}, {"x-csrf-token", c.token}],
        "/route_videos/0"
      )

    assert conn.status == 404
  end
end
