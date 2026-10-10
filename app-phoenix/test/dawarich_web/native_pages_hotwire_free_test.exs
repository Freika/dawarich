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
    "data-rails-form-ready",
    "onclick=",
    "onchange="
  ]
  @sessions [:native_pages, :native_admin, :native_background]
  @secret_free_change_forms ["integration-settings"]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    user = FrameSeeds.user!(8411)
    Repo.query!("UPDATE users SET admin = true WHERE id = 8411")

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

  defp password_forms_with_change(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("form[phx-change]")
    |> Enum.reject(&(List.first(LazyHTML.attribute(&1, "id")) in @secret_free_change_forms))
    |> Enum.filter(&(LazyHTML.query(&1, "input[type=password]") |> Enum.count() > 0))
  end

  defp native_paths do
    DawarichWeb.Router.__routes__()
    |> Enum.filter(fn
      %{metadata: %{phoenix_live_view: {_, _, _, %{name: name}}}} -> name in @sessions
      _ -> false
    end)
    |> Enum.map(fn %{path: path} ->
      id = if String.starts_with?(path, "/settings/users"), do: "8411", else: "84111"
      String.replace(path, ":id", id)
    end)
  end

  test "native admin and background pages retain exactly one accessible label per control", %{
    user: user
  } do
    previous = Map.new(~w(SELF_HOSTED DAWARICH_RAILS), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    RailsUser.insert!(%{
      id: 8412,
      email: "native-label-target@example.invalid",
      api_key: "synthetic-label-target-key",
      settings: %{"timezone" => "UTC"}
    })

    for {actor, path} <- [
          {user.id, "/settings/users"},
          {user.id, "/settings/users/8412"},
          {user.id, "/settings/users/8412/edit"},
          {user.id, "/settings/background_jobs"},
          {8412, "/settings/background_jobs"}
        ] do
      conn = get(RailsUser.signed_in(actor) |> RailsUser.connecting_as(actor), path)
      {:ok, view, connected} = live(conn)
      assert_native_controls(html_response(conn, 200))
      assert_native_controls(connected)

      if path == "/settings/users" do
        render_hook(view, "open_create", %{})
        assert_native_controls(Dawarich.Test.NativeAdminUI.html(view))
        render_hook(view, "open_delete", %{"id" => "8412"})
        assert_native_controls(Dawarich.Test.NativeAdminUI.html(view))
      end

      GenServer.stop(view.pid)
    end
  end

  defp assert_native_controls(html) do
    assert Dawarich.Test.NativeAdminUI.labels(html) == []
    ids = html |> LazyHTML.from_document() |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")
    assert Enum.uniq(ids) == ids
    for marker <- @markers, do: refute(html =~ marker)
  end

  test "every native page renders without Turbo, Stimulus or the importmap", %{user: user} do
    paths =
      native_paths() ++
        for(
          service <- ~w(photoprism airtrail teslamate trek),
          do: "/settings/integrations?service=#{service}"
        ) ++ ["/admin/settings?section=experimental"]

    assert "/tags" in paths

    saving =
      for path <- paths do
        conn = get(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)
        static = html_response(conn, 200)
        {:ok, _view, connected} = live(conn)

        for {html, phase} <- [{static, :static}, {connected, :connected}], marker <- @markers do
          refute html =~ marker, "#{path} (#{phase}) contains #{marker}"
        end

        for html <- [static, connected] do
          assert unlabelled(html) == [], "#{path} has unlabelled or doubly labelled controls"
          assert password_forms_with_change(html) == [], "#{path} sends passwords on phx-change"
        end

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

  test "LiveView event telemetry, which carries raw form params, reaches only LiveView's own logger" do
    for prefix <- [
          [:phoenix, :live_view, :handle_event],
          [:phoenix, :live_component, :handle_event]
        ],
        handler <- :telemetry.list_handlers(prefix) do
      assert match?({Phoenix.LiveView.Logger, _}, handler.id),
             "unexpected #{inspect(handler.id)} on #{inspect(handler.event_name)}"
    end
  end
end
