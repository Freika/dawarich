defmodule DawarichWeb.PublicReportDeliveryTest do
  use Dawarich.DataCase, async: true
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Test.{RailsUser, StatsSeeds}
  @endpoint DawarichWeb.Endpoint
  @now ~U[2026-10-07 12:00:00Z]

  setup do
    user = RailsUser.insert!(%{id: 19021, email: "report-delivery@example.invalid"})
    uuid = Ecto.UUID.generate()

    share = %{
      sharing_uuid: Ecto.UUID.dump!(uuid),
      sharing_settings: %{
        "enabled" => true,
        "expiration" => "1h",
        "expires_at" => "2026-10-07T13:00:00+00:00"
      }
    }

    StatsSeeds.digest!(user.id, Map.put(share, :year, 2024))
    StatsSeeds.stat!(user.id, Map.merge(share, %{year: 2024, month: 3}))
    %{uuid: uuid}
  end

  for kind <- [:digest, :month] do
    @tag review_delivery: true
    test "public #{kind} projection refreshes its clock after preparation", %{uuid: uuid} do
      opts = [now: @now, clock: &clock/0, self_hosted: true]
      assert {:ok, _} = Dawarich.Sharing.Pages.report(unquote(kind), uuid, opts)

      assert {:error, :not_found} =
               Dawarich.Sharing.Pages.report(unquote(kind), uuid, opts ++ [after_read: &expire/0])
    end

    @tag review_delivery: true
    test "routed public #{kind} HTTP refreshes admission after HTML preparation", %{uuid: uuid} do
      path = "/shared/#{unquote(kind)}/#{uuid}"
      assert build_conn() |> clock_conn() |> get(path) |> Map.get(:status) == 200

      conn =
        build_conn()
        |> clock_conn()
        |> put_private(:dawarich_before_delivery, &expire/0)
        |> get(path)

      assert conn.status == 302
      assert conn.resp_body == ""
    end
  end

  @tag review_delivery: true
  test "native digest HTTP refreshes admission after HTML preparation", %{uuid: uuid} do
    request = fn hook ->
      build_conn("GET", "/shared/digest/#{uuid}")
      |> Map.merge(%{params: %{}, path_params: %{"uuid" => uuid}})
      |> clock_conn()
      |> assign(:locale, "en")
      |> assign(:base_url, "http://www.example.com")
      |> assign(:current_user, nil)
      |> assign(:self_hosted, true)
      |> put_private(:dawarich_before_delivery, hook)
      |> DawarichWeb.NativePublicPage.call(:digest)
    end

    assert request.(fn -> :ok end).status == 200
    conn = request.(&expire/0)
    assert conn.status == 302
    assert conn.resp_body == ""
  end

  @tag review_delivery: true
  test "native digest HTTP refuses sharing revocation after HTML preparation", %{uuid: uuid} do
    hook = fn -> rows("UPDATE digests SET sharing_settings='{}' WHERE user_id=19021") end

    conn =
      build_conn("GET", "/shared/digest/#{uuid}")
      |> Map.merge(%{params: %{}, path_params: %{"uuid" => uuid}})
      |> clock_conn()
      |> assign(:locale, "en")
      |> assign(:base_url, "http://www.example.com")
      |> assign(:current_user, nil)
      |> assign(:self_hosted, true)
      |> put_private(:dawarich_before_delivery, hook)
      |> DawarichWeb.NativePublicPage.call(:digest)

    assert conn.status == 302
    assert conn.resp_body == ""
  end

  defp clock_conn(conn),
    do: conn |> assign(:now, @now) |> put_private(:dawarich_clock, &clock/0)

  defp clock, do: Process.get(:public_delivery_clock, @now)
  defp expire, do: Process.put(:public_delivery_clock, DateTime.add(@now, 2, :hour))
end
