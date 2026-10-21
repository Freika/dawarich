defmodule Dawarich.Geocoding.FakeHttp do
  @moduledoc false
  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{responses: %{}, requests: [], sent: []} end, name: __MODULE__)
  end

  def stub(url, status, body), do: put(url, {:ok, status, body})
  def stub_error(url, reason), do: put(url, {:error, reason})
  def stub_raise(url), do: put(url, :raise)

  def requests, do: Agent.get(__MODULE__, & &1.requests)
  def sent, do: Agent.get(__MODULE__, & &1.sent)

  def get(url) do
    case fetch(url, []) do
      {:ok, status, body} -> {status, body}
    end
  end

  def request(url, headers) do
    case fetch(url, headers) do
      :raise -> raise "Dawarich.Geocoding.FakeHttp: stubbed failure for #{url}"
      response -> response
    end
  end

  defp put(url, response),
    do: Agent.update(__MODULE__, fn state -> put_in(state.responses[url], response) end)

  defp fetch(url, headers) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.fetch(state.responses, url) do
        {:ok, response} ->
          {{:ok, response},
           %{state | requests: state.requests ++ [url], sent: state.sent ++ [{url, headers}]}}

        :error ->
          {:error, state}
      end
    end)
    |> case do
      {:ok, response} -> response
      :error -> raise "Dawarich.Geocoding.FakeHttp: no recorded response for #{url}"
    end
  end
end
