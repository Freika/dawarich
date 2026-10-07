defmodule DawarichWeb.A12f3bI05Test do
  use Dawarich.DataCase, async: false
  alias Dawarich.Notifications
  alias Dawarich.Immich.VerifyWorker
  import Plug.Conn
  alias Dawarich.Test.{RailsUser, ImmichEnrichmentStub}

  @now ~U[2026-01-15 23:30:00Z]

  setup do
    user =
      RailsUser.insert!(%{
        id: 73505,
        email: "i05@test",
        settings: %{
          "immich_url" => "http://immich.test",
          "immich_api_key" => "synthetic",
          "locale" => "de"
        }
      })

    notification = Notifications.create!(Repo, user.id, :info, "Checking", "Pending")
    %{user: user, notification: notification}
  end

  @tag a12f3b_case: "I05a"
  test "Immich enrichment verifies bounded passes and publishes source notification", %{
    user: user,
    notification: id
  } do
    parent = self()

    http = fn :get, url, headers, nil, _skip ->
      send(parent, {:get, url, headers})

      {:ok, 200, [],
       Jason.encode!(%{"exifInfo" => %{"latitude" => 52.520000001, "longitude" => 13.405}})}
    end

    args = args(id, [asset("one")])
    assert apply(VerifyWorker, :run, [Repo, Oban, args, [http: http]]) == :ok

    assert_received {:get, "http://immich.test/api/assets/one",
                     [{"x-api-key", "synthetic"}, {"accept", "application/json"}]}

    assert [[0, title, content, nil]] =
             rows("SELECT kind,title,content,read_at FROM notifications WHERE id=$1", [id])

    assert title == "Ergebnisse der Immich-Standortaktualisierung"
    assert content == "Der gespeicherte Standort für 1 Foto wurde bestätigt."

    assert rows("SELECT count(*) FROM phoenix.notification_events WHERE notification_id=$1", [id]) ==
             [[2]]

    assert apply(VerifyWorker, :run, [Repo, Oban, args, [http: http]]) == :ok
    refute_received {:get, _, _}

    assert rows("SELECT count(*) FROM phoenix.notification_events WHERE notification_id=$1", [id]) ==
             [[2]]

    for response <- [
          {:ok, 403, [], "{}"},
          {:ok, 500, [], "{}"},
          {:error, :timeout},
          {:ok, 200, [], "invalid"},
          {:ok, 200, [], "null"},
          {:ok, 200, [], ~s({"exifInfo":[]})},
          {:ok, 200, [], ~s({"exifInfo":{"latitude":null,"longitude":null}})}
        ] do
      args =
        args(id, [asset("zero") |> Map.merge(%{"latitude" => 0, "longitude" => 0})])
        |> Map.put("pass", 3)

      assert apply(VerifyWorker, :run, [
               Repo,
               Oban,
               args,
               [http: fn _, _, _, _, _ -> response end]
             ]) == :ok

      assert [[1, content]] = rows("SELECT kind,content FROM notifications WHERE id=$1", [id])
      assert content =~ "1"
    end

    no_http = fn _, _, _, _, _ -> flunk("unexpected verification") end

    assert apply(VerifyWorker, :run, [Repo, Oban, args(-1, [asset("one")]), [http: no_http]]) ==
             :ok

    rows("UPDATE users SET settings=settings || $2::jsonb WHERE id=$1", [
      user.id,
      %{"immich_url" => "http://other.test"}
    ])

    assert apply(VerifyWorker, :run, [Repo, Oban, args(id, [asset("one")]), [http: no_http]]) ==
             :ok

    assert rows("SELECT kind FROM notifications WHERE id=$1", [id]) == [[1]]
    url = ImmichEnrichmentStub.start(self())

    rows("UPDATE users SET settings=settings || $2::jsonb WHERE id=$1", [
      user.id,
      %{"immich_url" => url}
    ])

    conn =
      Plug.Test.conn(:post, "/api/v1/immich/enrich")
      |> DawarichWeb.Api.Respond.prepare()
      |> assign(:api_user, user)
      |> assign(:api_params, %{
        "assets" => [Map.put(asset("submitted"), "ignored", "discard"), asset("reject")]
      })

    conn = apply(DawarichWeb.Api.ImmichEnrichController, :call, [conn, :create])
    assert conn.status == 200

    assert %{
             "enriched" => 0,
             "pending" => 1,
             "failed" => 1,
             "errors" => [%{"immich_asset_id" => "reject", "error" => "HTTP 403: Forbidden"}]
           } = Jason.decode!(conn.resp_body)

    assert_received {:immich_request, "PUT", "/api/assets/submitted", ["synthetic"], body}
    assert Jason.decode!(body) == %{"latitude" => 52.52, "longitude" => 13.405}
    assert_received {:immich_request, "PUT", "/api/assets/reject", ["synthetic"], _}

    assert [[accepted, _at, _inserted]] =
             rows("SELECT args,scheduled_at,inserted_at FROM oban.oban_jobs")

    assert accepted["assets"] == [asset("submitted")]
    assert accepted["immich_url"] == url
    assert accepted["pass"] == 1
    assert accepted["confirmed"] == 0
    assert accepted["unconfirmed"] == []

    assert rows(
             "SELECT scheduled_at = n.created_at + interval '10 seconds' FROM oban.oban_jobs j JOIN notifications n ON n.id=(j.args->>'notification_id')::bigint WHERE n.id=$1",
             [accepted["notification_id"]]
           ) == [[true]]

    assert apply(VerifyWorker, :run, [Repo, Oban, accepted, []]) == :ok
    assert_received {:immich_request, "GET", "/api/assets/submitted", ["synthetic"], ""}
    refute_received {:immich_request, "PUT", _, _, _}

    assert rows("SELECT kind FROM notifications WHERE id=$1", [accepted["notification_id"]]) == [
             [0]
           ]

    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [user.id])

    assert apply(VerifyWorker, :run, [Repo, Oban, args(id, [asset("one")]), [http: no_http]]) ==
             :ok

    assert apply(VerifyWorker, :args_from_command, [
             1,
             %{"notification_id" => id, "assets" => [], "immich_url" => url, "pass" => 0}
           ]) == {:error, "invalid_payload"}

    assert apply(VerifyWorker, :args_from_command, [2, %{}]) == {:error, "unsupported_version"}
    assert VerifyWorker.new(%{}).changes.max_attempts == 26
    assert commands() == []
  end

  @tag a12f3b_case: "I05b"
  test "Immich verifier continuation preserves pass and asset identity", %{notification: id} do
    assets = Enum.map(1..21, &asset(to_string(&1)))
    first = args(id, assets)

    http = fn :get, url, _, nil, _ ->
      exif =
        if String.ends_with?(url, "/1"),
          do: %{},
          else: %{"latitude" => 52.52, "longitude" => 13.405}

      {:ok, 200, [], Jason.encode!(%{"exifInfo" => exif})}
    end

    assert apply(VerifyWorker, :run, [Repo, Oban, first, [http: http, now: @now]]) == :ok

    assert [[child, at, _inserted]] =
             rows("SELECT args,scheduled_at,inserted_at FROM oban.oban_jobs ORDER BY id")

    assert Map.take(child, ~w(notification_id assets immich_url pass confirmed unconfirmed)) == %{
             "notification_id" => id,
             "assets" => [List.last(assets)],
             "immich_url" => "http://immich.test",
             "pass" => 1,
             "confirmed" => 19,
             "unconfirmed" => [hd(assets)]
           }

    assert NaiveDateTime.compare(at, DateTime.to_naive(@now)) == :eq
    assert apply(VerifyWorker, :run, [Repo, Oban, first, [http: http, now: @now]]) == :ok
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
    assert apply(VerifyWorker, :run, [Repo, Oban, child, [http: http, now: @now]]) == :ok

    assert [[retry, at, _inserted]] =
             rows(
               "SELECT args,scheduled_at,inserted_at FROM oban.oban_jobs ORDER BY id DESC LIMIT 1"
             )

    assert retry["assets"] == [hd(assets)]
    assert retry["confirmed"] == 20
    assert retry["pass"] == 2
    assert retry["unconfirmed"] == []
    assert NaiveDateTime.compare(at, @now |> DateTime.add(30) |> DateTime.to_naive()) == :eq
    assert apply(VerifyWorker, :run, [Repo, Oban, retry, [http: http, now: @now]]) == :ok
    [[last]] = rows("SELECT args FROM oban.oban_jobs ORDER BY id DESC LIMIT 1")
    assert last["pass"] == 3
    assert apply(VerifyWorker, :run, [Repo, Oban, last, [http: http, now: @now]]) == :ok
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[3]]
    assert [[1, content]] = rows("SELECT kind,content FROM notifications WHERE id=$1", [id])
    assert content =~ "20"
    assert content =~ "1"
    assert commands() == []
  end

  defp args(id, assets),
    do: %{
      "notification_id" => id,
      "assets" => assets,
      "immich_url" => "http://immich.test",
      "event_id" => Ecto.UUID.generate()
    }

  defp asset(id), do: %{"immich_asset_id" => id, "latitude" => 52.52, "longitude" => 13.405}
end
