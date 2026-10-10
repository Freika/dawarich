defmodule Dawarich.RailsTimeTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.RailsTime

  setup do
    previous = System.get_env("TIME_ZONE")
    System.delete_env("TIME_ZONE")

    on_exit(fn ->
      if previous, do: System.put_env("TIME_ZONE", previous), else: System.delete_env("TIME_ZONE")
    end)
  end

  test "zones abbreviated UTC end in Z; another zero offset keeps +00:00" do
    assert RailsTime.iso8601(~N[2026-12-01 10:00:00], "UTC") == {:ok, "2026-12-01T10:00:00Z"}
    assert RailsTime.iso8601(~N[2026-12-01 10:00:00], "Etc/UTC") == {:ok, "2026-12-01T10:00:00Z"}

    assert RailsTime.iso8601(~N[2027-01-15 10:00:00], "Europe/London") ==
             {:ok, "2027-01-15T10:00:00+00:00"}
  end

  test "local time and offset at the instant, seconds truncated" do
    assert RailsTime.iso8601(~N[2027-07-01 10:00:00], "Europe/Berlin") ==
             {:ok, "2027-07-01T12:00:00+02:00"}

    assert RailsTime.iso8601(~N[2027-01-15 10:00:00], "America/New_York") ==
             {:ok, "2027-01-15T05:00:00-05:00"}

    assert RailsTime.iso8601(~N[2027-03-01 10:00:00.987654], "Asia/Kolkata") ==
             {:ok, "2027-03-01T15:30:00+05:30"}
  end

  test "after TZInfo's last generated year the offset in force at that year's end holds" do
    horizon = Date.utc_today().year + 100
    {:ok, inside} = NaiveDateTime.new(horizon, 7, 1, 10, 0, 0)
    {:ok, beyond} = NaiveDateTime.new(horizon + 1, 7, 1, 10, 0, 0)

    assert RailsTime.iso8601(inside, "Europe/Berlin") == {:ok, "#{horizon}-07-01T12:00:00+02:00"}

    assert RailsTime.iso8601(beyond, "Europe/Berlin") ==
             {:ok, "#{horizon + 1}-07-01T11:00:00+01:00"}

    assert RailsTime.iso8601(~N[3026-07-01 12:00:00], "Australia/Sydney") ==
             {:ok, "3026-07-01T23:00:00+11:00"}
  end

  test "no setting reads TIME_ZONE, then UTC; no time is nil whatever the setting" do
    assert RailsTime.iso8601(~N[2027-01-15 10:00:00], nil) == {:ok, "2027-01-15T10:00:00Z"}
    System.put_env("TIME_ZONE", "Europe/London")
    assert RailsTime.iso8601(~N[2027-01-15 10:00:00], nil) == {:ok, "2027-01-15T10:00:00+00:00"}
    assert RailsTime.iso8601(nil, 42) == {:ok, nil}
  end

  test "Rails aliases resolve to their IANA zone; other spellings, shapes and unknown zones go to Rails" do
    assert RailsTime.iso8601(~N[2027-07-01 10:00:00], "Berlin") ==
             {:ok, "2027-07-01T12:00:00+02:00"}

    assert RailsTime.iso8601(~N[2027-01-15 10:00:00], "Eastern Time (US & Canada)") ==
             {:ok, "2027-01-15T05:00:00-05:00"}

    for setting <- ["europe/berlin", "Europe/berlin", "UTC+3", "", 1, true, "Mars/Olympus_Mons"],
        do:
          assert(
            {:replay, _} = RailsTime.iso8601(~N[2027-01-15 10:00:00], setting),
            inspect(setting)
          )

    assert RailsTime.iso8601(~N[2027-07-01 10:00:00], "Europe/Berlin") ==
             {:ok, "2027-07-01T12:00:00+02:00"}
  end

  test "with_zone runs the function in the resolved zone: an IANA name as given, a Rails alias mapped, nil through TIME_ZONE to UTC" do
    assert RailsTime.with_zone("America/New_York", fn ->
             Repo.query!("SELECT current_setting('TimeZone'), ($1::timestamptz)::date", [
               ~U[2027-01-01 03:00:00Z]
             ]).rows
           end) == [["America/New_York", ~D[2026-12-31]]]

    zone = fn setting ->
      RailsTime.with_zone(setting, fn ->
        Repo.query!("SELECT current_setting('TimeZone')").rows
      end)
    end

    assert {zone.("Berlin"), zone.(nil)} == {[["Europe/Berlin"]], [["Etc/UTC"]]}
  end

  test "with_zone hands other spellings, other shapes and unknown zones to Rails without calling the function" do
    for setting <- ["europe/berlin", "Mars/Olympus_Mons", "", 1] do
      assert {:replay, _} =
               RailsTime.with_zone(setting, fn -> flunk("called for #{inspect(setting)}") end),
             inspect(setting)
    end

    assert RailsTime.with_zone("Europe/Berlin", fn -> :ok end) == :ok
  end

  test "nested equal zones set the database timezone once, and deferred calls set it again" do
    parent = self()
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      [:dawarich, :repo, :query],
      fn _, _, meta, _ ->
        if self() == parent and String.contains?(meta.query, "set_config('TimeZone'"),
          do: send(parent, :set_zone)
      end,
      nil
    )

    try do
      deferred =
        RailsTime.with_zone("Berlin", fn ->
          RailsTime.with_zone("Europe/Berlin", fn ->
            assert RailsTime.iso8601(~N[2027-07-01 10:00:00], "Berlin") ==
                     {:ok, "2027-07-01T12:00:00+02:00"}

            fn -> RailsTime.iso8601(~N[2027-01-15 10:00:00], "Berlin") end
          end)
        end)

      assert_receive :set_zone
      refute_receive :set_zone
      assert deferred.() == {:ok, "2027-01-15T11:00:00+01:00"}
      assert_receive :set_zone
      refute_receive :set_zone
    after
      :telemetry.detach(handler)
    end
  end

  test "different nested zones do not leave a false cache of the outer zone" do
    RailsTime.with_zone("Europe/Berlin", fn ->
      RailsTime.with_zone("Europe/Berlin", fn ->
        assert RailsTime.iso8601(~N[2027-07-01 10:00:00], "America/New_York") ==
                 {:ok, "2027-07-01T06:00:00-04:00"}
      end)

      assert RailsTime.iso8601(~N[2027-07-01 10:00:00], "Europe/Berlin") ==
               {:ok, "2027-07-01T12:00:00+02:00"}
    end)

    assert catch_throw(RailsTime.with_zone("Berlin", fn -> throw(:aborted) end)) == :aborted

    assert RailsTime.iso8601(~N[2027-01-15 10:00:00], "America/New_York") ==
             {:ok, "2027-01-15T05:00:00-05:00"}
  end

  defmodule QueryAdapter do
    defdelegate transaction(fun), to: Dawarich.Repo
    defdelegate query(sql, params), to: Dawarich.Repo
    defdelegate rollback(reason), to: Dawarich.Repo
  end

  test "query adapters without a dynamic repository retain the timezone contract" do
    assert RailsTime.with_zone(QueryAdapter, "Berlin", fn ->
             Repo.query!("SELECT current_setting('TimeZone')").rows
           end) == [["Europe/Berlin"]]
  end

  test "a query adapter inside an Ecto scope invalidates the previous timezone marker" do
    RailsTime.with_zone("Berlin", fn ->
      RailsTime.with_zone(QueryAdapter, "America/New_York", fn -> :ok end)

      assert RailsTime.iso8601(~N[2027-07-01 10:00:00], "Berlin") ==
               {:ok, "2027-07-01T12:00:00+02:00"}
    end)
  end

  test "sql/2 prints Rails' iso8601 (0) and JSON time (3) of a UTC timestamp in the session zone" do
    row = fn zone, at ->
      RailsTime.with_zone(zone, fn ->
        hd(
          Repo.query!(
            "SELECT #{RailsTime.sql("$1::timestamp", 0)}, #{RailsTime.sql("$1::timestamp", 3)}, #{RailsTime.sql("NULL::timestamp", 3)}",
            [at]
          ).rows
        )
      end)
    end

    assert row.("Europe/Berlin", ~N[2027-07-01 10:00:00.987654]) == [
             "2027-07-01T12:00:00+02:00",
             "2027-07-01T12:00:00.987+02:00",
             nil
           ]

    assert row.("UTC", ~N[2027-07-01 10:00:00.000999]) == [
             "2027-07-01T10:00:00Z",
             "2027-07-01T10:00:00.000Z",
             nil
           ]

    assert row.("Europe/London", ~N[2027-01-15 10:00:00]) == [
             "2027-01-15T10:00:00+00:00",
             "2027-01-15T10:00:00.000+00:00",
             nil
           ]

    assert row.("America/St_Johns", ~N[2027-01-15 10:00:00]) == [
             "2027-01-15T06:30:00-03:30",
             "2027-01-15T06:30:00.000-03:30",
             nil
           ]
  end
end
