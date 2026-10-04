defmodule DawarichWeb.PostersParityTest do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  import Dawarich.Test.RawHTTP
  alias Dawarich.Test.{ApiGolden, FrameSeeds, ParityHTML, RailsFormRequests, RailsUser}
  alias DawarichWeb.{MapGalleryCards, PostersController, RailsCsrf, RailsForm}
  alias DawarichWeb.Api.Body
  @dir "test/fixtures/posters"
  @requests ~w(create_whitelist create_blank_name create_blank_title create_missing_title create_error_true create_error_false delete_true delete_false delete_foreign)
  @cards ~w(absent_points already_completed_without_pair antimeridian clamps_high clamps_low clamps_zero deletion_during_render missing_job_row null_lonlat outside_frame overlapping_tracks_theme_basename phase_drawing_map phase_drawing_route phase_fetching_data phase_saving phase_unknown points_gap_boundaries render_title_0 render_title_1 unknown_theme)
  @names for(name <- @requests, locale <- ~w(en de), do: name <> "_" <> locale) ++ @cards

  @tag mutation: "poster-corpus"
  test "poster response corpus is complete" do
    assert Enum.sort(Path.wildcard(@dir <> "/*.json") |> Enum.map(&Path.basename(&1, ".json"))) ==
             Enum.sort(@names)
  end

  for name <- @names do
    @name name
    @group (cond do
              String.starts_with?(name, "create_whitelist") -> "create_stream"
              String.starts_with?(name, "create_error_true") -> "error_stream"
              String.starts_with?(name, "create_error_false") -> "error_html"
              String.starts_with?(name, "create_") -> "create_html"
              String.starts_with?(name, "delete_true") -> "delete_stream"
              String.starts_with?(name, "delete_false") -> "delete_html"
              String.starts_with?(name, "delete_foreign") -> "foreign"
              name in ~w(deletion_during_render missing_job_row) -> "missing_card"
              true -> "card"
            end)
    @tag p2_group: @group
    @tag poster_case: name
    test "poster response #{@name} matches Rails" do
      state = File.read!(@dir <> "/" <> @name <> ".json") |> Jason.decode!()
      rails = File.read!(@dir <> "/" <> @name <> ".html")

      if state["verb"] do
        user =
          FrameSeeds.user!(state["actor_id"], %{"locale" => state["locale"], "timezone" => "UTC"})

        for row <- state["before"], do: ApiGolden.insert!("posters", row)

        if String.starts_with?(@name, "delete_foreign") do
          foreign = FrameSeeds.user!(97102)

          Repo.insert_all("posters", [
            %{
              id: String.split(state["path"], "/") |> List.last() |> String.to_integer(),
              name: "Foreign",
              user_id: foreign.id,
              status: 0,
              settings: %{},
              created_at: ~N[2026-10-03 10:00:00],
              updated_at: ~N[2026-10-03 10:00:00]
            }
          ])
        end

        body = encode(state["params"])
        session = RailsUser.session(user.id)

        conn =
          Plug.Test.conn(state["verb"], state["path"], body)
          |> Map.put(:host, "www.example.com")
          |> put_req_header("content-type", "application/x-www-form-urlencoded")
          |> put_req_header("content-length", to_string(byte_size(body)))
          |> put_req_header(
            "accept",
            if(state["turbo"], do: "text/vnd.turbo-stream.html", else: "text/html")
          )
          |> put_req_header("x-csrf-token", RailsCsrf.masked_token(session))
          |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(session))
          |> assign(:api_tag, "form")
          |> assign(:current_user, user)
          |> assign(:rails_session, session)

        info =
          Phoenix.Router.route_info(DawarichWeb.Router, state["verb"], state["path"], conn.host)

        assert %{plug: PostersController} = info
        conn = %{conn | path_params: info.path_params}

        conn =
          if String.starts_with?(@name, "delete_foreign") do
            upstream = RailsFormRequests.upstream!()
            assert DawarichWeb.PostersGate.native?(conn, info.path_params) == false

            task =
              Task.async(fn ->
                Body.call(conn, nested_form: "poster") |> Body.replay("missing poster")
              end)

            socket = accept(upstream)
            {head, rest} = read_head(socket)
            assert request_line(head) == state["verb"] <> " " <> state["path"] <> " HTTP/1.1"
            assert read_at_least(socket, rest, byte_size(body)) == body

            reply(
              socket,
              "HTTP/1.1 404 Not Found\r\nContent-Type: text/html\r\nContent-Length: #{byte_size(rails)}\r\n\r\n" <>
                rails
            )

            result = Task.await(task)
            :gen_tcp.close(socket)
            result
          else
            conn
            |> Body.call(nested_form: "poster")
            |> RailsForm.call([])
            |> PostersController.call(info.plug_opts)
          end

        assert conn.status == state["status"]
        assert get_resp_header(conn, "location") == List.wrap(state["location"])

        assert get_resp_header(conn, "content-type") |> hd() |> String.split(";") |> hd() ==
                 state["content_type"]

        assert (get_in(conn.private[:dawarich_rails_session_changes] || %{}, ["flash", "flashes"]) ||
                  %{}) == state["flash"]

        if state["flash"] != %{} do
          assert %{http_only: true, same_site: "Lax", path: "/"} =
                   conn.resp_cookies["_dawarich_session"]
        else
          assert conn.resp_cookies == %{}
        end

        before_ids = Enum.map(state["before"], & &1["id"])

        assert normalize_rows(rows(user.id), before_ids) ==
                 normalize_rows(state["after"], before_ids)

        new = Enum.reject(rows(user.id), &(&1["id"] in before_ids))

        assert Enum.map(commands(), fn [kind, payload] ->
                 [kind, payload["poster_id"], payload["user_id"], payload["locale"]]
               end) ==
                 Enum.map(new, &["posters.created", &1["id"], user.id, state["locale"]])

        assert_html(conn.resp_body, rails, before_ids)
      else
        case state["after"] || state["poster"] do
          nil ->
            assert rails == ""

            assert Dawarich.MapGallery.poster(
                     state["actor_id"] || 97101,
                     get_in(state, ["before", "id"]) || 96999
                   ) == nil

          row ->
            FrameSeeds.user!(row["user_id"])
            ApiGolden.insert!("posters", row)

            for attachment <- state["attachments"] || [] do
              stamp = ~N[2026-10-03 10:00:00]

              {1, [%{id: blob}]} =
                Repo.insert_all(
                  "active_storage_blobs",
                  [
                    %{
                      key: "a9-#{row["id"]}-#{attachment["name"]}",
                      filename: attachment["filename"],
                      service_name: "local",
                      byte_size: attachment["byte_size"],
                      created_at: stamp
                    }
                  ],
                  returning: [:id]
                )

              Repo.insert_all("active_storage_attachments", [
                %{
                  record_type: "Poster",
                  record_id: row["id"],
                  name: attachment["name"],
                  blob_id: blob,
                  created_at: stamp
                }
              ])
            end

            poster = Dawarich.MapGallery.poster(row["user_id"], row["id"])

            native =
              MapGalleryCards.poster_card(%{
                __changed__: nil,
                poster: poster,
                locale: state["locale"] || "de"
              })
              |> Phoenix.HTML.Safe.to_iodata()
              |> IO.iodata_to_binary()

            assert_html(native, rails, [row["id"]])
        end
      end
    end
  end

  defp rows(user),
    do:
      Repo.query!("SELECT row_to_json(t) FROM posters t WHERE user_id=$1 ORDER BY id", [user]).rows
      |> List.flatten()

  defp normalize_rows(rows, before_ids) do
    Enum.map(rows, fn row ->
      row = Map.drop(row, ~w(created_at updated_at))
      if row["id"] in before_ids, do: row, else: Map.put(row, "id", "NEW")
    end)
    |> Enum.sort_by(& &1["id"])
  end

  defp encode(params),
    do:
      Enum.flat_map(params, fn {key, value} ->
        if is_map(value),
          do: Enum.map(value, fn {field, item} -> {key <> "[" <> field <> "]", item} end),
          else: [{key, value}]
      end)
      |> URI.encode_query()

  defp canonical(html, before_ids) do
    html =
      Regex.replace(
        ~r{(/rails/active_storage/blobs/(?:redirect|proxy)/)[^/"?]+},
        html,
        "\\1SIGNED"
      )

    Regex.replace(~r{poster_(\d+)|/posters/(\d+)}, html, fn text, first, last ->
      id = String.to_integer(if first == "", do: last, else: first)
      if id in before_ids, do: text, else: String.replace(text, to_string(id), "NEW")
    end)
  end

  defp assert_html(native, rails, ids) do
    native = canonical(native, ids)
    rails = canonical(rails, ids)
    actual = ParityHTML.normalize(native)
    expected = ParityHTML.normalize(rails)
    assert actual == expected, ParityHTML.first_difference(actual, expected)
    assert ParityHTML.stimulus(native, "*") == ParityHTML.stimulus(rails, "*")
  end
end
