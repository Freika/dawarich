defmodule DawarichWeb.StandalonePlaceBrowserTest do
  use Dawarich.IngestCase, async: false

  import Phoenix.ConnTest, only: [dispatch: 4]
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.Test.{RailsUser, SeedIds, TripsSeeds}
  alias DawarichWeb.{PlaceRequest, RailsCsrf, TripRequest}

  @accept "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"

  setup do
    env = Map.take(System.get_env(), ~w(DAWARICH_RAILS SELF_HOSTED))
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true"})
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Repo)

    on_exit(fn ->
      Application.put_env(:dawarich, :jobs_repo, previous)

      for name <- ~w(DAWARICH_RAILS SELF_HOSTED) do
        if env[name], do: System.put_env(name, env[name]), else: System.delete_env(name)
      end
    end)

    Repo.query!(
      "SELECT setval(pg_get_serial_sequence('places','id'),COALESCE((SELECT MAX(id) FROM places),0)+1,false)",
      [],
      log: false
    )

    id = user!(%{encrypted_password: "$2a$04$" <> String.duplicate("phoenixa5fixture", 4)})
    %{id: id, session: RailsUser.session(id)}
  end

  @tag :sa_g44_places
  test "standalone modal create and marker edit retain tags and notes through drawer saves",
       ctx do
    params = %{
      "_method_url" => "",
      "commit" => "Create Place",
      "place" => %{
        "name" => "Browser place",
        "latitude" => "52.52",
        "longitude" => "13.405",
        "source" => "manual",
        "note" => "Note from the map"
      }
    }

    created = submit(ctx.session, "/places", params)
    assert created.status == 200
    assert created.resp_body =~ "Place created successfully!"
    assert created.resp_body =~ ~s(data-created="true")

    [[id, "Note from the map"]] =
      Repo.query!("SELECT id,note FROM places WHERE user_id=$1", [ctx.id]).rows

    stamp = NaiveDateTime.utc_now()

    {2, tags} =
      SeedIds.insert_all!(
        Repo,
        "tags",
        for name <- ["Cafe", "Office"] do
          %{
            user_id: ctx.id,
            name: name,
            color: "#3b82f6",
            created_at: stamp,
            updated_at: stamp
          }
        end,
        returning: [:id]
      )

    for tag <- tags do
      attrs =
        Map.merge(params["place"], %{"name" => "Renamed place", "tag_ids" => [to_string(tag.id)]})

      edited =
        submit(ctx.session, "/places/#{id}", %{
          "_method_url" => "",
          "_method" => "patch",
          "commit" => "Update Place",
          "place" => attrs
        })

      assert edited.status == 200
      assert edited.resp_body =~ ~s(data-updated="true")
      assert edited.resp_body =~ ~s(target="place-drawer")

      assert Repo.query!(
               "SELECT tag_id FROM taggings WHERE taggable_type='Place' AND taggable_id=$1",
               [id]
             ).rows == [[tag.id]]
    end

    for note <- ["Saved from the map drawer", "Saved a second time"] do
      saved =
        submit(
          ctx.session,
          "/places/#{id}",
          %{
            "_method" => "patch",
            "commit" => "Save",
            "place" => %{"note" => note}
          },
          "place-drawer"
        )

      assert saved.status == 200
      assert saved.resp_body =~ note
      assert saved.resp_body =~ ~s(target="place-drawer")
      refute saved.resp_body =~ ~s(target="place-creation-data")

      assert Repo.query!("SELECT name,note FROM places WHERE id=$1", [id]).rows == [
               ["Renamed place", note]
             ]
    end

    assert submit(ctx.session, "/places", Map.put(params, "authenticity_token", "invalid")).status ==
             422

    stranger =
      RailsUser.session(
        user!(%{encrypted_password: "$2a$04$" <> String.duplicate("phoenixa5fixture", 4)})
      )

    assert submit(stranger, "/places/#{id}", Map.put(params, "_method", "patch")).status == 404
    assert submit(%{}, "/places", params).status == 302

    for action <- [:place_create, :place_update] do
      assert PlaceRequest.fields?(action, params)
      refute PlaceRequest.fields?(action, Map.put(params, "_method_url", %{"id" => "1"}))
      refute PlaceRequest.fields?(action, Map.put(params, "unexpected", "1"))
    end

    refute PlaceRequest.fields?(:place_destroy, %{"_method_url" => ""})
    refute TripRequest.fields?(:note_create, %{"_method_url" => "", "note" => %{"body" => "x"}})
    assert commands() == []
  end

  @tag :sa_g44_trip_notes
  test "standalone trip note forms create update and delete their exact Turbo frame", ctx do
    trip = TripsSeeds.trip!(%{id: 989_210, user_id: ctx.id})
    frame = "note-#{trip}-2026-05-10"
    path = "/trips/#{trip}/notes"

    created =
      submit(
        ctx.session,
        path,
        %{"note" => %{"date" => "2026-05-10", "body" => "First note"}},
        frame
      )

    assert created.status == 200
    assert created.resp_body =~ ~s(target="#{frame}")

    [[id]] = Repo.query!("SELECT id FROM notes WHERE user_id=$1", [ctx.id]).rows

    updated =
      submit(
        ctx.session,
        "#{path}/#{id}",
        %{
          "_method" => "patch",
          "commit" => "Update Note",
          "note" => %{"date" => "2026-05-10", "body" => "Updated note"}
        },
        frame
      )

    assert updated.status == 200
    assert updated.resp_body =~ ~s(target="#{frame}")
    assert Repo.query!("SELECT body FROM notes WHERE id=$1", [id]).rows == [["Updated note"]]

    deleted = submit(ctx.session, "#{path}/#{id}", %{"_method" => "delete"}, frame)
    assert deleted.status == 200
    assert deleted.resp_body =~ ~s(target="#{frame}")
    assert Repo.query!("SELECT id FROM notes WHERE id=$1", [id]).rows == []
    assert commands() == []
  end

  @tag :sa_g44_place_precision
  test "standalone map modal preserves full browser coordinate input at Rails storage precision",
       ctx do
    params = %{
      "_method_url" => "",
      "commit" => "Create Place",
      "place" => %{
        "name" => "Precision place",
        "latitude" => "52.444541348981886",
        "longitude" => "13.26398331296545",
        "source" => "manual",
        "note" => ""
      }
    }

    created = submit(ctx.session, "/places", params)
    assert created.status == 200
    assert created.resp_body =~ ~s(data-created="true")

    [[id, lat, lon, y, x]] =
      Repo.query!(
        "SELECT id,latitude::float8,longitude::float8,ST_Y(lonlat::geometry),ST_X(lonlat::geometry) FROM places WHERE user_id=$1",
        [ctx.id]
      ).rows

    assert [lat, lon, y, x] == [52.444541, 13.263983, 52.444541, 13.263983]
    edited = submit(ctx.session, "/places/#{id}", Map.put(params, "_method", "patch"))
    assert edited.status == 200
    assert edited.resp_body =~ ~s(data-updated="true")
    assert commands() == []
  end

  @tag :sa_g44_place_query
  test "standalone place drawer and nearby ignore Rails-accepted extra query fields", ctx do
    created =
      submit(ctx.session, "/places", %{
        "_method_url" => "",
        "place" => %{"name" => "Query place", "latitude" => "52.52", "longitude" => "13.405"}
      })

    assert created.status == 200
    [[id]] = Repo.query!("SELECT id FROM places WHERE user_id=$1", [ctx.id]).rows

    for query <- ["extra=1", "extra[nested]=1", "extra[]=1&extra[]=2"] do
      drawer =
        RailsUser.signed_in(ctx.id)
        |> Plug.Conn.put_req_header("turbo-frame", "place-drawer")
        |> dispatch(DawarichWeb.Endpoint, :get, "/places/#{id}?#{query}")

      assert drawer.status == 200
      assert drawer.resp_body =~ "Query place"

      nearby =
        RailsUser.signed_in(ctx.id)
        |> Plug.Conn.put_req_header("turbo-frame", "place-drawer")
        |> dispatch(DawarichWeb.Endpoint, :get, "/places/nearby?latitude=0&longitude=0&#{query}")

      assert nearby.status == 200
      assert nearby.resp_body =~ "No nearby places found"
    end

    foreign =
      RailsUser.signed_in(
        user!(%{encrypted_password: "$2a$04$" <> String.duplicate("phoenixa5fixture", 4)})
      )
      |> Plug.Conn.put_req_header("turbo-frame", "place-drawer")
      |> dispatch(DawarichWeb.Endpoint, :get, "/places/#{id}?extra=1")

    assert foreign.status == 404
    assert commands() == []
  end

  defp submit(session, path, params, frame \\ nil) do
    params = Map.put_new(params, "authenticity_token", RailsCsrf.masked_token(session))
    headers = [{"accept", @accept}] ++ if(frame, do: [{"turbo-frame", frame}], else: [])
    post_form(session, Plug.Conn.Query.encode(params), headers, path)
  end
end
