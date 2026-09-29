defmodule Dawarich.Transportation.Emissions do
  @moduledoc false

  alias Dawarich.RubyFloat

  @tuning %{
    window_s: 60,
    step_s: 30,
    gap_reset_s: 300,
    accuracy_mask_m: 100.0,
    accel_mask_mps2: 10.0,
    sparse_dt_s: 30.0,
    confidence_low: 0.5,
    confidence_high: 0.8,
    min_track_duration_s: 30,
    min_auto_sliver_s: 30
  }

  @inferred_modes ~w(stationary walking running cycling driving train flying)
  @hint_only_modes ~w(bus boat motorcycle)

  @mode_priors %{
    "stationary" => 0.0,
    "walking" => 0.0,
    "running" => -0.3,
    "cycling" => -0.3,
    "driving" => 0.0,
    "train" => -1.75,
    "flying" => -2.5,
    "bus" => -0.7,
    "boat" => -1.5,
    "motorcycle" => -1.0
  }

  @mode_profiles %{
    "stationary" => %{
      speed_p50: %{ln: {0.4, 1.2}, w: 1.0},
      speed_p95: %{ln: {1.5, 1.5}, w: 0.7},
      heading_change_rate: nil,
      motion_variance: nil,
      stop_fraction: %{n: {0.9, 0.15}, w: 0.6}
    },
    "walking" => %{
      speed_p50: %{ln: {4.5, 0.35}, w: 1.0},
      speed_p95: %{ln: {6.5, 0.4}, w: 0.7},
      heading_change_rate: %{n: {12.0, 8.0}, w: 0.8},
      motion_variance: %{n: {1.5, 1.5}, w: 0.25},
      stop_fraction: %{n: {0.15, 0.2}, w: 0.4}
    },
    "running" => %{
      speed_p50: %{ln: {10.0, 0.25}, w: 1.0},
      speed_p95: %{ln: {14.0, 0.3}, w: 0.7},
      heading_change_rate: %{n: {6.0, 5.0}, w: 0.8},
      motion_variance: %{n: {2.5, 2.0}, w: 0.25},
      stop_fraction: %{n: {0.05, 0.1}, w: 0.4}
    },
    "cycling" => %{
      speed_p50: %{ln: {17.0, 0.35}, w: 1.0},
      speed_p95: %{ln: {28.0, 0.35}, w: 0.7},
      heading_change_rate: %{n: {3.0, 3.0}, w: 0.8},
      motion_variance: %{n: {4.0, 3.0}, w: 0.25},
      stop_fraction: %{n: {0.08, 0.15}, w: 0.4}
    },
    "driving" => %{
      speed_p50: %{ln: {55.0, 0.75}, w: 1.0},
      speed_p95: %{ln: {110.0, 0.6}, w: 0.7},
      heading_change_rate: %{n: {1.2, 1.5}, w: 0.8},
      motion_variance: %{n: {14.0, 10.0}, w: 0.25},
      stop_fraction: %{n: {0.15, 0.2}, w: 0.4}
    },
    "train" => %{
      speed_p50: %{ln: {110.0, 0.45}, w: 1.0},
      speed_p95: %{ln: {170.0, 0.5}, w: 0.7},
      heading_change_rate: %{n: {0.3, 0.5}, w: 0.8},
      motion_variance: %{n: {8.0, 6.0}, w: 0.25},
      stop_fraction: %{n: {0.05, 0.1}, w: 0.4}
    },
    "flying" => %{
      speed_p50: %{ln: {500.0, 0.5}, w: 1.0},
      speed_p95: %{ln: {750.0, 0.4}, w: 0.7},
      heading_change_rate: %{n: {0.1, 0.3}, w: 0.8},
      motion_variance: %{n: {30.0, 25.0}, w: 0.25},
      stop_fraction: %{n: {0.01, 0.05}, w: 0.4}
    },
    "boat" => %{
      speed_p50: %{ln: {15.0, 0.9}, w: 1.0},
      speed_p95: nil,
      heading_change_rate: nil,
      motion_variance: nil,
      stop_fraction: nil
    }
  }

  @sparse_sigma_factor 1.5
  @sparse_dropped_features [:heading_change_rate, :motion_variance, :stop_fraction]

  def tuning, do: @tuning

  def log_likelihoods(window, enabled) do
    window
    |> candidate_modes(enabled)
    |> Enum.map(fn mode -> {mode, score_mode(mode, window)} end)
  end

  defp candidate_modes(window, enabled) do
    inferred = intersect(@inferred_modes, enabled)
    hint_only_enabled = intersect(@hint_only_modes, enabled)
    hint_keys = Enum.map(window.hints, fn {mode, _value} -> mode end)
    hinted = intersect(hint_keys, hint_only_enabled)

    Enum.uniq(inferred ++ hinted)
  end

  defp intersect(a, b) do
    a |> Enum.uniq() |> Enum.filter(&(&1 in b))
  end

  defp score_mode(mode, window) do
    profile = Map.get(@mode_profiles, mode) || Map.fetch!(@mode_profiles, "driving")

    total =
      RubyFloat.sum(
        Enum.map(profile, fn {feature, spec} -> feature_score(spec, window, feature) end)
      )

    hint_value =
      case List.keyfind(window.hints, mode, 0) do
        {^mode, value} -> value
        nil -> 0.0
      end

    total + Map.get(@mode_priors, mode, 0.0) + hint_value
  end

  defp feature_score(nil, _window, _feature), do: 0.0

  defp feature_score(spec, window, feature) do
    if window.sparse and feature in @sparse_dropped_features do
      0.0
    else
      value = Map.get(window, feature)
      density_score(spec, value, window.sparse)
    end
  end

  defp density_score(_spec, nil, _sparse), do: 0.0

  defp density_score(%{ln: {center, sigma}, w: w}, value, sparse) do
    sigma = if sparse, do: sigma * @sparse_sigma_factor, else: sigma
    w * log_normal_density(value, center, sigma)
  end

  defp density_score(%{n: {mu, sigma}, w: w}, value, _sparse) do
    w * normal_density(value, mu, sigma)
  end

  defp log_normal_density(value, center, sigma) do
    x = :math.log(value + 0.1)
    mu = :math.log(center)
    -((x - mu) * (x - mu) / (2 * sigma * sigma)) - :math.log(sigma)
  end

  defp normal_density(value, mean, sigma) do
    -((value - mean) * (value - mean) / (2 * sigma * sigma)) - :math.log(sigma)
  end
end
