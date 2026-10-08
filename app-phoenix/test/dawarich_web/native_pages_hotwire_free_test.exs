defmodule DawarichWeb.NativePagesHotwireFreeTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsUser}

  @endpoint DawarichWeb.Endpoint
  @markers [
    "type=\"importmap\"",
    "/phoenix/js/",
    "data-turbo",
    "data-controller",
    "data-action=",
    "turbo-frame",
    "turbo-stream",
    "RailsStimulus",
    "rails_bridge"
  ]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    user = FrameSeeds.user!(8411)

    Repo.insert_all("tags", [
      %{
        id: 84111,
        user_id: user.id,
        name: "Gate",
        icon: "☕",
        color: "#123abc",
        created_at: ~N[2026-03-01 10:00:00],
        updated_at: ~N[2026-03-01 10:00:00]
      }
    ])

    %{user: user}
  end

  defp native_paths do
    DawarichWeb.Router.__routes__()
    |> Enum.filter(
      &match?(%{metadata: %{phoenix_live_view: {_, _, _, %{name: :native_pages}}}}, &1)
    )
    |> Enum.map(&String.replace(&1.path, ":id", "84111"))
  end

  test "every native page renders without Turbo, Stimulus or the importmap", %{user: user} do
    paths = native_paths()
    assert "/tags" in paths

    for path <- paths do
      conn = get(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)
      static = html_response(conn, 200)
      {:ok, _view, connected} = live(conn)

      for {html, phase} <- [{static, :static}, {connected, :connected}], marker <- @markers do
        refute html =~ marker, "#{path} (#{phase}) contains #{marker}"
      end

      assert static =~ "/native/app"
    end
  end
end
