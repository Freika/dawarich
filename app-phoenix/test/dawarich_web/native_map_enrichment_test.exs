defmodule DawarichWeb.NativeMapEnrichmentTest do
  use Dawarich.DataCase, async: true
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Maps}
  alias Dawarich.Photos.ScopedEnrichment
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.MapLive.EnrichmentCommands
  @endpoint DawarichWeb.Endpoint
  @now ~U[2026-10-10 10:00:00Z]

  defmodule Host do
    use Phoenix.LiveView

    def mount(_params, session, socket) do
      {:ok,
       assign(socket,
         current_scope: Maps.principal(Accounts.get(session["user_id"]), "en"),
         enrichment_scanner: Agent.get(session["scanner"], & &1)
       )}
    end

    def handle_event("range", _params, socket), do: {:noreply, EnrichmentCommands.cancel(socket)}

    def handle_event(event, params, socket),
      do: EnrichmentCommands.handle_event(event, params, socket)

    def handle_async(name, result, socket),
      do: EnrichmentCommands.handle_async(name, result, socket)

    def render(assigns) do
      ~H"""
      <DawarichWeb.NativeMapEnrichment.tool
        enrichment={assigns[:enrichment]}
        start_date="2026-01-01"
        end_date="2026-01-31"
        locale="en"
      />
      """
    end
  end

  setup do
    [pro, lite] = for plan <- [1, 0], do: account!(plan)
    %{pro: pro, lite: lite}
  end

  test "non-Pro or revoked scope cannot scan or enrich", c do
    lite = Maps.principal(c.lite, "en")
    pro = Maps.principal(c.pro, "en")
    opts = [self_hosted?: false, now: @now]

    assert {:error, :pro_required} = ScopedEnrichment.scan(lite, %{}, opts)
    assert {:error, :pro_required} = ScopedEnrichment.enrich(lite, [], opts)
    assert {:ok, %{"error" => missing, "matches" => []}} = ScopedEnrichment.scan(pro, %{}, opts)
    assert missing =~ "URL"

    rows("UPDATE users SET encrypted_password=$1 WHERE id=$2", [
      String.duplicate("rotated", 10),
      c.pro.id
    ])

    assert {:error, :stale_session} = ScopedEnrichment.scan(pro, %{}, opts)
    assert {:error, :stale_session} = ScopedEnrichment.enrich(pro, [], opts)
    assert rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.pro.id]) == [[0]]
  end

  test "old scan reply cannot restore markers after range change", c do
    test_pid = self()

    scanner = fn _scope, params ->
      send(test_pid, {:scanning, params["start_date"], self()})
      if params["start_date"] == "2026-01-01", do: receive(do: (:release -> :ok))

      {:ok,
       %{
         "matches" => [%{"immich_asset_id" => params["start_date"]}],
         "total_matched" => 1,
         "total_without_geodata" => 1
       }}
    end

    agent = start_supervised!({Agent, fn -> scanner end})

    {:ok, view, _} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host,
        session: %{"user_id" => c.pro.id, "scanner" => agent}
      )

    render_hook(view, "enrichment:scan", %{"start_date" => "2026-01-01"})
    assert_receive {:scanning, "2026-01-01", slow}
    render_hook(view, "range", %{})
    render_hook(view, "enrichment:scan", %{"start_date" => "2026-02-01"})
    assert_receive {:scanning, "2026-02-01", fast}
    finished(fast)

    assert_push_event(view, "enrichment:matches", %{
      matches: [%{"immich_asset_id" => "2026-02-01"}]
    })

    send(slow, :release)
    finished(slow)
    render(view)
    refute_push_event(view, "enrichment:matches", %{})
    assert render(view) =~ ~s(data-enrichment-matched="1")
  end

  defp finished(pid) do
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2_000
  end

  defp account!(plan) do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "enrich-#{id}@dawarich.test",
      plan: plan,
      status: 1,
      settings: %{"timezone" => "UTC"}
    })

    Accounts.get(id)
  end
end
