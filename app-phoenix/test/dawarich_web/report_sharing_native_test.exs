defmodule DawarichWeb.ReportSharingNativeTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.StatsSeeds
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)

    user =
      RailsUser.insert!(%{
        id: 154_071,
        email: "native-report@example.invalid",
        plan: 2,
        settings: %{"timezone" => "UTC"}
      })

    stat!(user.id, %{year: 2024, month: 3})
    digest!(user.id, %{year: 2024})
    %{user: Accounts.get(user.id)}
  end

  defp open(user, path),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  defp values(view), do: :sys.get_state(view.pid).socket.assigns.page

  defp submit(view, enabled, expiration \\ "24h"),
    do:
      render_submit(view, "report_sharing_update", %{
        "enabled" => enabled,
        "expiration" => expiration
      })

  test "report and achievement sharing entrypoints perform scoped native writes and return safely",
       c do
    for {path, back} <- [
          {"/stats/2024/3/sharing", "/stats/2024/3"},
          {"/digests/2024/sharing", "/digests/2024"},
          {"/achievements/country_de/sharing", "/achievements/country_de"}
        ] do
      {:ok, view, _} = open(c.user, path <> "?return_to=https%3A%2F%2Fevil.example%2F")
      assert has_element?(view, "a[href='#{back}']")
      refute has_element?(view, "[data-controller],turbo-frame")
      submit(view, "1")
      assert is_binary(values(view).uuid)
      assert has_element?(view, "a[data-public-share]")
      assert has_element?(view, "#report-share-copy[data-clipboard-url=true]")

      foreign =
        RailsUser.insert!(%{id: 154_072, email: "foreign-report@example.invalid", plan: 2})

      assert {:error, _} =
               Dawarich.Sharing.change(
                 Dawarich.Accounts.Scope.for_user(Accounts.get(foreign.id), "en"),
                 :sys.get_state(view.pid).socket.assigns.resource,
                 :update,
                 %{"enabled" => "0"}
               )

      assert has_element?(view, "a[data-public-share]")
      submit(view, "0")
      refute has_element?(view, "a[data-public-share]")
      Repo.query!("DELETE FROM users WHERE id=154072", [], log: false)
    end
  end

  test "monthly expiry presets and digest disable preserve public visibility", c do
    {:ok, month, _} = open(c.user, "/stats/2024/3/sharing")

    for {preset, hours} <- [{"1h", 1}, {"12h", 12}, {"24h", 24}] do
      before = DateTime.utc_now()
      submit(month, "1", preset)
      settings = values(month).settings
      assert settings["expiration"] == preset
      {:ok, due, _} = DateTime.from_iso8601(settings["expires_at"])
      assert DateTime.diff(due, before) in (hours * 3600 - 2)..(hours * 3600 + 2)
      assert Dawarich.Digests.Sharing.public?(settings, before, "UTC")
      refute Dawarich.Digests.Sharing.public?(settings, DateTime.add(due, 1), "UTC")
    end

    {:ok, digest, _} = open(c.user, "/digests/2024/sharing")
    submit(digest, "1", "12h")
    uuid = values(digest).uuid
    assert values(digest).settings["enabled"]
    submit(digest, "0")
    assert values(digest).uuid == uuid

    assert values(digest).settings == %{
             "enabled" => false,
             "expiration" => nil,
             "expires_at" => nil
           }

    refute Dawarich.Digests.Sharing.public?(values(digest).settings, DateTime.utc_now(), "UTC")
  end
end
