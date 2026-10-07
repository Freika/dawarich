defmodule Dawarich.Mail.Wave2ArgsTest do
  use ExUnit.Case, async: true

  alias Dawarich.Mail.{
    AccountDestroyConfirmationWorker,
    ArchivalApproachingWorker,
    FamilyInvitationWorker,
    FamilyLapseWorker,
    OauthAccountLinkWorker,
    WelcomeWorker
  }

  @payloads Path.expand("../../fixtures/wave2/payloads.json", __DIR__)

  @workers %{
    "mail.family_invitation" => FamilyInvitationWorker,
    "mail.family_lapse" => FamilyLapseWorker,
    "mail.user.welcome" => WelcomeWorker,
    "mail.user.archival_approaching" => ArchivalApproachingWorker,
    "mail.user.oauth_account_link" => OauthAccountLinkWorker,
    "mail.user.account_destroy_confirmation" => AccountDestroyConfirmationWorker
  }

  @link_types ~w(mail.user.oauth_account_link mail.user.account_destroy_confirmation)

  @digest "d52d0dfe8c237434e757944f3e99c3e286f7b91d1a308d7eb3464e3c5833cb7a"

  @rails_dedupe_keys %{
    "mail.family_invitation" => "family-invitation:12",
    "mail.user.welcome" => "welcome:42",
    "mail.user.archival_approaching" => "archival-approaching:42:2026-03-29T01:30:00Z",
    "mail.user.oauth_account_link" => "oauth-link:42:" <> @digest,
    "mail.user.account_destroy_confirmation" => "destroy-confirmation:42:" <> @digest
  }

  defp payloads, do: @payloads |> File.read!() |> Jason.decode!()

  defp mistyped(value, worker)
       when is_integer(value) and worker in [FamilyInvitationWorker, FamilyLapseWorker],
       do: "invalid"

  defp mistyped(value, _worker) when is_integer(value), do: to_string(value)
  defp mistyped(value, _worker) when is_binary(value), do: 1

  test "each decoder accepts its exact payload and rejects extra, missing and mistyped keys and other versions" do
    payloads = payloads()

    for {type, worker} <- @workers do
      payload = Map.fetch!(payloads, type)
      expected = if type in @link_types, do: Map.delete(payload, "link_url"), else: payload

      assert worker.args_from_command(1, payload) == {:ok, expected}, type

      assert worker.args_from_command(1, Map.put(payload, "extra", 1)) ==
               {:error, "invalid_payload"},
             type

      for key <- Map.keys(payload), broken <- [nil, mistyped(payload[key], worker)] do
        assert worker.args_from_command(1, Map.delete(payload, key)) ==
                 {:error, "invalid_payload"},
               "#{type} without #{key}"

        assert worker.args_from_command(1, Map.put(payload, key, broken)) ==
                 {:error, "invalid_payload"},
               "#{type} with #{key} = #{inspect(broken)}"
      end

      assert worker.args_from_command(1, [payload]) == {:error, "invalid_payload"}, type
      assert worker.args_from_command(2, payload) == {:error, "unsupported_version"}, type
    end
  end

  test "Oban args never contain an email, a URL or a token" do
    payloads = payloads()

    for {type, worker} <- @workers do
      {:ok, args} = worker.args_from_command(1, Map.fetch!(payloads, type))
      json = Jason.encode!(Map.put(args, "event_id", Ecto.UUID.generate()))

      refute json =~ "@", type
      refute json =~ "http", type
      refute json =~ "token=", type
    end
  end

  test "every worker: queue mailers, max_attempts 20, timeout 5 minutes" do
    for worker <- Map.values(@workers) do
      opts = worker.__opts__()
      assert opts[:queue] == :mailers, inspect(worker)
      assert opts[:max_attempts] == 20, inspect(worker)
      assert worker.timeout(%Oban.Job{}) == :timer.minutes(5), inspect(worker)
    end
  end

  test "the claim key equals the Rails dedupe key for the same payload" do
    payloads = payloads()

    for {type, key} <- @rails_dedupe_keys do
      worker = Map.fetch!(@workers, type)
      {:ok, args} = worker.args_from_command(1, Map.fetch!(payloads, type))
      assert worker.provider_key(args) == key, type
    end
  end
end
