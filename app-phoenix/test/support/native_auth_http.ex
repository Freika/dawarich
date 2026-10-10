defmodule Dawarich.Test.NativeAuthHTTP do
  @moduledoc false

  def post_form(session, body, headers \\ [], path \\ "/exports") do
    import Plug.Conn
    import Phoenix.ConnTest

    conn =
      Enum.reduce(headers, build_conn(), fn {name, value}, conn ->
        put_req_header(conn, name, value)
      end)

    conn
    |> Map.put(:remote_ip, {192, 0, 2, 33})
    |> put_req_cookie("_dawarich_session", Dawarich.Test.RailsUser.cookie(session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded;charset=UTF-8")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> dispatch(DawarichWeb.Endpoint, :post, path, body)
  end

  def isolate_counters(actor_id \\ nil) do
    now = System.os_time(:second)

    keys =
      for at <- [now, now + 900],
          do:
            DawarichWeb.RateLimit.Rules.key(
              at,
              900,
              "auth/account_link_challenge_ip",
              "192.0.2.33"
            )

    keys =
      keys ++
        if actor_id,
          do:
            for(
              at <- [now, now + 900],
              do:
                DawarichWeb.RateLimit.Rules.key(
                  at,
                  900,
                  "auth/account_link_challenge_session",
                  actor_id
                )
            ),
          else: []

    cleanup = fn ->
      for key <- keys,
          do:
            Dawarich.ScratchRepo.query!("DELETE FROM phoenix.counters WHERE key=$1", [key],
              log: false
            )
    end

    cleanup.()
    ExUnit.Callbacks.on_exit(cleanup)
  end

  def fields(html) do
    for node <- LazyHTML.query(LazyHTML.from_fragment(html), "input") do
      for key <- ~w(name type value id) do
        value =
          if key == "value" and LazyHTML.attribute(node, "name") == ["authenticity_token"],
            do: ["CSRF"],
            else: LazyHTML.attribute(node, key)

        {key, value}
      end
    end
  end

  def text(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.map(fn node ->
      LazyHTML.text(node) |> String.replace(~r/\s+/, " ") |> String.trim()
    end)
    |> Enum.join(" ")
  end
end
