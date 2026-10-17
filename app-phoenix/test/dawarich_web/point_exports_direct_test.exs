defmodule DawarichWeb.PointExportsDirectTest do
  use Dawarich.IngestCase, async: false

  import Dawarich.Test.RailsFormRequests
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf

  @body "start_at=2024-03-01+00%3A00%3A00+UTC&end_at=2024-03-31+00%3A00%3A00+UTC&file_format=gpx"
  @key "command:exports.points"

  setup do
    Ownership.put!(Repo, @key, :oban)

    RailsUser.insert!(%{
      id: 7441,
      email: "direct-export@example.test",
      settings: %{"timezone" => "America/New_York"}
    })

    session = RailsUser.session(7441)
    saved = System.get_env("TIME_ZONE")
    System.delete_env("TIME_ZONE")

    on_exit(fn ->
      if saved, do: System.put_env("TIME_ZONE", saved), else: System.delete_env("TIME_ZONE")
    end)

    %{session: session, token: RailsCsrf.masked_token(session), upstream: upstream!()}
  end

  defp post(ctx), do: post_form(ctx.session, @body, [{"x-csrf-token", ctx.token}])

  defp outbox,
    do:
      Repo.query!(
        "SELECT command_version, payload, aggregate_id, dedupe_key, metadata, state FROM job_outbox"
      ).rows

  for {zone, want} <- [
        {"America/New_York", "America/New_York"},
        {"Eastern Time (US & Canada)", "America/New_York"},
        {"UTC", "Etc/UTC"},
        {"Berlin", "Europe/Berlin"},
        {"Asia/Tokyo", "Asia/Tokyo"},
        {nil, "Etc/UTC"},
        {"Not/AZone", "Europe/Berlin"}
      ] do
    test "Oban-owned POST captures request zone #{inspect(zone)} directly", ctx do
      Repo.query!("UPDATE users SET settings = $1 WHERE id = 7441", [
        %{"timezone" => unquote(zone)}
      ])

      assert post(ctx).status == 302
      assert commands() == []
      assert [[id]] = Repo.query!("SELECT id FROM exports").rows

      assert outbox() == [
               [
                 2,
                 %{"export_id" => id, "user_id" => 7441, "time_zone" => unquote(want)},
                 id,
                 "points-export:#{id}",
                 %{"producer" => "Phoenix ExportsCreate"},
                 "pending"
               ]
             ]

      Repo.query!(
        "UPDATE users SET settings = '{\"timezone\":\"Pacific/Auckland\"}'::jsonb WHERE id = 7441"
      )

      assert [[%{"time_zone" => unquote(want)} | _]] =
               Repo.query!("SELECT payload FROM job_outbox").rows
    end
  end

  test "missing and invalid settings use the configured process fallback", ctx do
    System.put_env("TIME_ZONE", "Asia/Tokyo")

    for zone <- [nil, "Not/AZone"] do
      Repo.query!("UPDATE users SET settings = $1 WHERE id = 7441", [%{"timezone" => zone}])
      assert post(ctx).status == 302
    end

    assert Enum.all?(outbox(), fn [2, payload | _] -> payload["time_zone"] == "Asia/Tokyo" end)
    assert length(outbox()) == 2
    assert commands() == []
  end

  test "an Oban-owned POST works without the Rails reverse table", ctx do
    Repo.query!("DROP TABLE phoenix.rails_commands")
    assert post(ctx).status == 302
    assert length(outbox()) == 1
    assert Repo.query!("SELECT count(*) FROM exports").rows == [[1]]
  end

  test "outbox failure rolls back the native export and returns the source error", ctx do
    Repo.query!("DROP TABLE job_outbox")

    conn = post(ctx)
    assert conn.status == 422
    assert conn.resp_body == ""
    assert Plug.Conn.get_resp_header(conn, "location") == ["http://www.example.com/exports"]

    assert Repo.query!("SELECT count(*) FROM exports").rows == [[0]]
    assert commands() == []
  end

  for owner <- [:sidekiq, :missing] do
    test "#{owner} native producer ownership refuses without a Rails handback", ctx do
      case unquote(owner) do
        :sidekiq -> Ownership.put!(Repo, @key, :sidekiq)
        :missing -> Repo.query!("DELETE FROM phoenix.job_owners WHERE key = $1", [@key])
      end

      assert post(ctx).status == 422
      assert Repo.query!("SELECT id FROM exports").rows == []
      assert commands() == []
      assert outbox() == []
    end
  end

  test "native export POST fails closed when producer ownership is unavailable", ctx do
    Ownership.put!(Repo, @key, :sidekiq)
    assert post(ctx).status == 422
    assert commands() == []
    assert outbox() == []
    assert Repo.query!("SELECT count(*) FROM exports", [], log: false).rows == [[0]]
  end

  test "native export POST refuses its stale actor after form admission", ctx do
    actor = Dawarich.Accounts.get(7441)

    conn =
      Phoenix.ConnTest.build_conn(:post, "/exports")
      |> Plug.Conn.assign(:current_user, actor)
      |> Plug.Conn.assign(:rails_session, ctx.session)
      |> Plug.Conn.assign(:api_params, %{
        "start_at" => "2024-03-01",
        "end_at" => "2024-03-31",
        "file_format" => "gpx"
      })

    Repo.query!("UPDATE users SET locked_at=now() WHERE id=7441", [], log: false)
    assert DawarichWeb.ExportsCreate.call(conn, :create).status == 422
    assert Repo.query!("SELECT count(*) FROM exports", [], log: false).rows == [[0]]
  end

  test "retained export POST refuses invalid CSRF without a Rails replay", ctx do
    conn = post_form(ctx.session, @body, [{"x-csrf-token", String.reverse(ctx.token)}])
    assert conn.status == 422
    assert Repo.query!("SELECT count(*) FROM exports", [], log: false).rows == [[0]]
    assert commands() == []
    assert outbox() == []
  end
end
