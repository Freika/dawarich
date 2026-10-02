defmodule Dawarich.Tracks.ChunkerTest do
  use Dawarich.TracksCase, async: true, group: :tracks_db

  alias Dawarich.Tracks.Chunker

  @dst [
    {0, 1_774_652_400, 1_774_738_800, 1_774_652_400, 1_774_760_400},
    {1, 1_774_738_800, 1_774_821_600, 1_774_717_200, 1_774_843_200},
    {2, 1_774_821_600, 1_774_908_000, 1_774_800_000, 1_774_908_000}
  ]

  @base 1_780_300_800
  @points [
    @base + 36_000,
    @base + 36_600,
    @base + 3 * 86_400 + 43_200,
    @base + 3 * 86_400 + 43_800
  ]
  @gap_start @base - 7_200

  @gap [
    {0, 1_780_293_600, 1_780_380_000, 1_780_293_600, 1_780_401_600},
    {1, 1_780_552_800, 1_780_639_200, 1_780_531_200, 1_780_660_800}
  ]

  @first_to_last [
    {0, 1_780_336_800, 1_780_423_200, 1_780_336_800, 1_780_444_800},
    {1, 1_780_509_600, 1_780_596_000, 1_780_488_000, 1_780_603_800},
    {2, 1_780_596_000, 1_780_603_800, 1_780_574_400, 1_780_603_800}
  ]

  @first_to_end [{0, 1_780_336_800, 1_780_423_200, 1_780_336_800, 1_780_444_800}]

  test "chunks follow Rails across DST and skip empty days" do
    %{call: [call]} = TracksFixtures.load!(ScratchRepo, "range_dst")

    assert chunks(1, call["start_at"], call["end_at"], call["zone"]) == @dst

    user = gap_user!()
    assert chunks(user, @gap_start, @gap_start + 5 * 86_400, "Europe/Berlin") == @gap
  end

  test "open bounds use the first and last point" do
    user = gap_user!()

    assert chunks(user, nil, nil, "Europe/Berlin") == @first_to_last
    assert chunks(user, nil, @base + 2 * 86_400, "Europe/Berlin") == @first_to_end

    before = database_time()
    point!(user, before - 60, 12.3731, 51.3397)

    [{0, start_ts, end_ts, buffer_start_ts, buffer_end_ts}] =
      chunks(user, before - 3_600, nil, "UTC")

    after_call = database_time()

    assert {start_ts, buffer_start_ts} == {before - 3_600, before - 3_600}
    assert end_ts in before..after_call
    assert buffer_end_ts == end_ts
  end

  defp gap_user! do
    user = user!()
    for ts <- @points, do: point!(user.id, ts, 12.3731, 51.3397)
    user.id
  end

  defp chunks(user_id, start_ts, end_ts, zone) do
    ScratchRepo
    |> Chunker.chunks(user_id, at(start_ts), at(end_ts), zone)
    |> Enum.map(&{&1.chunk_id, &1.start_ts, &1.end_ts, &1.buffer_start_ts, &1.buffer_end_ts})
  end

  defp database_time do
    %{rows: [[timestamp]]} =
      ScratchRepo.query!("SELECT floor(extract(epoch FROM clock_timestamp()))::bigint", [],
        log: false
      )

    timestamp
  end

  defp at(nil), do: nil
  defp at(epoch), do: DateTime.from_unix!(epoch)
end
