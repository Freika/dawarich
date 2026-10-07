defmodule DawarichWeb.StandaloneHtmlPagesTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.{ApiGolden, RailsUser}
  @endpoint DawarichWeb.Endpoint

  setup do
    previous = Map.new(~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL), &{&1, System.get_env(&1)})
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true", "FORCE_SSL" => "false"})

    on_exit(fn ->
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    fixture = File.read!("test/fixtures/standalone/html_pages.json") |> Jason.decode!()

    for actor <- fixture["users"] do
      actor = Map.new(actor, fn {key, value} -> {String.to_atom(key), value} end)

      actor =
        Enum.reduce(~w(active_until created_at updated_at last_sign_in_at)a, actor, fn key, row ->
          Map.update!(row, key, fn value -> if value, do: NaiveDateTime.from_iso8601!(value) end)
        end)

      RailsUser.insert!(actor)
    end

    for table <-
          ~w(imports points tracks trips places tags notifications stats digests shared_links families family_memberships family_invitations family_location_requests achievement_progresses trip_sources) do
      for row <- fixture["rows"][table], do: ApiGolden.insert!(table, row)
    end

    Dawarich.State.put_registration_enabled(Repo, false)
    Dawarich.Jobs.Ownership.put!(Repo, "command:trips.calculate", :oban)
    %{fixture: fixture}
  end

  @tag :standalone_html_sweep
  test "every Rails HTML GET page and its captured form query renders natively without handback errors",
       %{fixture: fixture} do
    assert length(fixture["routes"]) > 70

    results =
      for route <- fixture["routes"] do
        result = request(fixture["user_id"], route["target"])

        if route["rails_status"] == 200 and route["html"] do
          {route["target"], result,
           route["native_status"] ||
             if(URI.parse(route["target"]).path == "/sidekiq", do: 302, else: 200)}
        end
      end

    failures =
      for {target, result, expected} <- Enum.reject(results, &is_nil/1),
          result != expected,
          do: {target, result, expected}

    assert failures == []
  end

  @tag :standalone_resources
  test "standalone public trip and track pages honor sharing flags privacy zones and revoked grants",
       %{fixture: fixture} do
    owner = fixture["user_id"]
    trip_link = "a9480100-0000-4000-8000-000000000001"
    track_link = "a9480100-0000-4000-8000-000000000002"

    Repo.query!(
      "INSERT INTO action_text_rich_texts(name,body,record_type,record_id,created_at,updated_at) VALUES('description','<div>Owner-only description</div>','Trip',94801,now(),now())"
    )

    for {id, type} <- [{trip_link, "trip"}, {track_link, "track"}] do
      conn = page(owner, "/s/" <> id)
      assert conn.status == 200
      assert String.contains?(conn.resp_body, ~s(data-controller="shared-trip-map")) == true

      assert String.contains?(conn.resp_body, ~s(data-shared-trip-map-link-id-value="#{id}")) ==
               true

      assert String.contains?(conn.resp_body, "synthetic-html-pages-key") == false
      if type == "trip", do: assert(conn.resp_body =~ "Owner-only description")
    end

    Repo.query!("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [
      trip_link,
      %{
        "show_route" => false,
        "show_stats" => false,
        "show_description" => false,
        "show_days" => false,
        "show_day_notes" => false,
        "show_photos" => false
      }
    ])

    hidden = page(owner, "/s/" <> trip_link)
    assert hidden.status == 200
    assert String.contains?(hidden.resp_body, "Owner-only description") == false
    assert String.contains?(hidden.resp_body, ~s(data-controller="shared-trip-map")) == false
    assert String.contains?(hidden.resp_body, "data-day-dot") == false

    Repo.query!("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [
      trip_link,
      %{"show_description" => false, "show_photos" => false}
    ])

    Repo.query!("UPDATE tags SET privacy_radius_meters=1000 WHERE id=94801")

    Repo.query!(
      "UPDATE places SET latitude=ST_Y(p.lonlat::geometry),longitude=ST_X(p.lonlat::geometry) FROM points p WHERE places.id=94801 AND p.id=94801"
    )

    Repo.query!(
      "INSERT INTO taggings(tag_id,taggable_type,taggable_id,created_at,updated_at) VALUES(94801,'Place',94801,now(),now())"
    )

    private = page(owner, "/s/" <> trip_link)
    assert private.status == 200
    assert String.contains?(private.resp_body, "No data") == true
    assert String.contains?(private.resp_body, "10:00") == false
    Repo.query!("UPDATE shared_links SET revoked_at=now() WHERE id=$1::text::uuid", [trip_link])
    assert page(owner, "/s/" <> trip_link).status == 404
    Repo.query!("UPDATE tracks SET user_id=94802 WHERE id=94801")
    missing = page(owner, "/s/" <> track_link)
    assert missing.status == 200
    assert String.contains?(missing.resp_body, ~s(data-controller="shared-trip-map")) == false
  end

  defp page(user_id, target) do
    RailsUser.signed_in(user_id)
    |> put_req_header("accept", "text/html")
    |> get(target)
  end

  defp request(user_id, target) do
    RailsUser.signed_in(user_id)
    |> put_req_header("accept", "text/html")
    |> get(target)
    |> Map.fetch!(:status)
  rescue
    error ->
      {:exception, error.__struct__,
       Enum.take(
         Enum.map(__STACKTRACE__, fn {module, function, _, location} ->
           {module, function, location[:line]}
         end),
         3
       )}
  end
end
