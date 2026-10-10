defmodule Dawarich.Mail.FamilyInvitationWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 20

  alias Dawarich.Mail.{Delivery, ExploreFeatures, Wave2}

  @handler "mail.family_invitation"
  @payload %{"invitation_id" => :integer, "locale" => :string}

  @invitation """
  SELECT i.email, i.token, i.status, f.name, inv.email, inv.settings, r.id, r.settings
  FROM family_invitations i JOIN families f ON f.id = i.family_id
  LEFT JOIN users inv ON inv.id = i.invited_by_id AND inv.deleted_at IS NULL
  LEFT JOIN users r ON r.email = i.email AND r.deleted_at IS NULL
  WHERE i.id = $1
  """

  def args_from_command(1, payload) when is_map(payload) do
    with {:ok, invitation_id} <- id(Map.get(payload, "invitation_id")) do
      Wave2.decode(1, Map.put(payload, "invitation_id", invitation_id), @payload)
    end
  end

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  defp id(value)
       when is_integer(value) and value in -9_223_372_036_854_775_808..9_223_372_036_854_775_807,
       do: {:ok, value}

  defp id(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> id(integer)
      _ -> {:error, "invalid_payload"}
    end
  end

  defp id(_value), do: {:error, "invalid_payload"}

  def provider_key(%{"invitation_id" => invitation_id}), do: "family-invitation:#{invitation_id}"

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"invitation_id" => invitation_id} = args}) do
    repo = Dawarich.Jobs.repo()

    case repo.query!(@invitation, [invitation_id], log: false).rows do
      [[_email, _token, 0, _family, nil | _]] ->
        {:cancel, "inviter missing"}

      [
        [
          email,
          token,
          0,
          family,
          inviter_email,
          inviter_settings,
          recipient_id,
          recipient_settings
        ]
      ] ->
        settings = if recipient_id, do: recipient_settings, else: inviter_settings
        locale = ExploreFeatures.locale(settings, args["locale"])

        Delivery.deliver(repo, @handler, provider_key(args), token, args["event_id"], fn ->
          Wave2.family_invitation(email, locale, token, family, inviter_email, System.get_env())
        end)

      _ ->
        :ok
    end
  end
end
