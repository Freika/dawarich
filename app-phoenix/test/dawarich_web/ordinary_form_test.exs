defmodule DawarichWeb.OrdinaryFormTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias DawarichWeb.OrdinaryForm, as: F
  @endpoint DawarichWeb.Endpoint

  defp changeset(params \\ %{}, action \\ nil) do
    cs =
      Ecto.Changeset.cast({%{name: "", note: ""}, %{name: :string, note: :string}}, params, [
        :name,
        :note
      ])
      |> Ecto.Changeset.validate_required([:name])

    %{cs | action: action}
  end

  test "ordinary form shows touched errors and submit summary while retaining values" do
    form =
      apply(F, :new, [
        "place",
        changeset(%{"name" => "", "_unused_name" => "", "note" => "Draft"}, :validate)
      ])

    html = render_component(&Dawarich.Test.OrdinaryFormLive.render_form/1, state: form)
    refute html =~ "can&#39;t be blank"
    assert html =~ "Draft"
    form = apply(F, :validate, [form, changeset(%{"name" => "", "note" => "Draft"}, :insert)])
    html = render_component(&Dawarich.Test.OrdinaryFormLive.render_form/1, state: form)
    assert html =~ "can&#39;t be blank"
    assert html =~ "role=\"alert\""
    assert html =~ "Draft"
  end

  test "ordinary form accepts a generation only once and permits zero-effect retry" do
    form = apply(F, :new, ["place", changeset(%{"name" => "Valid"})])
    assert {:ok, saving} = apply(F, :accept, [form, form.generation])
    assert apply(F, :accept, [saving, form.generation]) == :refused
    accepted = apply(F, :finish, [saving, {:ok, %{id: 1}}])
    assert apply(F, :accept, [accepted, form.generation]) == :refused
    fresh = apply(F, :new, ["place", changeset(%{"name" => "Valid"})])
    assert fresh.generation != form.generation
    assert fresh.id != form.id
    assert apply(F, :accept, [fresh, form.generation]) == :refused
    {:ok, saving} = apply(F, :accept, [fresh, fresh.generation])
    failed = apply(F, :finish, [saving, {:error, changeset(%{"name" => ""}, :insert)}])
    assert {:ok, _} = apply(F, :accept, [failed, fresh.generation])
  end

  test "ordinary form partial acceptance never retries create as new" do
    form = apply(F, :new, ["place", changeset(%{"name" => "Valid"})])
    {:ok, saving} = apply(F, :accept, [form, form.generation])
    partial = apply(F, :finish, [saving, {:partial, %{id: 1}, :tags_failed}])
    assert partial.status == :partial
    assert apply(F, :accept, [partial, form.generation]) == :refused
  end

  test "ordinary confirmation cancel performs no command and restores opener" do
    form = apply(F, :new, ["delete", changeset()])
    selected = apply(F, :confirm, [form, 41])
    assert selected.confirmation == 41
    assert apply(F, :confirm, [selected, 42]).confirmation == 41
    canceled = apply(F, :cancel, [selected])
    assert canceled.confirmation == nil

    html =
      render_component(&DawarichWeb.OrdinaryFormComponents.dialog/1,
        id: "test-dialog",
        title: "Delete",
        cancel_event: "cancel_form",
        close_label: "Close",
        inner_block: []
      )

    assert html =~ "dawarich:close-dialog"
    assert html =~ "phx-key=\"Escape\""
    assert html =~ "aria-labelledby=\"test-dialog-title\""
  end

  test "ordinary interface embeds independent full and note hosts with unique ids" do
    full = apply(F, :new, ["place", changeset(%{"name" => "First"})])
    note = apply(F, :new, ["note", changeset(%{"name" => "Second", "note" => "Note"})])

    html =
      render_component(&Dawarich.Test.OrdinaryFormLive.render_form/1, state: full) <>
        render_component(&Dawarich.Test.OrdinaryFormLive.render_form/1, state: note)

    ids = LazyHTML.from_fragment(html) |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")
    assert length(ids) == length(Enum.uniq(ids))
    refute html =~ "data-turbo"
    refute html =~ "phx-update=\"ignore\""
    {:ok, view, _} = live_isolated(Phoenix.ConnTest.build_conn(), Dawarich.Test.OrdinaryFormLive)
    state = :sys.get_state(view.pid).socket.assigns.forms["place"]
    render_submit(view, "save", %{"host" => "place", "generation" => state.generation})
    render_submit(view, "save", %{"host" => "place", "generation" => state.generation})
    assert has_element?(view, "#saves", "1")
    note_state = :sys.get_state(view.pid).socket.assigns.forms["note"]
    render_submit(view, "save", %{"host" => "note", "generation" => note_state.generation})
    assert has_element?(view, "#saves", "2")
  end
end
