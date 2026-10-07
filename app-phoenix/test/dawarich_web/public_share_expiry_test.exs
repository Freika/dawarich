defmodule DawarichWeb.PublicShareExpiryTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  import Dawarich.Test.StatsSeeds
  alias Dawarich.{Digests, Repo}
  alias Dawarich.Test.RailsUser

  @endpoint DawarichWeb.Endpoint
  @now ~U[2026-10-07 12:00:00Z]
  @oracle File.read!("test/fixtures/stats/public_share_expiry.json") |> Jason.decode!()

  setup do
    zone = System.get_env("TIME_ZONE")
    System.put_env("TIME_ZONE", "Europe/Berlin")

    on_exit(fn ->
      if zone, do: System.put_env("TIME_ZONE", zone), else: System.delete_env("TIME_ZONE")
    end)

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    user =
      RailsUser.insert!(%{
        id: 64128,
        email: "public-expiry@dawarich.test",
        settings: %{"timezone" => "Pacific/Pago_Pago"}
      })

    uuid = Ecto.UUID.generate()
    stat!(user.id, %{year: 2024, month: 3, sharing_uuid: Ecto.UUID.dump!(uuid)})
    digest!(user.id, %{year: 2024, sharing_uuid: Ecto.UUID.dump!(uuid)})
    %{uuid: uuid, user: user}
  end

  @tag public_expiry_pages: true
  test "public pages accept Rails stored expiry formats and refuse invalid or expired shares", %{
    uuid: uuid
  } do
    for text <- [
          "3026-01-01 12:00:00",
          "3026/01/01 12:00:00",
          "1 Jan 3026 12:00:00",
          "Jan 1, 3026 12:00 PM",
          "Thu, 01 Jan 3026 12:00:00 GMT",
          "30260101T120000Z",
          "01-Jan-3026 12:00:00",
          "3026.01.01 12:00:00",
          "3026-01-01T12:00:00+05:45"
        ] do
      assert_pages(uuid, text, 200)
    end

    for text <- [
          "2024-01-01 12:00:00",
          "2024/01/01",
          "nonsense",
          "2026-99-01",
          "",
          nil,
          123,
          false
        ] do
      assert_pages(uuid, text, 302)
    end

    assert_pages(uuid, "2026-10-07 14:00:00.123456", 200, ~U[2026-10-07 12:00:00.123456Z])
    assert_pages(uuid, "2026-10-07 14:00:00.123456", 302, ~U[2026-10-07 12:00:00.123457Z])
  end

  @tag public_expiry_parse: true
  test "stored expiry parsing preserves the Rails date corpus viewer timezone DST and fractions",
       %{uuid: uuid, user: user} do
    dst = File.read!("priv/rails_time_zone_dst.json") |> Jason.decode!()
    zones = File.read!("priv/rails_time_zones.json") |> Jason.decode!()
    assert dst["tzinfo_data_version"] == zones["tzinfo_data_version"]
    assert @oracle["tzinfo_data_version"] == zones["tzinfo_data_version"]
    now = ~U[2026-01-15 23:30:00Z]

    for row <- @oracle["cases"] do
      if row["error"] do
        assert Dawarich.SharingExpiry.parse(row["text"], now, row["zone"]) == nil
      else
        at = Dawarich.SharingExpiry.parse(row["text"], now, row["zone"])
        epoch = if at, do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
        assert epoch == row["epoch"], inspect(row)
        if at, do: assert(NaiveDateTime.to_iso8601(at) <> "Z" == row["utc"], inspect(row))
      end
    end

    for {text, expected} <- [
          {"2026-10-25 02:30:00", ~N[2026-10-25 00:30:00]},
          {"2026-03-29 02:30:00", ~N[2026-03-29 01:30:00]},
          {"3026-07-01 12:00:00", ~N[3026-07-01 11:00:00]},
          {"2100-07-01 12:00:00", ~N[2100-07-01 11:00:00]},
          {"2026-10-07T12:00:00.123456789Z", ~N[2026-10-07 12:00:00.123456]}
        ] do
      assert NaiveDateTime.compare(
               Dawarich.SharingExpiry.parse(text, @now, "Europe/Berlin"),
               expected
             ) == :eq
    end

    settings = %{"enabled" => true, "expiration" => "1h", "expires_at" => "2026-10-07 02:00:00"}

    for table <- ~w(stats digests),
        do:
          Repo.query!("UPDATE #{table} SET sharing_settings=$1 WHERE sharing_uuid=$2", [
            settings,
            Ecto.UUID.dump!(uuid)
          ])

    for kind <- ~w(month digest) do
      conn = RailsUser.signed_in(user.id) |> assign(:now, @now) |> get("/shared/#{kind}/#{uuid}")
      assert conn.status == 200
      assert (build_conn() |> assign(:now, @now) |> get("/shared/#{kind}/#{uuid}")).status == 302
    end

    for blank <- [nil, false, "", " \t", [], %{}] do
      assert Digests.Sharing.public?(%{settings | "expiration" => blank}, @now)
    end
  end

  @tag public_expiry_map: true
  test "public month map uses Rails stored expiry and keeps owner admission independent of login",
       %{uuid: uuid, user: user} do
    Repo.query!("UPDATE users SET settings=NULL, locked_at=$1 WHERE id=$2", [
      DateTime.to_naive(DateTime.utc_now()),
      user.id
    ])

    for text <- ["3026-01-01 12:00:00", "1 Jan 3026 12:00:00"] do
      Repo.query!("UPDATE stats SET sharing_settings=$1 WHERE user_id=$2", [
        %{"enabled" => true, "expiration" => "1h", "expires_at" => text},
        user.id
      ])

      assert {:ok, %{shared: true}} = Dawarich.MapApi.Hexagons.context(nil, %{"uuid" => uuid})
    end

    Repo.query!("UPDATE stats SET sharing_settings=$1 WHERE user_id=$2", [
      %{"enabled" => true, "expiration" => "1h", "expires_at" => "2024-01-01 12:00:00"},
      user.id
    ])

    assert {:error, 404, _} = Dawarich.MapApi.Hexagons.context(nil, %{"uuid" => uuid})
    wall = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.add(-10 * 3600)

    Repo.query!("UPDATE stats SET sharing_settings=$1 WHERE user_id=$2", [
      %{"enabled" => true, "expiration" => "1h", "expires_at" => NaiveDateTime.to_iso8601(wall)},
      user.id
    ])

    assert {:ok, %{shared: true}} =
             Dawarich.MapApi.Hexagons.context(%{timezone: "Pacific/Pago_Pago"}, %{"uuid" => uuid})

    assert {:error, 404, _} = Dawarich.MapApi.Hexagons.context(nil, %{"uuid" => uuid})
    Repo.query!("UPDATE users SET deleted_at=$1 WHERE id=$2", [DateTime.to_naive(@now), user.id])
    assert {:error, 404, _} = Dawarich.MapApi.Hexagons.context(nil, %{"uuid" => uuid})
  end

  defp assert_pages(uuid, text, status, now \\ @now) do
    settings = %{"enabled" => true, "expiration" => "1h", "expires_at" => text}

    for table <- ~w(stats digests),
        do:
          Repo.query!("UPDATE #{table} SET sharing_settings=$1 WHERE sharing_uuid=$2", [
            settings,
            Ecto.UUID.dump!(uuid)
          ])

    for kind <- ~w(month digest) do
      conn = build_conn() |> assign(:now, now) |> get("/shared/#{kind}/#{uuid}")
      assert conn.status == status, inspect({kind, text, now, conn.status})

      if status == 302,
        do: assert(get_resp_header(conn, "location") == ["http://www.example.com/"])
    end
  end
end
