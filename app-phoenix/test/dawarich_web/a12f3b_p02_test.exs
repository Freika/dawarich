defmodule DawarichWeb.A12f3bP02Test do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Posters.{Generation, NativeRenderer}
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Storage

  defmodule Client do
    @behaviour ExAws.Request.HttpClient
    def request(method, url, body, _headers, _opts) do
      key = URI.parse(url).path
      objects = Process.get(:poster_objects, %{})

      case method do
        :put ->
          Process.put(:poster_objects, Map.put(objects, key, body))
          send(self(), {:put, key})

          case Process.delete(:poster_failure) do
            :raise -> raise "upload acknowledgement lost"
            :exit -> exit(:upload_acknowledgement_lost)
            nil -> :ok
          end

        :delete ->
          Process.put(:poster_objects, Map.delete(objects, key))
      end

      {:ok, %{status_code: 200, headers: [], body: ""}}
    end
  end

  defmodule Tiles do
    def init(opts), do: opts
    def call(conn, _opts), do: Plug.Conn.send_resp(conn, 404, "")
  end

  setup do
    root = Path.join(System.tmp_dir!(), "poster-output-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    Ownership.put!(ScratchRepo, "command:posters.create", :oban)
    %{root: root, storage: %{root: root, service: "local"}}
  end

  @tag a12f3b_case: "P02a"
  test "poster generation renders every retained source style and attaches once", c do
    state = seed("points_gap_boundaries")
    Process.put(:poster_failure, :raise)
    event = Ecto.UUID.generate()

    assert :ok =
             Generation.run(state["before"]["id"], state["actor_id"], event, "de",
               repo: ScratchRepo,
               storage: s3(c.root),
               renderer: &render/3
             )

    assert rows("SELECT status FROM posters") == [[3]]
    assert rows("SELECT id FROM active_storage_attachments") == []
    assert Process.get(:poster_objects) == %{}
    assert Processed.done?(ScratchRepo, event)

    for name <- ~w(absent_points antimeridian timestamps/date_only points_gap_boundaries) do
      state = seed(name)
      id = state["before"]["id"]
      event = Ecto.UUID.generate()

      assert :ok =
               Generation.run(id, state["actor_id"], event, state["locale"],
                 repo: ScratchRepo,
                 storage: c.storage,
                 renderer: &render/3
               )

      assert rows("SELECT status FROM posters") == [[state["after"]["status"]]]
      files = rows("SELECT key,content_type FROM active_storage_blobs ORDER BY content_type")
      assert length(files) == length(state["attachments"])

      assert :ok =
               Generation.run(id, state["actor_id"], event, state["locale"],
                 repo: ScratchRepo,
                 renderer: fn _, _, _ -> flunk("event replay rendered") end
               )

      assert rows("SELECT key,content_type FROM active_storage_blobs ORDER BY content_type") ==
               files
    end

    state = seed("points_gap_boundaries")
    track = state["track"]

    poster = %{
      id: state["before"]["id"],
      name: "Synthetic",
      settings: state["before"]["settings"]
    }

    bandit = start_supervised!({Bandit, plug: Tiles, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, port}} = ThousandIsland.listener_info(bandit)

    for file <- Path.wildcard(Path.expand("../public/poster_themes/*.json")) do
      poster = %{
        poster
        | settings: Map.put(poster.settings, "theme", Path.basename(file, ".json"))
      }

      result =
        NativeRenderer.render(poster, track, "en",
          tiles_url: "http://127.0.0.1:#{port}/{z}/{x}/{y}.pbf"
        )

      assert <<137, 80, 78, 71, 13, 10, 26, 10, _::32, "IHDR", 2400::32, 3200::32, _::binary>> =
               result.png

      assert String.starts_with?(result.pdf, "%PDF-")
    end
  end

  @tag a12f3b_case: "P02b"
  test "poster retry preserves attachment identity after ambiguous upload", c do
    state = seed("points_gap_boundaries")
    id = state["before"]["id"]
    event = Ecto.UUID.generate()
    opts = [repo: ScratchRepo, storage: s3(c.root), renderer: &render/3]
    Process.put(:poster_failure, :exit)

    assert catch_exit(Generation.run(id, state["actor_id"], event, "en", opts)) ==
             :upload_acknowledgement_lost

    assert_receive {:put, original}
    refute Processed.done?(ScratchRepo, event)
    assert :ok = Generation.run(id, state["actor_id"], event, "en", opts)
    assert_receive {:put, retry}
    assert retry == original
    assert map_size(Process.get(:poster_objects)) == 2
    keys = rows("SELECT key FROM active_storage_blobs") |> List.flatten()
    assert length(keys) == 2
    assert rows("SELECT count(*) FROM active_storage_attachments") == [[2]]
    assert :ok = Generation.run(id, state["actor_id"], event, "en", opts)
    assert rows("SELECT key FROM active_storage_blobs") |> List.flatten() == keys
  end

  defp render(_, _, _), do: %{png: "synthetic png", pdf: "%PDF-synthetic"}

  defp s3(root) do
    config =
      Storage.config!(
        %{
          "STORAGE_BACKEND" => "s3",
          "AWS_ACCESS_KEY_ID" => "synthetic",
          "AWS_SECRET_ACCESS_KEY" => "synthetic",
          "AWS_REGION" => "eu-central-1",
          "AWS_BUCKET" => "synthetic"
        },
        root
      )

    %{config | ex_aws: Keyword.put(config.ex_aws, :http_client, Client)}
  end

  defp seed(name) do
    state = File.read!("test/fixtures/posters/#{name}.json") |> Jason.decode!()

    Dawarich.FixtureCleanup.delete!(
      ScratchRepo,
      ~w(public.active_storage_attachments public.active_storage_blobs public.posters public.points public.tracks public.users)
    )

    rows("DELETE FROM phoenix.processed_commands")

    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES($1,'poster@dawarich.test',now(),now())",
      [state["actor_id"]]
    )

    for {table, items} <- [
          {"posters", [state["before"]]},
          {"points", state["points"]},
          {"tracks", state["tracks"]}
        ],
        row <- items do
      rows(
        "INSERT INTO #{table} SELECT * FROM json_populate_record(NULL::#{table},$1::text::json)",
        [Jason.encode!(row)]
      )
    end

    state
  end
end
