defmodule Dawarich.Mail.JobResult do
  @moduledoc false

  def protect(deliver) do
    case deliver.() do
      :ok ->
        :ok

      {:snooze, seconds} when is_integer(seconds) ->
        {:snooze, seconds}

      {:error, :claim_lost} ->
        {:error, :claim_lost}

      {:error, message} when message in ["DOMAIN is not set", "JWT_SECRET_KEY is not set"] ->
        {:error, message}

      {:cancel, reason}
      when reason in ["archival upgrade link expired", "link digest mismatch"] ->
        {:cancel, reason}

      {:error, {type, <<code, a, b>> = status}}
      when type in [:temporary_failure, :permanent_failure] and code in ?2..?5 and a in ?0..?9 and
             b in ?0..?9 ->
        {:error, {type, status}}

      _ ->
        {:error, :delivery_failed}
    end
  rescue
    _ -> {:error, :delivery_failed}
  catch
    _, _ -> {:error, :delivery_failed}
  end
end
