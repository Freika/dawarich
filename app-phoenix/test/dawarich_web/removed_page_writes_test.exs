defmodule DawarichWeb.RemovedPageWritesTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser

  @endpoint DawarichWeb.Endpoint
  @removed [
    {:patch, "/settings/general", "locale=de&timezone=Asia%2FTokyo"},
    {:put, "/settings/general", "locale=de"},
    {:post, "/settings/general", "_method=patch&locale=de"},
    {:post, "/settings/general/verify_supporter", "supporter_email=fan%40example.test"},
    {:post, "/settings/general/test_email", ""},
    {:patch, "/settings/visits", "settings%5Bvisit_radius_meters%5D=75"},
    {:put, "/settings/visits", "settings%5Bvisit_radius_meters%5D=75"},
    {:post, "/settings/visits", "_method=patch&settings%5Bvisit_radius_meters%5D=75"},
    {:post, "/visits/redetections", ""},
    {:patch, "/settings/integrations", "settings%5Bimmich_url%5D=http%3A%2F%2Fimmich.test"},
    {:put, "/settings/integrations", "settings%5Bimmich_url%5D=http%3A%2F%2Fimmich.test"},
    {:post, "/settings/integrations", "_method=patch&settings%5Bimmich_url%5D=x"},
    {:post, "/settings/general.html", "_method=patch&locale=de"},
    {:post, "/settings/trek_sources", "trip_source%5Bbase_url%5D=http%3A%2F%2Ftrek.test"},
    {:post, "/settings/trek_sources.html", "trip_source%5Bbase_url%5D=http%3A%2F%2Ftrek.test"},
    {:post, "/settings/trek_sources/1", "_method=delete"},
    {:post, "/settings/trek_sources/1/sync", ""},
    {:post, "/settings/trek_sources/1/import_trips", ""},
    {:post, "/settings/trek_sources/1/sync.html", ""},
    {:post, "/settings/trek_sources/1/import_trips.html", ""},
    {:delete, "/settings/trek_sources/1", ""},
    {:post, "/settings/generate_api_key", ""},
    {:get, "/settings/users/export", ""},
    {:post, "/settings/users/import", "archive=signed"},
    {:post, "/admin/settings", "section=points&instance_settings%5Bstore_geodata%5D=false"},
    {:patch, "/admin/settings", "section=points&instance_settings%5Bstore_geodata%5D=false"},
    {:put, "/admin/settings", "section=points&instance_settings%5Bstore_geodata%5D=false"},
    {:post, "/admin/settings",
     "_method=patch&section=points&instance_settings%5Bstore_geodata%5D=false"},
    {:post, "/admin/settings.html", "_method=patch&section=points"},
    {:post, "/admin/settings/test_geocoding", ""},
    {:post, "/admin/settings/test_map_matching", ""},
    {:post, "/settings/users",
     "user%5Bemail%5D=new%40example.invalid&user%5Bpassword%5D=synthetic-pass-1&user%5Bpassword_confirmation%5D=synthetic-pass-1"},
    {:post, "/settings/users/9896", "_method=put&user%5Badmin%5D=1"},
    {:patch, "/settings/users/9896", "user%5Badmin%5D=1"},
    {:put, "/settings/users/9896", "user%5Badmin%5D=1"},
    {:post, "/settings/users/9896", "_method=delete"},
    {:delete, "/settings/users/9896", ""},
    {:post, "/settings/users/9896/regenerate_api_key", ""},
    {:post, "/settings/users/9896/send_password_reset", ""},
    {:post, "/settings/users/update_registration_settings", "enabled=1"},
    {:patch, "/settings/users/update_registration_settings", "enabled=1"},
    {:patch, "/settings/background_jobs", "settings%5Bvisits_suggestions_enabled%5D=true"}
  ]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    RailsUser.insert!(%{
      id: 9895,
      email: "removed-writes@dawarich.test",
      api_key: "removed-writes-key",
      admin: true,
      settings: %{"timezone" => "UTC", "locale" => "en"}
    })

    RailsUser.insert!(%{
      id: 9896,
      email: "removed-writes-target@dawarich.test",
      api_key: "removed-writes-target-key",
      settings: %{"timezone" => "UTC", "locale" => "en"}
    })

    :ok
  end

  defp send_request(method, path, body) do
    session = RailsUser.session(9895)

    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("accept", "text/html")
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("x-csrf-token", DawarichWeb.RailsCsrf.masked_token(session))
    |> dispatch(@endpoint, method, path, body)
  end

  defp footprint,
    do:
      Repo.query!(
        "SELECT (SELECT to_jsonb(u) - 'updated_at' FROM users u WHERE id=9895), (SELECT to_jsonb(u) - 'updated_at' FROM users u WHERE id=9896), (SELECT count(*) FROM users), (SELECT count(*) FROM instance_settings), (SELECT count(*) FROM job_outbox), (SELECT count(*) FROM oban.oban_jobs), (SELECT count(*) FROM phoenix.rails_commands), (SELECT count(*) FROM active_storage_blobs)"
      ).rows

  test "every removed page-write path answers like an unknown page and changes nothing" do
    missing = send_request(:post, "/no-such-page", "")
    assert missing.status == 404

    for {method, path, body} <- @removed do
      before = footprint()
      response = send_request(method, path, body)

      assert {response.status, response.resp_body} == {missing.status, missing.resp_body},
             "#{method} #{path}"

      assert footprint() == before, "#{method} #{path}"
    end
  end
end
