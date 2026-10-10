defmodule Dawarich.Test.RateLimitCorpus do
  @moduledoc false

  @path Path.expand("../fixtures/rate_limit/corpus.json", __DIR__)
  @external_resource @path

  def corpus do
    with nil <- :persistent_term.get({__MODULE__, :corpus}, nil) do
      data = @path |> File.read!() |> Jason.decode!()
      :persistent_term.put({__MODULE__, :corpus}, data)
      data
    end
  end

  def request_conn(r) do
    target = if r["query"] in [nil, ""], do: r["path"], else: r["path"] <> "?" <> r["query"]
    conn = Plug.Test.conn(r["method"], "http://www.example.com" <> target, r["body"] || "")
    {:ok, ip} = r["remote_addr"] |> String.to_charlist() |> :inet.parse_address()

    %{
      conn
      | remote_ip: ip,
        req_headers: conn.req_headers ++ Enum.map(r["headers"] || [], &List.to_tuple/1)
    }
  end

  def key(%{"window" => window, "throttle" => throttle, "discriminator" => discriminator}),
    do: "rack::attack:#{window}:#{throttle}:#{discriminator}"
end
