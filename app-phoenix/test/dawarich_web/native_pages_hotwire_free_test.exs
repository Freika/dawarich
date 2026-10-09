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
    "rails_bridge",
    " inert",
    "data-rails-form-ready"
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

    url = Dawarich.Test.NativeIntegrationStub.start!()
    {:ok, key} = Dawarich.ActiveRecordEncryption.key()

    Repo.insert_all("trip_sources", [
      %{
        id: 84111,
        user_id: user.id,
        provider: "trek",
        base_url: url,
        api_key: Dawarich.ActiveRecordEncryption.encrypt("synthetic-trek", key),
        status: 0,
        importing: false,
        created_at: ~N[2026-03-01 10:00:00],
        updated_at: ~N[2026-03-01 10:00:00]
      }
    ])

    %{user: user}
  end

  defp unlabelled(html) do
    doc = LazyHTML.from_document(html)

    for control <-
          doc
          |> LazyHTML.query(
            "input:not([type=hidden]):not([type=submit]):not([type=button]), select, textarea"
          )
          |> LazyHTML.filter(":not(label *):not([aria-label]):not([aria-labelledby])"),
        id = List.first(LazyHTML.attribute(control, "id")),
        is_nil(id) or Enum.count(LazyHTML.query(doc, ~s(label[for="#{id}"]))) != 1,
        do: LazyHTML.to_html(control)
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

    saving =
      for path <- paths do
        conn = get(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)
        static = html_response(conn, 200)
        {:ok, _view, connected} = live(conn)

        for {html, phase} <- [{static, :static}, {connected, :connected}], marker <- @markers do
          refute html =~ marker, "#{path} (#{phase}) contains #{marker}"
        end

        for html <- [static, connected],
            do:
              assert(unlabelled(html) == [], "#{path} has unlabelled or doubly labelled controls")

        assert static =~ "/native/app"
        assert static =~ ~r/<script[^>]*phx-track-static[^>]*\/native\/app/

        forms = for html <- [static, connected], html =~ ~s(phx-submit="save"), do: html

        for html <- forms,
            do:
              assert(html =~ ~r/<button[^>]*type="submit"[^>]*phx-disable-with/, "#{path} submit")

        forms != []
      end

    assert Enum.count(saving, & &1) >= 2
  end
end
