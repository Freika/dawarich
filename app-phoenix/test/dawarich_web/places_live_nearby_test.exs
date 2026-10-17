defmodule DawarichWeb.PlacesLiveNearbyTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest
  import ExUnit.CaptureLog
  alias Dawarich.Test.NativePlaces, as: N
  @endpoint DawarichWeb.Endpoint
  @attrs %{
    "name" => "Draft",
    "latitude" => "51",
    "longitude" => "12",
    "note" => "Retained note",
    "tag_ids" => []
  }
  setup do
    ctx = N.setup!()
    previous = Application.get_env(:dawarich, :native_places_nearby_opts)
    parent = self()

    fetch = fn _, lat, _, radius, _, _ ->
      send(parent, {:provider_started, self(), lat, radius})

      receive do
        {:respond, results} -> results
      end
    end

    Application.put_env(:dawarich, :native_places_nearby_opts, fetch: fetch)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :native_places_nearby_opts, previous),
        else: Application.delete_env(:dawarich, :native_places_nearby_opts)
    end)

    Map.put(ctx, :fetch, fetch)
  end

  defp open(ctx) do
    {:ok, view, _} = live(N.conn(ctx.actor), "/places")
    render_click(view, "open_create", %{})
    gen = N.generation(view, :form_state)
    render_change(view, "validate_place", %{"generation" => gen, "place" => @attrs})
    {view, gen}
  end

  defp suggestion,
    do: %{
      "name" => "Suggestion",
      "latitude" => 51.2,
      "longitude" => 12.2,
      "geodata" => %{"api_key" => "synthetic-hidden-provider"}
    }

  test "nearby runs only connected and only once per current request", ctx do
    get(N.conn(ctx.actor), "/places")
    refute_received {:provider_started, _, _, _}
    {view, gen} = open(ctx)
    render_click(view, "nearby", %{"generation" => gen})
    assert_receive {:provider_started, task, 51.0, 0.5}
    token = :sys.get_state(view.pid).socket.assigns.nearby_state.token
    render_click(view, "nearby", %{"generation" => gen})
    assert :sys.get_state(view.pid).socket.assigns.nearby_state.token == token
    refute_received {:provider_started, _, _, _}
    send(task, {:respond, []})
    render_async(view)
    assert has_element?(view, "[data-nearby-state=empty]")
  end

  test "only matching nearby result and timeout may alter current form", ctx do
    {view, gen} = open(ctx)
    render_click(view, "nearby", %{"generation" => gen})
    assert_receive {:provider_started, task, _, _}
    old = :sys.get_state(view.pid).socket.assigns.nearby_state
    monitor = Process.monitor(task)

    render_change(view, "validate_place", %{
      "generation" => gen,
      "place" => %{@attrs | "latitude" => "52"}
    })

    assert_receive {:DOWN, ^monitor, :process, ^task, _}
    render_click(view, "nearby", %{"generation" => gen})
    assert_receive {:provider_started, current, 52.0, _}
    send(view.pid, {:nearby_timeout, old.generation, old.token})
    render(view)
    assert :sys.get_state(view.pid).socket.assigns.nearby_state.status == :loading
    send(current, {:respond, [suggestion()]})
    render_async(view)
    send(view.pid, {:nearby_timeout, old.generation, old.token})
    assert render(view) =~ "Suggestion"
    assert :sys.get_state(view.pid).socket.assigns.nearby_state.status == :results
    render_click(view, "cancel_form", %{})
    refute render(view) =~ "Suggestion"
  end

  test "nearby selection changes only name and coordinates", ctx do
    {view, gen} = open(ctx)
    render_click(view, "nearby", %{"generation" => gen})
    assert_receive {:provider_started, task, _, _}
    send(task, {:respond, [suggestion()]})
    render_async(view)

    run = :sys.get_state(view.pid).socket.assigns.nearby_state.run_id

    render_click(view, "select_nearby", %{
      "generation" => gen,
      "run" => run,
      "index" => "0",
      "note" => "Forged"
    })

    html = render(view)
    assert html =~ "Retained note"
    assert html =~ "Suggestion"
    refute html =~ "Forged"
    refute html =~ "synthetic-hidden-provider"

    assert :sys.get_state(view.pid).socket.assigns.form_state.changeset.params["latitude"] ==
             "51.2"

    render_click(view, "select_nearby", %{"generation" => gen, "run" => run, "index" => "99"})
    assert render(view) =~ "Retained note"
  end

  test "nearby selection refuses a previous completed provider run", ctx do
    {view, gen} = open(ctx)
    render_click(view, "nearby", %{"generation" => gen})
    assert_receive {:provider_started, first, _, _}
    send(first, {:respond, [Map.put(suggestion(), "name", "First run")]})
    render_async(view)
    old = :sys.get_state(view.pid).socket.assigns.nearby_state[:run_id]
    render_click(view, "nearby", %{"generation" => gen, "radius" => "1.0"})
    assert_receive {:provider_started, second, _, 1.0}
    send(second, {:respond, [Map.put(suggestion(), "name", "Second run")]})
    render_async(view)
    before = :sys.get_state(view.pid).socket.assigns.form_state.changeset
    current = :sys.get_state(view.pid).socket.assigns.nearby_state[:run_id]

    render_click(view, "select_nearby", %{"generation" => gen, "run" => old, "index" => "0"})
    assert :sys.get_state(view.pid).socket.assigns.form_state.changeset == before
    render_click(view, "select_nearby", %{"generation" => gen, "index" => "0"})
    assert :sys.get_state(view.pid).socket.assigns.form_state.changeset == before
    assert is_binary(old) and is_binary(current) and old != current

    assert has_element?(
             view,
             "[phx-click=select_nearby][phx-value-run='#{current}']",
             "Second run"
           )

    render_click(view, "select_nearby", %{"generation" => gen, "run" => current, "index" => "0"})
    assert has_element?(view, "input[name='place[name]'][value='Second run']")
    assert has_element?(view, "textarea", "Retained note")
  end

  test "nearby crash timeout and revoked delivery expose no config or private state", ctx do
    {view, gen} = open(ctx)
    render_click(view, "nearby", %{"generation" => gen})
    assert_receive {:provider_started, task, _, _}
    state = :sys.get_state(view.pid).socket.assigns.nearby_state
    monitor = Process.monitor(task)
    send(view.pid, {:nearby_timeout, state.generation, state.token})
    assert render(view) =~ "role=\"alert\""
    assert_receive {:DOWN, ^monitor, :process, ^task, _}

    Application.put_env(:dawarich, :native_places_nearby_opts,
      fetch: fn _, _, _, _, _, _ -> raise "api_key=synthetic-crash-secret" end
    )

    crash_log =
      capture_log(fn ->
        render_click(view, "nearby", %{"generation" => gen})
        render_async(view)
        assert has_element?(view, "dialog [role=alert]")
      end)

    assert {String.contains?(crash_log, "synthetic-crash-secret"), :leak} == {false, :leak}
    Application.put_env(:dawarich, :native_places_nearby_opts, fetch: ctx.fetch)
    render_click(view, "nearby", %{"generation" => gen})
    assert_receive {:provider_started, current, _, _}
    N.revoke(ctx.actor)

    log =
      capture_log(fn ->
        send(current, {:respond, [suggestion()]})
        assert_redirect(view, "/users/sign_in")
      end)

    refute String.contains?(log, "synthetic-hidden-provider")
  end
end
