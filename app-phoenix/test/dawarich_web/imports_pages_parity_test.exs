defmodule DawarichWeb.ImportsPagesParityTest do
  use Dawarich.IngestCase, async: false

  import Phoenix.ConnTest

  alias Dawarich.Test.{ParityHTML, RailsUser}

  @endpoint DawarichWeb.Endpoint
  @dir "test/fixtures/imports_pages"
  @external_resource "test/fixtures/imports_pages/pages.json"
  @original ~r/(<a class="btn btn-outline"[^>]*href=")[^"]*(")/
  @stimulus "[data-controller], [data-action], [data-upload-target], [data-turbo], [data-turbo-confirm], [data-turbo-frame], [data-disable-with]"

  setup do
    Repo.query!(
      File.read!(
        Path.expand("../../priv/repo/sql/20261001150000_import_download_requests.sql", __DIR__)
      ),
      [],
      query_type: :text
    )

    root = Path.join(System.tmp_dir!(), "imports-pages-" <> Ecto.UUID.generate())
    Application.put_env(:dawarich, :imports_storage, %{service: "local", root: root})

    on_exit(fn ->
      Application.delete_env(:dawarich, :imports_storage)
      File.rm_rf!(root)
    end)

    seed = @dir |> Path.join("seed.json") |> File.read!() |> Jason.decode!()
    load!(seed, root)
    :ok
  end

  defp load!(seed, root) do
    now = NaiveDateTime.utc_now()

    for u <- seed["users"],
        do:
          RailsUser.insert!(%{
            id: u["id"],
            email: u["email"],
            status: u["status"],
            settings: u["settings"]
          })

    for r <- seed["imports"] do
      data =
        Map.new(r["additional_data_extraction"], fn
          {"started_at", ago} -> {"started_at", stamp(NaiveDateTime.add(now, -ago))}
          pair -> pair
        end)

      {:ok, created, 0} = DateTime.from_iso8601(r["created_at"])

      Repo.insert_all("imports", [
        %{
          id: r["id"],
          user_id: r["user_id"],
          name: r["name"],
          source: r["source"],
          status: r["status"],
          raw_data: r["raw_data"],
          additional_data_extraction_status: r["additional_data_extraction_status"],
          additional_data_extraction: data,
          created_at: DateTime.to_naive(created),
          updated_at: now
        }
      ])

      for n <- List.duplicate(0, r["points"]) |> Enum.with_index(),
          do:
            Repo.query!(
              "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,$3,ST_SetSRID(ST_MakePoint(12.37,51.34),4326),now(),now())",
              [r["user_id"], r["id"], 1_790_000_000 + elem(n, 1)]
            )

      with [filename, original] <- r["file"] do
        blob =
          Dawarich.RailsBlobFixture.create!(Repo, root, filename, "PK",
            content_type: "application/zip",
            metadata: %{
              "dawarich_client_wrapped" => true,
              "dawarich_original_filename" => original
            }
          )

        Repo.query!(
          "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Import',$1,$2,now())",
          [r["id"], blob.id]
        )
      end
    end
  end

  defp stamp(naive), do: naive |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  for page <- "test/fixtures/imports_pages/pages.json" |> File.read!() |> Jason.decode!() do
    @page page

    test "#{page["name"]} matches the page Rails renders" do
      conn = get(RailsUser.signed_in(@page["user_id"]), @page["path"])
      html = conn |> response(@page["status"]) |> neutral()
      rails = Path.join(@dir, "pages/#{@page["name"]}.html") |> File.read!() |> neutral()

      native = ParityHTML.fragment(html, "div.px-4.flex-1 > div.flex > *")
      expected = ParityHTML.normalize(rails)

      assert native == expected,
             "#{@page["name"]}: " <> ParityHTML.first_difference(native, expected)

      assert wiring(inner(html)) == wiring(rails)
      assert html =~ "<title>#{@page["title"]}</title>"
    end
  end

  defp wiring(html) do
    html = String.replace(html, ~s(<turbo-frame data-turbo="false"), "<turbo-frame")

    for {tag, attrs} <- ParityHTML.stimulus(html, @stimulus),
        not delete_control?({tag, attrs}),
        do: {tag, List.keydelete(attrs, "data-testid", 0)}
  end

  defp delete_control?({"a", attrs}), do: {"data-turbo-method", "delete"} in attrs
  defp delete_control?({"form", [{"data-turbo", "false"}]}), do: true
  defp delete_control?(_), do: false

  defp inner(html),
    do:
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("div.px-4.flex-1 > div.flex > *")
      |> LazyHTML.to_html()

  defp neutral(html), do: Regex.replace(@original, html, "\\1ORIGINAL\\2")
end
