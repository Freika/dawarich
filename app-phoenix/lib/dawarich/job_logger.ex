defmodule Dawarich.JobLogger do
  @moduledoc false
  @id "dawarich-job-logger"
  @events [
    [:oban, :job, :start],
    [:oban, :job, :stop],
    [:oban, :job, :exception],
    [:oban, :peer, :election, :stop]
  ]
  @opts [encode: true, level: :info, oban_name: :all]

  def attach, do: :telemetry.attach_many(@id, @events, &__MODULE__.handle_event/4, @opts)

  def detach, do: :telemetry.detach(@id)

  def handle_event(event, measure, %{job: job} = meta, opts),
    do: Oban.Telemetry.handle_event(event, measure, %{meta | job: %{job | args: %{}}}, opts)

  def handle_event(event, measure, meta, opts),
    do: Oban.Telemetry.handle_event(event, measure, meta, opts)
end
