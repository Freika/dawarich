defmodule Dawarich.Geocoding.FakeHttp do
  @moduledoc false
  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{responses: %{}, requests: []} end, name: __MODULE__)
  end

  def stub(url, status, body) do
    Agent.update(__MODULE__, fn state -> put_in(state.responses[url], {status, body}) end)
  end

  def requests, do: Agent.get(__MODULE__, & &1.requests)

  def get(url) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.fetch(state.responses, url) do
        {:ok, response} -> {{:ok, response}, %{state | requests: state.requests ++ [url]}}
        :error -> {:error, state}
      end
    end)
    |> case do
      {:ok, {status, body}} -> {status, body}
      :error -> raise "Dawarich.Geocoding.FakeHttp: no recorded response for #{url}"
    end
  end
end
