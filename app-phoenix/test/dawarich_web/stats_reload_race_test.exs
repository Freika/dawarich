defmodule DawarichWeb.StatsReloadRaceTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.StatsSeeds
  alias Dawarich.Test.NativeAdminUI
  @endpoint DawarichWeb.Endpoint

  setup do
    %{target: user} = NativeAdminUI.setup!()
    stat!(user.id, %{year: 2024, month: 3, distance: 1000, daily_distance: [[1, 1000]]})
    %{user: user}
  end

  test "a stats reload racing recalculation renders an authorized uncached chart", %{user: user} do
    {:ok, cache} = Dawarich.Test.NativePageCache.start()

    command = fn args ->
      result = Dawarich.Test.NativePageCache.command(cache, args)

      if hd(args) == "GET" do
        Dawarich.Repo.query!(
          "UPDATE stats SET distance=distance+1 WHERE user_id=$1 AND year=2024",
          [user.id],
          log: false
        )
      end

      result
    end

    install_cache(command)
    {:ok, view, _} = live(NativeAdminUI.conn(user), "/stats/2024/3")
    assert has_element?(view, "#monthly-stats-map[phx-hook=MapPreview]")
    assert :sys.get_state(view.pid).socket.assigns.data.data.stat.distance == 1002
    assert Dawarich.Test.NativePageCache.entries(cache) == %{}
  end

  test "a recalculation race cannot render a chart after the actor identity changes", %{
    user: user
  } do
    {:ok, view, _} = live(NativeAdminUI.conn(user), "/stats/2024/3")
    {:ok, cache} = Dawarich.Test.NativePageCache.start()
    {:ok, reads} = start_supervised({Agent, fn -> 0 end}, id: :reads)
    handler = "stats-reload-identity"

    :telemetry.attach(
      handler,
      [:dawarich, :repo, :query],
      fn _, _, metadata, _ ->
        if String.starts_with?(
             metadata.query,
             "SELECT month, distance, flight_distance, daily_distance, toponyms"
           ) do
          count = Agent.get_and_update(reads, fn count -> {count + 1, count + 1} end)

          if count == 2 do
            Dawarich.Repo.query!(
              "UPDATE users SET encrypted_password='changed-synthetic-identity' WHERE id=$1",
              [user.id],
              log: false
            )
          end
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    command = fn args ->
      result = Dawarich.Test.NativePageCache.command(cache, args)

      if hd(args) == "GET" do
        Dawarich.Repo.query!(
          "UPDATE stats SET distance=distance+1 WHERE user_id=$1 AND year=2024",
          [user.id],
          log: false
        )
      end

      result
    end

    install_cache(command)
    assert {:error, {:redirect, %{to: "/users/sign_in"}}} = render_patch(view, "/stats/2024/3")
    assert Agent.get(reads, & &1) == 2
    assert Dawarich.Test.NativePageCache.entries(cache) == %{}
  end

  defp install_cache(command) do
    previous = Application.get_env(:dawarich, :native_page_cache_command)
    Application.put_env(:dawarich, :native_page_cache_command, command)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :native_page_cache_command, previous),
        else: Application.delete_env(:dawarich, :native_page_cache_command)
    end)
  end
end
