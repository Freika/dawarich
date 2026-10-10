defmodule DawarichWeb.TripsNativeNotesTest do
  use Dawarich.DataCase, async: false

  import Phoenix.LiveViewTest

  alias Dawarich.Accounts
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.{TripsNativeUI, TripsSeeds}
  alias Dawarich.Trips.Notes

  setup do
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Dawarich.Repo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, previous) end)
    TripsSeeds.user!(9_971)
    TripsSeeds.user!(9_972)

    TripsSeeds.trip!(%{
      id: 997_101,
      user_id: 9_971,
      distance: 1000,
      path: [[12.5, 51.25], [12.4, 51.34]],
      started_at: ~N[2026-05-09 06:00:00],
      ended_at: ~N[2026-05-12 20:00:00]
    })

    TripsSeeds.note!(%{
      id: 997_191,
      trip_id: 997_101,
      user_id: 9_971,
      body: "Lunch by the lake",
      noted_at: ~N[2026-05-10 12:00:00]
    })

    :ok
  end

  defp open(user_id \\ 9_971) do
    {:ok, view, _html} = TripsNativeUI.live_as(user_id, "/trips/997101")
    render_async(view)
    view
  end

  defp notes,
    do: rows("SELECT body, noted_at FROM notes WHERE attachable_id=997101 ORDER BY noted_at")

  defp textarea(view, date) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#note-form-#{date} textarea")
    |> Enum.map(&LazyHTML.text/1)
  end

  test "daily note cancel and reopen preserve persisted text and zoned noon" do
    view = open()
    render_click(view, "note_edit", %{"date" => "2026-05-10"})
    assert textarea(view, "2026-05-10") == ["Lunch by the lake"]

    view
    |> form("#note-form-2026-05-10", note: %{body: "Changed my mind"})
    |> render_change()

    render_click(view, "note_cancel", %{"date" => "2026-05-10"})
    assert render(view) =~ "Lunch by the lake"
    render_click(view, "note_edit", %{"date" => "2026-05-10"})
    assert textarea(view, "2026-05-10") == ["Lunch by the lake"]
    render_click(view, "note_cancel", %{"date" => "2026-05-10"})

    render_click(view, "note_edit", %{"date" => "2026-05-11"})

    view
    |> form("#note-form-2026-05-11", note: %{body: "Dinner at the harbour"})
    |> render_submit()

    assert render(view) =~ "Dinner at the harbour"
    refute has_element?(view, "#note-form-2026-05-11")

    assert notes() == [
             ["Lunch by the lake", ~N[2026-05-10 12:00:00.000000]],
             ["Dinner at the harbour", ~N[2026-05-11 12:00:00.000000]]
           ]
  end

  test "two submissions keep one note for the owned trip date" do
    first = open()
    second = open()

    for {view, body} <- [{first, "From the first tab"}, {second, "From the second tab"}] do
      render_click(view, "note_edit", %{"date" => "2026-05-11"})
      view |> form("#note-form-2026-05-11", note: %{body: body}) |> render_submit()
    end

    assert rows(
             "SELECT body FROM notes WHERE attachable_id=997101 AND noted_at::date='2026-05-11'"
           ) ==
             [["From the second tab"]]

    scope = Scope.for_user(Accounts.get(9_972), "en")

    assert Notes.save(scope, 997_101, "2026-05-11", "Foreign", ~U[2026-10-03 10:00:00Z]) ==
             {:error, :not_found}

    assert Notes.save(
             Scope.for_user(Accounts.get(9_971), "en"),
             997_101,
             "bad-date",
             "x",
             ~U[2026-10-03 10:00:00Z]
           ) == {:error, :invalid_date}

    assert length(notes()) == 2
  end

  test "calculation updates do not erase an unsaved visible note" do
    view = open()
    render_click(view, "note_edit", %{"date" => "2026-05-09"})

    view
    |> form("#note-form-2026-05-09", note: %{body: "Half-written arrival"})
    |> render_change()

    rows("UPDATE trips SET distance=2000 WHERE id=997101")
    send(view.pid, {:domain_changed, 997_101, :trip})
    render_async(view)

    assert textarea(view, "2026-05-09") == ["Half-written arrival"]
    assert length(notes()) == 1
  end

  test "notes outside the visible window or of a deleted note are refused without effects" do
    view = open()
    render_click(view, "note_edit", %{"date" => "2027-01-01"})
    refute has_element?(view, "#note-form-2027-01-01")

    render_click(view, "note_delete", %{"date" => "2026-05-10"})
    refute render(view) =~ "Lunch by the lake"
    assert notes() == []

    render_click(view, "note_delete", %{"date" => "2026-05-10"})
    assert notes() == []
  end
end
