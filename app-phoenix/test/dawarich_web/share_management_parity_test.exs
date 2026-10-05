defmodule DawarichWeb.ShareManagementParityTest do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  import Dawarich.Test.RawHTTP
  alias Dawarich.Test.{FrameSeeds, ParityHTML, RailsFormRequests, RailsUser}

  alias DawarichWeb.{
    LayoutAssigns,
    Locale,
    RailsCsrf,
    RailsForm,
    RequireUser,
    ShareManagementForm,
    ShareManagementPage
  }

  alias DawarichWeb.Api.Body
  @dir "test/fixtures/share_management"
  @cases ~w(ambiguous_override hub_active_live hub_active_shared hub_active_timeline hub_active_unknown
    hub_bad_range hub_empty_live hub_empty_make hub_empty_shared hub_empty_timeline hub_empty_unknown
    hub_guest hub_range live_active live_active_frame live_delete live_delete_missing
    live_expiry_America_Havana live_expiry_Asia_Tokyo live_expiry_Europe_Berlin live_expiry_UTC
    live_expiry_blank live_expiry_dst_after live_expiry_future live_expiry_malformed live_expiry_past
    live_hub_blank live_hub_false live_hub_true live_invalid_frame live_invalid_hub live_invalid_magic_phrase
    live_invalid_name live_json_create live_new_document live_new_frame live_phrase live_phrase_missing
    live_revoke live_revoke_missing live_settings live_turbo_create live_url live_url_missing
    shared_revoke_foreign shared_revoke_live shared_revoke_missing shared_revoke_timeline shared_revoke_track
    shared_revoke_trip trip_active trip_active_frame trip_delete trip_delete_missing trip_expiry_blank
    trip_expiry_dst_after trip_expiry_future trip_expiry_malformed trip_expiry_past trip_foreign
    trip_invalid_magic_phrase trip_invalid_name trip_missing trip_new_document trip_new_frame trip_phrase
    trip_phrase_missing trip_revoke trip_revoke_missing trip_settings trip_url trip_url_missing)
  @names [
    "failed_live_replacement"
    | for(name <- @cases, locale <- ~w(en de es fr pl ca zh), do: name <> "_" <> locale)
  ]

  @tag mutation: "corpus"
  test "management corpus is complete" do
    actual =
      @dir |> Path.join("*.json") |> Path.wildcard() |> Enum.map(&Path.basename(&1, ".json"))

    assert Enum.sort(actual) == Enum.sort(@names)
    assert length(@names) == 505
  end

  for name <- @names do
    @name name
    @tag management_case: name
    test "management #{@name} matches Rails" do
      state = load(@name)
      user = FrameSeeds.seed_management!(@name)
      now = state["now"] |> DateTime.from_iso8601() |> elem(1)
      rails = File.read!(Path.join(@dir, @name <> ".html"))
      session = if user, do: RailsUser.session(user.id), else: %{}
      {conn, body} = request(state, user, session, now)

      conn =
        if replay?(state) do
          upstream = RailsFormRequests.upstream!()
          task = Task.async(fn -> respond(conn, state) end)
          socket = accept(upstream)
          {head, rest} = read_head(socket)
          length = header(head, "content-length") |> List.first("0") |> String.to_integer()
          assert read_at_least(socket, rest, length) == body
          assert request_line(head) == state["verb"] <> " " <> state["path"] <> " HTTP/1.1"
          assert rows() == state["before"]
          assert commands() == []

          response_headers =
            if state["location"], do: "Location: #{state["location"]}\r\n", else: ""

          reply(
            socket,
            "HTTP/1.1 #{state["status"]} Fixture\r\nContent-Type: #{state["content_type"]}\r\n#{response_headers}Content-Length: #{byte_size(rails)}\r\n\r\n" <>
              rails
          )

          result = Task.await(task)
          :gen_tcp.close(socket)
          assert rows() == state["before"]
          result
        else
          result = respond(conn, state)
          assert normalize_rows(rows(), state) == normalize_rows(state["after"], state)
          assert events() == state["events"]
          result
        end

      assert conn.status == state["status"]
      assert get_resp_header(conn, "location") == List.wrap(state["location"])

      assert conn |> get_resp_header("content-type") |> hd() |> String.split(";") |> hd() ==
               state["content_type"]

      if not replay?(state) do
        changes = conn.private[:dawarich_rails_session_changes] || %{}
        assert (get_in(changes, ["flash", "flashes"]) || %{}) == state["flash"]
        if state["flash"] != %{}, do: assert_cookie(conn)
        if state["verb"] != "GET" and state["flash"] == %{}, do: assert(conn.resp_cookies == %{})
      end

      if conn.status in [200, 422] do
        native = fragment(conn.resp_body)
        actual = normalize(native, state)
        expected = normalize(rails, state)
        assert actual == expected, ParityHTML.first_difference(actual, expected)
        assert attributes(native, state) == attributes(rails, state)
      else
        assert normalize(conn.resp_body, state) == normalize(rails, state)
      end
    end
  end

  defp load(name), do: Path.join(@dir, name <> ".json") |> File.read!() |> Jason.decode!()

  defp request(state, user, session, now) do
    body =
      if state["json_request"], do: Jason.encode!(state["params"]), else: encode(state["params"])

    type =
      if state["json_request"], do: "application/json", else: "application/x-www-form-urlencoded"

    conn =
      Plug.Test.conn(state["verb"], state["path"], body)
      |> Map.put(:host, "www.example.com")
      |> put_req_header("content-type", type)
      |> put_req_header("content-length", to_string(byte_size(body)))
      |> put_req_header("x-csrf-token", RailsCsrf.masked_token(session) || "")
      |> assign(:api_tag, "form")
      |> assign(:current_user, user)
      |> assign(:rails_session, session)
      |> assign(:now, now)

    conn =
      Enum.reduce(state["headers"], conn, fn {key, value}, conn ->
        put_req_header(conn, String.downcase(key), value)
      end)

    info =
      Phoenix.Router.route_info(DawarichWeb.Router, state["verb"], conn.request_path, conn.host)

    conn = %{conn | path_params: info.path_params}

    if state["verb"] == "GET" do
      conn =
        conn
        |> fetch_query_params()
        |> Locale.call([])
        |> LayoutAssigns.call([])
        |> assign(:now, now)

      {conn, body}
    else
      {conn, body}
    end
  end

  defp respond(conn, %{"verb" => "GET"}) do
    conn = RequireUser.call(conn, [])

    if conn.halted do
      conn
    else
      action =
        Phoenix.Router.route_info(DawarichWeb.Router, "GET", conn.request_path, conn.host).plug_opts

      ShareManagementPage.render(conn, action)
    end
  end

  defp respond(conn, state) do
    conn = Body.call(conn, nested_form: "shared_link")
    conn = if conn.halted, do: conn, else: RailsForm.call(conn, [])

    if conn.halted do
      conn
    else
      action =
        Phoenix.Router.route_info(DawarichWeb.Router, state["verb"], conn.request_path, conn.host).plug_opts

      ShareManagementForm.call(conn, action)
    end
  end

  defp replay?(state) do
    state["json_request"] or Map.has_key?(state["headers"], "X-HTTP-Method-Override") or
      (state["verb"] == "POST" and state["path"] == "/share_links/live" and state["status"] == 422) or
      (state["path"] =~ "/share_links/shares/" and String.ends_with?(state["path"], "/revoke") and
         Enum.any?(state["before"], fn row ->
           String.contains?(state["path"], row["id"]) and row["resource_type"] in [1, 2]
         end))
  end

  defp encode(params) do
    params
    |> pairs()
    |> Enum.map_join("&", fn {key, value} ->
      URI.encode_www_form(key) <> "=" <> URI.encode_www_form(to_string(value))
    end)
  end

  defp pairs(map, prefix \\ nil) do
    Enum.flat_map(map, fn {key, value} ->
      key = if prefix, do: prefix <> "[" <> key <> "]", else: key
      if is_map(value), do: pairs(value, key), else: [{key, value}]
    end)
  end

  defp rows,
    do:
      Repo.query!("SELECT row_to_json(t) FROM shared_links t ORDER BY id").rows |> List.flatten()

  defp events do
    for ["share_management.live_revoked", payload] <- commands() do
      %{
        "stream" =>
          "shared_location:" <>
            Base.encode64("gid://dawarich/SharedLink/" <> payload["share_id"], padding: false),
        "message" => %{"revoked" => true}
      }
    end
  end

  defp normalize_rows(rows, state) do
    before = Enum.map(state["before"], & &1["id"])

    Enum.map(rows, fn row ->
      row = if row["id"] in before, do: row, else: Map.put(row, "id", "NEW-ID")

      if String.ends_with?(state["path"], "regenerate_phrase") and
           row["magic_phrase"] not in [nil, "old-fixture-phrase"],
         do: Map.put(row, "magic_phrase", "PHRASE"),
         else: row
    end)
    |> Enum.sort_by(& &1["id"])
  end

  defp fragment(html) do
    doc = LazyHTML.from_document(html)
    frame = LazyHTML.query(doc, "turbo-frame#share-link-modal")
    if Enum.any?(frame), do: LazyHTML.to_html(frame), else: html
  end

  defp canonical(html, state) do
    html = Regex.replace(~r/\b(required|checked|readonly)="\1"/, html, "\\1")

    html =
      Regex.replace(
        ~r/(name="shared_link\[magic_phrase\]"[^>]*value=")[^"]*"/,
        html,
        "\\1PHRASE\""
      )

    html =
      Regex.replace(
        ~r/(value=")[^"]*("[^>]*name="shared_link\[magic_phrase\]")/,
        html,
        "\\1PHRASE\\2"
      )

    before = Enum.map(state["before"], & &1["id"])

    Regex.replace(
      ~r/a9f10000-0000-4000-8000-\d{12}|[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/,
      html,
      fn id -> if id in before, do: id, else: "NEW-ID" end
    )
  end

  defp normalize(html, state), do: html |> canonical(state) |> ParityHTML.normalize()
  defp attributes(html, state), do: html |> canonical(state) |> ParityHTML.stimulus("*")

  defp assert_cookie(conn) do
    assert %{http_only: true, same_site: "Lax", path: "/"} =
             conn.resp_cookies["_dawarich_session"]
  end
end
