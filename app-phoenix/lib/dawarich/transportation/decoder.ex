defmodule Dawarich.Transportation.Decoder do
  @moduledoc false

  alias Dawarich.RubyFloat
  alias Dawarich.Transportation.Emissions

  @hubs ["stationary", "walking"]

  def call([], _enabled), do: []

  def call(windows, enabled) do
    windows
    |> split_chains()
    |> Enum.flat_map(&decode_chain(&1, enabled))
  end

  defp transition_penalty(from, from), do: 0.0

  defp transition_penalty(from, to) do
    cond do
      to == "flying" or from == "flying" -> -6.0
      from in @hubs or to in @hubs -> -2.5
      Enum.sort([from, to]) == ["driving", "train"] -> -8.0
      true -> -5.0
    end
  end

  defp split_chains(windows) do
    {chains, current} =
      Enum.reduce(windows, {[], []}, fn window, {chains, current} ->
        if window.gap_before and current != [] do
          {[Enum.reverse(current) | chains], [window]}
        else
          {chains, [window | current]}
        end
      end)

    chains = if current == [], do: chains, else: [Enum.reverse(current) | chains]
    Enum.reverse(chains)
  end

  defp decode_chain(chain, enabled) do
    emissions = Enum.map(chain, &Emissions.log_likelihoods(&1, enabled))
    modes = emissions |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()

    if modes == [] do
      Enum.map(chain, fn _ -> %{mode: "unknown", posterior: 0.0} end)
    else
      path = viterbi(emissions, modes)
      posteriors = forward_backward(emissions, modes)

      path
      |> Enum.with_index()
      |> Enum.map(fn {mode, i} ->
        posterior = posteriors |> Enum.at(i) |> Map.get(mode, 0.0)
        %{mode: mode, posterior: RubyFloat.round(posterior, 4)}
      end)
    end
  end

  defp viterbi(emissions, modes) do
    emissions_tuple = List.to_tuple(emissions)
    first = Map.new(modes, fn m -> {m, emission_score(elem(emissions_tuple, 0), m)} end)
    n = tuple_size(emissions_tuple)

    {final_scores, backpointers} =
      Enum.reduce(1..(n - 1)//1, {first, []}, fn i, {scores, backpointers} ->
        {new_scores, pointers} =
          Enum.reduce(modes, {%{}, %{}}, fn to, {new_scores, pointers} ->
            best_from =
              Enum.max_by(modes, fn from -> scores[from] + transition_penalty(from, to) end)

            new_score =
              scores[best_from] + transition_penalty(best_from, to) +
                emission_score(elem(emissions_tuple, i), to)

            {Map.put(new_scores, to, new_score), Map.put(pointers, to, best_from)}
          end)

        {new_scores, [pointers | backpointers]}
      end)

    last = Enum.max_by(modes, fn m -> final_scores[m] end)

    Enum.reduce(backpointers, [last], fn pointers, path ->
      [pointers[List.first(path)] | path]
    end)
  end

  defp forward_backward(emissions, modes) do
    n = length(emissions)
    emissions_tuple = List.to_tuple(emissions)

    forward = build_forward(emissions_tuple, modes, n)
    backward = build_backward(emissions_tuple, modes, n)

    for i <- 0..(n - 1)//1 do
      fwd = elem(forward, i)
      bwd = elem(backward, i)
      joint = Map.new(modes, fn m -> {m, fwd[m] + bwd[m]} end)
      total = logsumexp(Map.values(joint))
      Map.new(joint, fn {m, v} -> {m, :math.exp(v - total)} end)
    end
  end

  defp build_forward(emissions_tuple, modes, n) do
    first = Map.new(modes, fn m -> {m, emission_score(elem(emissions_tuple, 0), m)} end)

    1..(n - 1)//1
    |> Enum.reduce([first], fn i, [prev | _] = acc ->
      current =
        Map.new(modes, fn to ->
          terms = Enum.map(modes, fn from -> prev[from] + transition_penalty(from, to) end)
          {to, logsumexp(terms) + emission_score(elem(emissions_tuple, i), to)}
        end)

      [current | acc]
    end)
    |> Enum.reverse()
    |> List.to_tuple()
  end

  defp build_backward(emissions_tuple, modes, n) do
    last = Map.new(modes, fn m -> {m, 0.0} end)

    (n - 2)..0//-1
    |> Enum.reduce([last], fn i, [next_back | _] = acc ->
      current =
        Map.new(modes, fn from ->
          terms =
            Enum.map(modes, fn to ->
              transition_penalty(from, to) + emission_score(elem(emissions_tuple, i + 1), to) +
                next_back[to]
            end)

          {from, logsumexp(terms)}
        end)

      [current | acc]
    end)
    |> List.to_tuple()
  end

  defp emission_score(emission, mode), do: Map.get(emission, mode, -1.0e4)

  defp logsumexp(values) do
    max = Enum.max(values)
    exps = Enum.map(values, &:math.exp(&1 - max))
    max + :math.log(RubyFloat.sum(exps))
  end
end
