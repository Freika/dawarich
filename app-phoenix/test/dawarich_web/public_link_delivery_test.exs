defmodule DawarichWeb.PublicLinkDeliveryTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Test.{RailsUser, FrameSeeds, StatsSeeds}
  @endpoint DawarichWeb.Endpoint

  setup do
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    old = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if old, do: System.put_env("DAWARICH_RAILS", old), else: System.delete_env("DAWARICH_RAILS")
    end)

    user = RailsUser.insert!(%{id: 19022, email: "link-delivery@example.invalid"})
    uuid = Ecto.UUID.generate()

    rows(
      "INSERT INTO trips(id,user_id,name,started_at,ended_at,created_at,updated_at) VALUES(19022,19022,'Public trip','2026-01-01','2026-01-02',now(),now())"
    )

    FrameSeeds.track!(user.id, 19022, %{
      start_at: ~N[2026-01-01 00:00:00],
      end_at: ~N[2026-01-02 00:00:00]
    })

    rows(
      "INSERT INTO shared_links(id,user_id,resource_type,resource_id,name,settings,created_at,updated_at) VALUES($1::text::uuid,19022,0,19022,'Public link',$2,now(),now())",
      [uuid, %{"show_days" => false, "start_date" => "2026-01-01", "end_date" => "2026-01-02"}]
    )

    FrameSeeds.point!(user.id, 190_220, DateTime.to_unix(~U[2024-03-05 12:00:00Z]))

    StatsSeeds.stat!(user.id, %{
      year: 2024,
      month: 3,
      sharing_uuid: Ecto.UUID.dump!(uuid),
      sharing_settings: %{"enabled" => true, "expiration" => nil}
    })

    %{uuid: uuid}
  end

  for {kind, type} <- [{:trip, 0}, {:track, 1}, {:timeline, 2}, {:live, 3}] do
    @tag review_delivery: true
    test "public #{kind} shared-link HTTP refuses revocation after document preparation", %{
      uuid: uuid
    } do
      rows("UPDATE shared_links SET resource_type=$1 WHERE user_id=19022", [unquote(type)])
      assert get(build_conn(), "/s/#{uuid}").status == 200

      conn =
        build_conn()
        |> put_private(:dawarich_before_delivery, &revoke/0)
        |> get("/s/#{uuid}")

      assert conn.status == 404
      refute conn.resp_body =~ "Public trip"
    end
  end

  for action <- ~w(trip points route photos) do
    @tag review_delivery: true
    test "public shared #{action} API refuses revocation after payload preparation", %{uuid: uuid} do
      path = "/api/v1/shared/#{uuid}/#{unquote(action)}"
      assert get(build_conn(), path).status == 200

      conn = build_conn() |> put_private(:dawarich_before_delivery, &revoke/0) |> get(path)
      assert conn.status == 404
      assert Jason.decode!(conn.resp_body) == %{"error" => "not_found"}
    end
  end

  @tag review_delivery: true
  test "public shared live points API refuses revocation after payload preparation", %{uuid: uuid} do
    rows("UPDATE shared_links SET resource_type=3 WHERE user_id=19022")
    path = "/api/v1/shared/#{uuid}/points"
    assert get(build_conn(), path).status == 200
    conn = build_conn() |> put_private(:dawarich_before_delivery, &revoke/0) |> get(path)
    assert conn.status == 404
    assert Jason.decode!(conn.resp_body) == %{"error" => "not_found"}
  end

  for path <- ~w(hexagons hexagons/bounds) do
    @tag review_delivery: true
    test "public month #{path} API refuses revocation before response delivery", %{uuid: uuid} do
      path = "/api/v1/maps/#{unquote(path)}?uuid=#{uuid}"
      assert get(build_conn(), path).status == 200
      hook = fn -> rows("UPDATE stats SET sharing_settings='{}' WHERE user_id=19022") end
      conn = build_conn() |> put_private(:dawarich_before_delivery, hook) |> get(path)
      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] =~ "Shared stats"
    end
  end

  for action <- [:photos, :thumbnail] do
    @tag review_delivery: true
    test "public cached photo #{action} delivery refuses revocation after preparation", %{
      uuid: uuid
    } do
      listener = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])
      assert {:ok, listener} = listener
      {:ok, {_, port}} = :inet.sockname(listener)

      settings = %{
        "timezone" => "UTC",
        "immich_url" => "http://127.0.0.1:#{port}",
        "immich_api_key" => "synthetic-provider"
      }

      rows("UPDATE users SET settings=$1 WHERE id=19022", [settings])

      rows(
        "UPDATE shared_links SET settings=jsonb_set(settings,'{show_photos}','true') WHERE user_id=19022"
      )

      link = Dawarich.SharedLinks.active(uuid, DateTime.utc_now())
      {from, to} = Dawarich.SharedApi.Photos.grant_context(link).range
      key = "photos_search/19022/v2/#{from}/#{to}"

      photo =
        Map.new(
          ~w(id latitude longitude localDateTime capturedAt originalFileName city state country type orientation source),
          &{&1, nil}
        )
        |> Map.merge(%{
          "id" => "synthetic",
          "source" => "immich",
          "latitude" => 1.0,
          "longitude" => 1.0,
          "capturedAt" => "2026-01-01T12:00:00Z"
        })

      assert {:ok, "OK"} = Dawarich.Photos.ProviderCache.put(key, [photo], 60)
      assert match?({:ok, [_]}, Dawarich.Photos.ProviderCache.get(key))
      assert length(Dawarich.SharedApi.Photos.gallery(link)) == 1

      server =
        Task.async(fn ->
          for _ <- 1..2 do
            {:ok, socket} = :gen_tcp.accept(listener)
            {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

            :ok =
              :gen_tcp.send(
                socket,
                "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: close\r\n\r\nsynthetic-jpg"
              )

            :gen_tcp.close(socket)
          end
        end)

      path =
        if unquote(action) == :photos,
          do: "/api/v1/shared/#{uuid}/photos",
          else: "/api/v1/shared/#{uuid}/photos/synthetic/thumbnail?source=immich"

      try do
        positive = get(build_conn(), path)
        assert positive.status == 200

        if unquote(action) == :thumbnail,
          do: assert(positive.resp_body == "synthetic-jpg"),
          else: assert(length(Jason.decode!(positive.resp_body)) == 1)

        conn = build_conn() |> put_private(:dawarich_before_delivery, &revoke/0) |> get(path)
        assert conn.status == 404
        assert Jason.decode!(conn.resp_body) == %{"error" => "not_found"}
      after
        Task.shutdown(server, :brutal_kill)
        :gen_tcp.close(listener)

        Dawarich.Redis.cache_command([
          "UNLINK",
          key,
          Dawarich.SharedApi.Closure.photo_ids_key(link)
        ])
      end
    end
  end

  defp revoke, do: rows("UPDATE shared_links SET revoked_at=now() WHERE user_id=19022")
end
