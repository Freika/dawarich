defmodule Dawarich.SafeTimestampTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.SafeTimestamp

  @now ~U[2026-09-29 10:00:00Z]

  test "two text bounds resolve in one statement with clamps and the year-2000 guard" do
    {result, statements} =
      count(fn ->
        Repo.transaction(fn ->
          Repo.query!("SELECT set_config('TimeZone', 'Europe/Berlin', true)")

          [
            SafeTimestamp.range({:text, "2026-01-01"}, {:text, "2026-01-02T12:30:00Z"}, @now),
            SafeTimestamp.range({:text, "J2451545"}, {:epoch, 99_999_999_999}, @now),
            SafeTimestamp.range(nil, {:text, "2000-01-01"}, @now)
          ]
        end)
      end)

    assert {:ok,
            [
              {1_767_222_000, 1_767_357_000},
              {1_790_676_000, 4_102_441_200},
              {nil, 946_681_200}
            ]} = result

    assert statements == 3
  end

  defp count(fun) do
    owner = self()
    key = {__MODULE__, make_ref()}

    :telemetry.attach(
      key,
      [:dawarich, :repo, :query],
      fn _, _, meta, _ ->
        if self() == owner and meta.query =~ "extract(epoch", do: send(owner, key)
      end,
      nil
    )

    try do
      result = fun.()
      {result, drain(key, 0)}
    after
      :telemetry.detach(key)
    end
  end

  defp drain(key, n) do
    receive do
      ^key -> drain(key, n + 1)
    after
      0 -> n
    end
  end
end
