defmodule Dawarich.Visits.WebScopeTest do
  use Dawarich.JobsCase
  alias Dawarich.Visits.WebScope
  @now ~U[2026-10-03 10:00:00Z]
  @stamp ~N[2026-10-03 10:00:00.000000]

  setup do
    for {id, plan} <- [{8900, 0}, {8901, 2}] do
      ScratchRepo.insert_all("users", [
        %{
          id: id,
          email: "a8-scope-#{id}@dawarich.test",
          encrypted_password: "synthetic",
          settings: %{"timezone" => "Europe/Berlin"},
          plan: plan,
          active_until: ~N[3026-01-01 00:00:00],
          created_at: @stamp,
          updated_at: @stamp
        }
      ])
    end

    %{user: %{id: 8900, plan: 0, settings: %{"timezone" => "Europe/Berlin"}}}
  end

  defp visit!(id, attrs \\ %{}) do
    ScratchRepo.insert_all("visits", [
      Map.merge(
        %{
          id: id,
          user_id: 8900,
          name: "Synthetic visit",
          status: 0,
          started_at: ~N[2026-10-03 09:00:00],
          ended_at: @stamp,
          duration: 60,
          created_at: @stamp,
          updated_at: @stamp
        },
        attrs
      )
    ])
  end

  defp load(user, ids, self_hosted \\ false),
    do:
      ScratchRepo.transaction(fn -> WebScope.load(ScratchRepo, user, ids, @now, self_hosted) end)

  @tag :timezone_fallback
  test "missing timezone cutoff uses configured DST zone and blank remains UTC", %{user: user} do
    previous = System.get_env("TIME_ZONE")
    System.put_env("TIME_ZONE", "Europe/Berlin")

    on_exit(fn ->
      if previous, do: System.put_env("TIME_ZONE", previous), else: System.delete_env("TIME_ZONE")
    end)

    for settings <- [%{}, %{"timezone" => nil}] do
      assert {:ok, ~N[2025-03-29 02:30:00.000000]} =
               WebScope.cutoff(
                 ScratchRepo,
                 %{user | settings: settings},
                 ~U[2026-03-29 01:30:00Z],
                 false
               )
    end

    assert {:ok, ~N[2025-03-29 01:30:00.000000]} =
             WebScope.cutoff(
               ScratchRepo,
               %{user | settings: %{"timezone" => ""}},
               ~U[2026-03-29 01:30:00Z],
               false
             )
  end

  test "mixed owned and foreign selection cannot partially mutate", %{user: user} do
    visit!(890_100)
    visit!(890_101, %{user_id: 8901})
    visit!(890_102, %{status: 2})
    visit!(890_103, %{deleted_at: @stamp})
    visit!(890_104, %{started_at: ~N[2025-01-01 00:00:00]})

    assert {:ok, {:error, :missing}} =
             ScratchRepo.transaction(fn ->
               case WebScope.load(ScratchRepo, user, [890_100, 890_101], @now, false) do
                 {:ok, rows} ->
                   ScratchRepo.query!("UPDATE visits SET status=1 WHERE id=ANY($1)", [
                     Enum.map(rows, & &1["id"])
                   ])

                   {:ok, rows}

                 other ->
                   other
               end
             end)

    assert [[0], [0]] =
             ScratchRepo.query!("SELECT status FROM visits WHERE id=ANY($1) ORDER BY id", [
               [890_100, 890_101]
             ]).rows

    assert {:ok, {:ok, [%{"id" => 890_100}]}} = load(user, [890_100])
  end

  test "declined and tombstoned visits cannot be resurrected", %{user: user} do
    visit!(890_110, %{status: 2})
    visit!(890_111, %{deleted_at: @stamp})
    for id <- [890_110, 890_111], do: assert(load(user, [id]) == {:ok, {:error, :missing}})

    assert [[2, nil], [0, @stamp]] =
             ScratchRepo.query!("SELECT status,deleted_at FROM visits ORDER BY id").rows
  end

  test "Lite cutoff includes inherited access and the exact boundary", %{user: user} do
    visit!(890_120, %{started_at: ~N[2025-10-03 10:00:00]})
    visit!(890_121, %{started_at: ~N[2025-10-03 09:59:59]})
    assert {:ok, {:ok, [%{"id" => 890_120}]}} = load(user, [890_120])
    assert {:ok, {:error, :archived}} = load(user, [890_120, 890_121])
    assert {:ok, {:error, :missing}} = load(user, [999_999])

    {1, [%{id: family}]} =
      ScratchRepo.insert_all(
        "families",
        [%{name: "Synthetic family", creator_id: 8901, created_at: @stamp, updated_at: @stamp}],
        returning: [:id]
      )

    ScratchRepo.insert_all("family_memberships", [
      %{family_id: family, user_id: user.id, role: 1, created_at: @stamp, updated_at: @stamp}
    ])

    assert {:ok, {:ok, rows}} = load(user, [890_120, 890_121])
    assert Enum.map(rows, & &1["id"]) == [890_120, 890_121]
    ScratchRepo.query!("UPDATE users SET deleted_at=$1 WHERE id=8901", [@stamp])
    assert {:ok, {:error, :archived}} = load(user, [890_121])
    assert {:ok, {:ok, [_]}} = load(user, [890_121], true)
  end

  test "selection ids match Ruby to_i deduplication and web cap" do
    assert WebScope.ids(nil) == {:ok, []}
    assert WebScope.ids("12prefix") == {:ok, [12]}

    assert WebScope.ids(["0", "12prefix", "12", "-3", "nonsense", "2_0tail"]) ==
             {:ok, [12, -3, 20]}

    assert WebScope.ids(List.duplicate("1", 501)) == {:ok, [1]}
    assert WebScope.ids(Enum.map(1..500, &Integer.to_string/1)) == {:ok, Enum.to_list(1..500)}
    assert WebScope.ids(Enum.map(1..501, &Integer.to_string/1)) == {:error, :too_many}
    for raw <- [12, %{}, ["12", %{}], [nil]], do: assert(match?({:replay, _}, WebScope.ids(raw)))
  end

  test "date scope uses the user's local DST day" do
    for {day, first, last, seconds} <- [
          {"2026-03-29", ~N[2026-03-28 23:00:00], ~N[2026-03-29 22:00:00], 82_800},
          {"2026-10-25", ~N[2026-10-24 22:00:00], ~N[2026-10-25 23:00:00], 90_000}
        ] do
      assert {:ok, {start, stop}} = WebScope.day_bounds("Europe/Berlin", day, ScratchRepo)
      assert NaiveDateTime.compare(start, first) == :eq
      assert NaiveDateTime.compare(stop, last) == :eq
      assert NaiveDateTime.diff(stop, start) == seconds
    end

    assert WebScope.day_bounds("Berlin", "2026-03-29", ScratchRepo) ==
             WebScope.day_bounds("Europe/Berlin", "2026-03-29", ScratchRepo)

    for {zone, date} <- [
          {"Unknown/Legacy", "2026-03-29"},
          {"UTC", "tomorrow"},
          {"UTC", "2026-02-30"},
          {nil, "2026-03-29"}
        ],
        do: assert(match?({:replay, _}, WebScope.day_bounds(zone, date, ScratchRepo)))
  end
end
