defmodule DawarichWeb.ListFormatTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.Test.ParityHTML
  alias DawarichWeb.{BlobPath, HumanDatetime, HumanSize}

  @dir "test/fixtures/imports_exports"

  defp corpus(name), do: @dir |> Path.join(name) |> File.read!() |> Jason.decode!()

  test "HumanSize matches number_to_human_size" do
    for %{"locale" => locale, "bytes" => bytes, "text" => text} <- corpus("human_size.json"),
        do: assert(HumanSize.format(locale, bytes) == text, "#{locale} #{bytes}")

    assert HumanSize.format("en", nil) == nil
  end

  test "HumanDatetime matches human_datetime in every zone, month and locale" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)

    for %{"zone" => zone, "time" => time, "locale" => locale, "html" => html} <-
          corpus("human_datetime.json") do
      {:ok, at, 0} = DateTime.from_iso8601(time)
      naive = DateTime.to_naive(at)

      %{rows: [[offset, name]]} =
        Dawarich.UserTimeZone.query!(
          "SELECT extract(epoch FROM (($1::timestamp AT TIME ZONE 'UTC') AT TIME ZONE z.name) - $1::timestamp)::int, z.name FROM z",
          [naive],
          %{"timezone" => zone}
        )

      rendered =
        render_component(&HumanDatetime.human_datetime/1,
          locale: locale,
          at: Dawarich.ImportExportIndex.zoned(naive, offset, name)
        )

      assert ParityHTML.normalize(rendered) == ParityHTML.normalize(html),
             "#{zone} #{time} #{locale}"
    end
  end

  test "BlobPath reproduces rails_blob_path: Rails' signed id and its escaped, sanitized filename" do
    for %{"blob_id" => id, "filename" => filename, "path" => path} <- corpus("blob_paths.json"),
        do: assert(BlobPath.redirect_path(id, filename) == path, inspect(filename))
  end
end
