defmodule Dawarich.PointExportsTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.PointExports
  alias Dawarich.Test.RailsUser

  @ok "2024-03-01 00:00:00 UTC"

  defp params(start_at, end_at \\ "2024-03-31 00:00:00 +0100", format \\ "json"),
    do: %{"start_at" => start_at, "end_at" => end_at, "file_format" => format}

  test "the points page's TimeWithZone#to_s stamps give Rails' name and UTC bounds" do
    assert PointExports.parse(params("2024-03-01 00:00:00 +0100")) ==
             {:ok,
              %{
                name: "export_from_2024-03-01_to_2024-03-31.json",
                file_format: 0,
                start_at: ~N[2024-02-29 23:00:00],
                end_at: ~N[2024-03-30 23:00:00]
              }}

    for {stamp, utc} <- [
          {"2024-03-01 00:00:00 UTC", ~N[2024-03-01 00:00:00]},
          {"2024-03-01 00:00:00 -0000", ~N[2024-03-01 00:00:00]},
          {"2024-03-01 00:00:00 +0545", ~N[2024-02-29 18:15:00]},
          {"2024-03-01 00:00:00 -0330", ~N[2024-03-01 03:30:00]},
          {"2024-03-01 00:00:00 +2359", ~N[2024-02-29 00:01:00]},
          {"1583-01-01 12:30:59 +1345", ~N[1582-12-31 22:45:59]},
          {"2024-02-29 23:59:59 UTC", ~N[2024-02-29 23:59:59]}
        ] do
      assert {:ok, %{start_at: ^utc}} = PointExports.parse(params(stamp)), stamp
    end

    assert {:ok, %{name: "export_from_1583-01-01_to_2024-03-31.json"}} =
             PointExports.parse(params("1583-01-01 12:30:59 +1345"))

    assert {:ok, %{name: "export_from_2024-03-01_to_2024-03-31.gpx", file_format: 1}} =
             PointExports.parse(params(@ok, "2024-03-31 00:00:00 +0100", "gpx"))
  end

  test "every other shape is Rails' to answer" do
    for bad <- [
          "2024-03-01",
          "2024-03-01T00:00",
          "2024-03-01 00:00:00",
          "2024-03-01 00:00:00 +01:00",
          "2024-03-01T00:00:00Z",
          "2024-03-01 00:00:00 CET",
          "2024-03-01 00:00:00 GMT",
          " 2024-03-01 00:00:00 UTC",
          "2024-03-01 00:00:00 UTC ",
          "2024-02-30 00:00:00 UTC",
          "2024-03-01 24:00:00 UTC",
          "2024-03-01 23:59:60 UTC",
          "2024-03-01 00:00:00 +2400",
          "2024-03-01 00:00:00 +0060",
          "1582-10-10 00:00:00 +0000",
          "1500-02-29 00:00:00 +0000",
          "10000-01-01 00:00:00 UTC",
          "2024-3-01 00:00:00 UTC",
          "",
          nil,
          [@ok]
        ] do
      assert PointExports.parse(params(bad)) == :rails, inspect(bad)
      assert PointExports.parse(params(@ok, bad)) == :rails, inspect(bad)
    end

    for format <- ["archive", "csv", "JSON", "", nil, ["json"]] do
      assert PointExports.parse(params(@ok, @ok, format)) == :rails, inspect(format)
    end

    assert PointExports.parse(%{"start_at" => @ok, "end_at" => @ok}) == :rails
    assert PointExports.parse(%{"end_at" => @ok, "file_format" => "json"}) == :rails
  end

  test "create writes Rails' row and the exports.points_created command in one transaction" do
    RailsUser.insert!(%{id: 7321, email: "a7s2-create@dawarich.test"})
    {:ok, export} = PointExports.parse(params("2024-03-01 00:00:00 +0100"))

    assert {:ok, id} = PointExports.create(export, %{id: 7321}, "de")

    assert [
             [
               ^id,
               "export_from_2024-03-01_to_2024-03-31.json",
               0,
               0,
               0,
               start_at,
               end_at,
               7321,
               nil,
               nil,
               nil,
               created,
               created
             ]
           ] =
             Repo.query!(
               "SELECT id, name, status, file_format, file_type, start_at, end_at, user_id, url, error_message, processing_started_at, created_at, updated_at FROM exports"
             ).rows

    assert {start_at, end_at} == {~N[2024-02-29 23:00:00.000000], ~N[2024-03-30 23:00:00.000000]}

    assert commands() == [
             ["exports.points_created", %{"export_id" => id, "user_id" => 7321, "locale" => "de"}]
           ]
  end

  test "a command that cannot be written leaves no export behind" do
    RailsUser.insert!(%{id: 7322, email: "a7s2-rollback@dawarich.test"})
    Repo.query!("DROP TABLE phoenix.rails_commands")
    {:ok, export} = PointExports.parse(params(@ok))

    assert PointExports.create(export, %{id: 7322}, "en") ==
             {:error, "export write failed: Postgrex.Error"}

    assert Repo.query!("SELECT count(*) FROM exports").rows == [[0]]
  end
end
