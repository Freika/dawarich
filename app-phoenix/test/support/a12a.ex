defmodule Dawarich.Test.A12a do
  @moduledoc false

  import ExUnit.Callbacks, only: [start_supervised!: 1]

  alias Dawarich.Accounts.User
  alias Dawarich.Cable.Bus
  alias Dawarich.RailsMessages
  alias DawarichWeb.CableProxy.Frame
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Repo

  @tables ~w(users families family_memberships shared_links notifications trips)
  @host "www.example.com"
  @ed_cases ~w(version_8 message_action_subscribed)

  @path Path.expand("../fixtures/a12a/cable.json", __DIR__)
  @external_resource @path
  @corpus @path |> File.read!() |> Jason.decode!()

  def corpus, do: @corpus
  def cases(section), do: for(%{"section" => ^section} = c <- @corpus["cases"], do: c)

  def case!(name),
    do: Enum.find(@corpus["cases"], &(&1["name"] == name)) || raise("no case #{name}")

  def now do
    {:ok, at, 0} = DateTime.from_iso8601(@corpus["now"])
    at
  end

  def secret, do: Application.fetch_env!(:dawarich, :rails_secret)
  def test_redis_url, do: Application.fetch_env!(:dawarich, :redis)[:url]

  def identifier(c) do
    c["steps"]
    |> Enum.flat_map(fn
      %{"send" => text} ->
        case Jason.decode(text) do
          {:ok, %{"command" => "subscribe", "identifier" => id}} -> [id]
          _ -> []
        end

      _ ->
        []
    end)
    |> List.last()
  end

  def term(%{"object" => pairs}), do: {:object, Enum.map(pairs, fn [k, v] -> {k, term(v)} end)}
  def term(%{"float" => text}), do: Ruby.float(text)
  def term(list) when is_list(list), do: Enum.map(list, &term/1)
  def term(other), do: other

  def seed! do
    for table <- @tables do
      rows = for row <- @corpus["rows"][table], do: Map.new(row, &column(table, &1))
      Repo.insert_all(table, rows)
    end

    :ok
  end

  defp column("shared_links", {"id", id}), do: {:id, Ecto.UUID.dump!(id)}

  defp column(_table, {name, value}) when is_binary(value) do
    if String.ends_with?(name, ["_at", "_until"]),
      do: {String.to_atom(name), NaiveDateTime.from_iso8601!(value)},
      else: {String.to_atom(name), value}
  end

  defp column(_table, {name, value}), do: {String.to_atom(name), value}

  def user!(name), do: Repo.get!(User, @corpus["users"][name])
  def share!(name), do: %{id: @corpus["shares"][name], magic_phrase: phrase(name)}
  def family_id!(name), do: @corpus["families"][name]
  def trip_id!(name), do: @corpus["trips"][name]

  defp phrase(name) do
    id = @corpus["shares"][name]
    Enum.find_value(@corpus["rows"]["shared_links"], &(&1["id"] == id && &1["magic_phrase"]))
  end

  def expected_identity(c) do
    case hd(c["steps"]) do
      %{"expect" => ~s({"type":"welcome"})} -> :welcome
      %{"expect" => ~s({"type":"disconnect") <> _} -> :unauthorized
      %{"silent_ms" => _} -> :silent
    end
  end

  def expected_decision(name) do
    case List.last(case!(name)["steps"]) do
      %{"silent_ms" => _} -> :ignore
      %{"expect" => frame} -> if frame =~ "reject_subscription", do: :reject, else: :confirm
    end
  end

  def outcome({:ok, %{}}), do: :welcome
  def outcome(other), do: other

  def share_param(c) do
    [_path, query] = String.split(c["path"], "?", parts: 2)
    Plug.Conn.Query.decode(query)["share_id"]
  end

  def start_bus! do
    for spec <- Bus.child_specs(bus: true, url: test_redis_url(), database: 2),
        do: start_supervised!(spec)

    start_supervised!({Redix, {test_redis_url(), [name: Dawarich.Redis]}})
    :ok
  end

  def publish!(broadcasting, payload) do
    {:ok, _} =
      Redix.command(Dawarich.Redis, ["PUBLISH", "dawarich_a12a:" <> broadcasting, payload])

    :ok
  end

  def serve_cable!(opts \\ []) do
    base = [
      now: now(),
      secret: secret(),
      self_hosted: true,
      beat_ms: 3_000,
      env: %{"RAILS_ENV" => "test"}
    ]

    plug = {DawarichWeb.Cable, Keyword.merge(base, opts)}
    spec = {Bandit, [plug: plug] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
    bandit = start_supervised!(Supervisor.child_spec(spec, id: make_ref()))
    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    port
  end

  def ed_cases, do: @ed_cases

  def cookie(names) do
    names
    |> List.wrap()
    |> Enum.map_join("; ", fn name ->
      session = @corpus["sessions"][name]
      session["cookie"] <> "=" <> session["value"]
    end)
  end

  def open!(port, cookie) do
    headers = [{"Origin", "http://" <> @host}, {"Cookie", cookie}]
    socket = Dawarich.Test.RawHTTP.ws_request(port, "/cable", headers, @host)
    {101, _headers} = response_head(socket)
    socket
  end

  def request!(port, c) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 5_000)
    cookie = if c["cookies"] == [], do: [], else: [["Cookie", cookie(c["cookies"])]]

    head = [
      "#{c["method"]} #{c["path"]} HTTP/1.1\r\nHost: #{@host}\r\n",
      for([name, value] <- c["headers"] ++ cookie, do: "#{name}: #{value}\r\n"),
      "\r\n"
    ]

    :ok = :gen_tcp.send(socket, head)
    socket
  end

  def response_head(socket, acc \\ "") do
    case :binary.split(acc, "\r\n\r\n") do
      [head, rest] ->
        Process.put({__MODULE__, socket}, rest)
        [status_line | lines] = String.split(head, "\r\n")
        [_, status | _] = String.split(status_line, " ", parts: 3)

        headers =
          for line <- lines,
              [k, v] <- [String.split(line, ":", parts: 2)],
              do: {String.downcase(k), String.trim(v)}

        {String.to_integer(status), headers}

      [_] ->
        {:ok, data} = :gen_tcp.recv(socket, 0, 5_000)
        response_head(socket, acc <> data)
    end
  end

  def recv_frame(socket, timeout) do
    case Process.get({__MODULE__, :frames, socket}, []) do
      [frame | rest] ->
        Process.put({__MODULE__, :frames, socket}, rest)
        frame

      [] ->
        buffer = Process.get({__MODULE__, socket}, "")
        {:ok, frames, tail} = Frame.decode(buffer)
        Process.put({__MODULE__, socket}, tail)
        Process.put({__MODULE__, :frames, socket}, frames)
        if frames == [], do: recv_more(socket, tail, timeout), else: recv_frame(socket, timeout)
    end
  end

  defp recv_more(socket, tail, timeout) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, data} ->
        Process.put({__MODULE__, socket}, tail <> data)
        recv_frame(socket, timeout)

      {:error, reason} ->
        reason
    end
  end

  def next_frame(socket, timeout \\ 2_000) do
    case recv_frame(socket, timeout) do
      {_fin, :text, ~s({"type":"ping") <> _} -> next_frame(socket, timeout)
      {_fin, :text, text} -> %{"expect" => text}
      {_fin, :close, <<code::16, _::binary>>} -> %{"close" => code}
      {_fin, kind, payload} -> %{"unexpected" => [Atom.to_string(kind), payload]}
      reason -> %{"error" => inspect(reason)}
    end
  end

  def ws_recv_json(socket) do
    {_fin, :text, text} = recv_frame(socket, 2_000)
    Jason.decode!(text)
  end

  def ws_recv_any(socket, timeout) do
    case recv_frame(socket, timeout) do
      :timeout -> :timeout
      frame -> frame
    end
  end

  def send_text(socket, text), do: :ok = :gen_tcp.send(socket, Frame.encode(:text, text))

  def replay(port, c) do
    socket = request!(port, c)

    try do
      observe(socket, c)
    after
      :gen_tcp.close(socket)
    end
  end

  defp observe(socket, c) do
    {status, headers} = response_head(socket)
    protocol = List.first(for {"sec-websocket-protocol", v} <- headers, do: v)

    if status == 101 do
      {status, protocol, nil, nil, Enum.map(c["steps"], &replay_step(socket, &1))}
    else
      length = String.to_integer(List.first(for {"content-length", v} <- headers, do: v))
      body = read_body(socket, Process.get({__MODULE__, socket}, ""), length)
      {status, protocol, List.first(for {"content-type", v} <- headers, do: v), body, []}
    end
  end

  def recorded(c), do: {c["status"], c["protocol"], c["content_type"], c["body"], c["steps"]}

  defp read_body(_socket, acc, length) when byte_size(acc) >= length,
    do: binary_part(acc, 0, length)

  defp read_body(socket, acc, length) do
    {:ok, data} = :gen_tcp.recv(socket, 0, 5_000)
    read_body(socket, acc <> data, length)
  end

  defp replay_step(socket, %{"send" => text} = step) do
    send_text(socket, text)
    step
  end

  defp replay_step(socket, %{"send_binary" => data} = step) do
    :ok = :gen_tcp.send(socket, Frame.encode(:binary, Base.decode64!(data)))
    step
  end

  defp replay_step(_socket, %{"publish" => %{"broadcasting" => b, "payload" => p}} = step) do
    publish!(b, p)
    step
  end

  defp replay_step(socket, %{"silent_ms" => _} = step) do
    case next_frame(socket, 200) do
      %{"error" => ":timeout"} -> step
      other -> other
    end
  end

  defp replay_step(socket, _expect_or_close), do: next_frame(socket)

  def conn_with(opts) do
    conn = Plug.Test.conn(:get, "/cable")
    conn = %{conn | req_headers: [{"host", @host} | conn.req_headers]}
    conn = if o = opts[:origin], do: Plug.Conn.put_req_header(conn, "origin", o), else: conn

    if p = opts[:forwarded_proto],
      do: Plug.Conn.put_req_header(conn, "x-forwarded-proto", p),
      else: conn
  end

  def broadcasting(channel, who),
    do: RailsMessages.broadcasting([channel, {:user, @corpus["users"][who]}])

  def subscribe_frame(channel),
    do: Jason.encode!(%{command: "subscribe", identifier: Jason.encode!(%{channel: channel})})

  def unsubscribe_frame(channel),
    do: Jason.encode!(%{command: "unsubscribe", identifier: Jason.encode!(%{channel: channel})})

  def subscribed(b),
    do: {:redix_pubsub, self(), make_ref(), :subscribed, %{channel: Bus.channel(b)}}

  def redis_message(b, payload),
    do:
      {:redix_pubsub, self(), make_ref(), :message, %{channel: Bus.channel(b), payload: payload}}

  def init_state(identity) do
    %{
      identity: identity,
      context: %{secret: secret(), now: &now/0, self_hosted: true},
      beat_ms: 3_000,
      subs: %{}
    }
  end

  def socket_state(identity), do: %{init_state(identity) | identity: identity}

  def confirmed_state(channel, who) do
    b = broadcasting(channel |> String.replace_suffix("Channel", "") |> Macro.underscore(), who)
    {:ok, _} = Bus.subscribe(b)
    id = Jason.encode!(%{channel: channel})
    %{socket_state(%{user: user!(who), share: nil}) | subs: %{id => {b, :confirmed}}}
  end

  def streamables(parts),
    do:
      Enum.map(parts, fn
        [model, id] -> {String.to_atom(model), id}
        part -> part
      end)

  def relay!(name), do: @corpus["relay"][name]
  def relay_payload(name), do: name |> relay!() |> Map.fetch!("published") |> hd() |> List.last()

  def listen(broadcasting) do
    pid = listener()
    {:ok, ref} = Redix.PubSub.subscribe(pid, Bus.channel(broadcasting), self())

    receive do
      {:redix_pubsub, ^pid, ^ref, :subscribed, _} -> {:ok, ref}
    after
      2_000 -> raise "no subscription to #{broadcasting}"
    end
  end

  def listen_all do
    pid = listener()
    {:ok, ref} = Redix.PubSub.psubscribe(pid, "dawarich_a12a:*", self())

    receive do
      {:redix_pubsub, ^pid, ^ref, :psubscribed, _} -> {:ok, ref}
    after
      2_000 -> raise "no pattern subscription"
    end
  end

  def heard(timeout \\ 2_000) do
    receive do
      {:redix_pubsub, _pid, _ref, kind, %{channel: channel, payload: payload}}
      when kind in [:message, :pmessage] ->
        {String.replace_prefix(channel, "dawarich_a12a:", ""), payload}
    after
      timeout -> :nothing
    end
  end

  defp listener do
    case Process.whereis(:a12a_listener) do
      nil ->
        start = {Redix.PubSub, :start_link, [test_redis_url(), [name: :a12a_listener]]}
        start_supervised!(%{id: :a12a_listener, start: start})

      pid ->
        pid
    end
  end

  def producer_inputs, do: @corpus["producers"]

  def phoenix_encoding(%{"channel" => channel, "streamables" => parts, "input" => input} = p) do
    parts = if channel, do: [channel | streamables(parts)], else: streamables(parts)

    %{
      "name" => p["name"],
      "broadcasting" => RailsMessages.broadcasting(parts),
      "payload" => Dawarich.Cable.Frames.payload(term(input))
    }
  end
end
