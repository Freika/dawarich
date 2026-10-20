defmodule DawarichWeb.ImportStallDeadlinesTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, ImportsExportsSeeds}
  @endpoint DawarichWeb.Endpoint

  setup do
    user = RailsUser.insert!(%{id: 13341, email: "stall-deadline@example.invalid"})
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    ImportsExportsSeeds.import!(%{
      id: 133_410,
      user_id: user.id,
      status: 4,
      updated_at: now |> DateTime.add(-3540) |> DateTime.to_naive()
    })

    ImportsExportsSeeds.import!(%{
      id: 133_411,
      user_id: user.id,
      source: 4,
      raw_data: %{"waypoints_seen" => 1},
      additional_data_extraction_status: 2,
      additional_data_extraction: %{
        "started_at" => now |> DateTime.add(-21540) |> DateTime.to_iso8601()
      }
    })

    clock = start_supervised!({Agent, fn -> now end})
    conn = RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id)
    %{now: now, clock: clock, conn: conn, user: user}
  end

  test "deletion recovery controls appear at their one-hour deadline without polling or invalidation",
       c do
    view = open(c, "/imports")
    refute has_element?(view, "#import_133410 [data-testid=import-delete]")
    token = scheduled_token(view, DateTime.add(c.now, 60))
    advance(c, 60)
    send(view.pid, {:import_stall_deadline, token})
    assert has_element?(view, "#import_133410 [data-testid=import-delete]")
    refute state(view).assigns.polling
  end

  test "extraction recovery controls appear at their six-hour deadline without a domain message",
       c do
    view = open(c, "/imports/133411")
    refute has_element?(view, "form[phx-submit=remove_extraction] button[type=submit]")
    token = scheduled_token(view, DateTime.add(c.now, 60))
    advance(c, 60)
    send(view.pid, {:import_stall_deadline, token})
    assert has_element?(view, "form[phx-submit=remove_extraction] button[type=submit]")

    assert render(view) =~
             DawarichWeb.Translate.t("en", "imports.extraction_card.start_over", %{})

    refute state(view).assigns.polling
  end

  test "superseded deadlines cannot refresh a new extraction and completed runs cancel their timer",
       c do
    view = open(c, "/imports/133411")
    old = token(view)
    started(c, 3600)
    wake(view)
    current = token(view)
    assert old != current
    advance(c, 60)
    send(view.pid, {:import_stall_deadline, old})
    render(view)
    assert state(view).assigns.now == c.now
    refute has_element?(view, "form[phx-submit=remove_extraction] button[type=submit]")
    advance(c, 3660)
    send(view.pid, {:import_stall_deadline, current})
    assert has_element?(view, "form[phx-submit=remove_extraction] button[type=submit]")

    started(c, 7200)
    wake(view)
    %{timer: timer} = state(view).assigns.import_stall_timer
    rows("UPDATE imports SET additional_data_extraction_status=3 WHERE id=133411")
    wake(view)
    assert state(view).assigns.import_stall_timer == nil
    assert Process.read_timer(timer) == false
  end

  test "deadline deliveries re-admit revoked sessions and clear and cancel both private snapshots",
       c do
    views =
      for {module, path} <- [
            {DawarichWeb.ImportsLive.Index, "/imports"},
            {DawarichWeb.ImportsLive.Show, "/imports/133411"}
          ],
          do: {module, open(c, path)}

    rows("UPDATE users SET encrypted_password='revoked-stall-session' WHERE id=$1", [c.user.id])
    advance(c, 60)

    for {module, view} <- views do
      socket = state(view)
      timer = socket.assigns[:import_stall_timer] || %{token: make_ref(), timer: nil}
      socket = Phoenix.Component.assign(socket, :import_stall_timer, timer)

      assert {:noreply, refused} =
               module.handle_info({:import_stall_deadline, timer.token}, socket)

      assert refused.redirected == {:redirect, %{to: "/users/sign_in", status: 302}}
      assert refused.assigns.import_stall_timer == nil
      assert (refused.assigns[:entries] || []) == []
      assert refused.assigns[:record] == nil
      assert refused.assigns[:points] == nil
    end
  end

  defp open(c, path) do
    {:ok, view, _} = live(c.conn, path)

    :sys.replace_state(view.pid, fn state ->
      put_in(state.socket.assigns[:imports_clock], fn -> Agent.get(c.clock, & &1) end)
    end)

    wake(view)
    view
  end

  defp scheduled_token(view, expected) do
    timer = state(view).assigns.import_stall_timer
    assert DateTime.compare(timer.at, expected) == :eq
    assert Process.read_timer(timer.timer) in 1..60_000
    timer.token
  end

  defp state(view), do: :sys.get_state(view.pid).socket
  defp token(view), do: (state(view).assigns[:import_stall_timer] || %{token: make_ref()}).token
  defp advance(c, seconds), do: Agent.update(c.clock, fn _ -> DateTime.add(c.now, seconds) end)

  defp wake(view) do
    send(view.pid, :imports_changed)
    render(view)
  end

  defp started(c, offset) do
    at = c.now |> DateTime.add(offset - 21540) |> DateTime.to_iso8601()

    rows("UPDATE imports SET additional_data_extraction=$1 WHERE id=133411", [
      %{"started_at" => at}
    ])
  end
end
