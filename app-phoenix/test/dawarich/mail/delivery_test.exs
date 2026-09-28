defmodule Dawarich.Mail.DeliveryTest do
  use Dawarich.JobsCase

  alias Dawarich.Mail.{Delivery, Smtp}

  @handler "mail.test"
  @key "welcome:1"

  defp build,
    do:
      {:ok,
       %{
         from: "Dawarich <hi@example.test>",
         to: "u@example.test",
         subject: "Hi",
         text: "Hi",
         html: "<p>Hi</p>"
       }}

  defp deliver(event_id), do: Delivery.deliver(ScratchRepo, @handler, @key, event_id, &build/0)

  defp claim_row,
    do:
      rows(
        "SELECT event_id, delivered_at FROM phoenix.delivery_claims WHERE handler = $1 AND provider_key = $2",
        [@handler, @key]
      )

  defp delivered_at do
    [[_, delivered_at]] = claim_row()
    delivered_at
  end

  test "first claim sends and delivered! records the receipt; the same event afterwards sends nothing" do
    event_id = Ecto.UUID.generate()

    assert deliver(event_id) == :ok
    assert_received {:mail, %{to: "u@example.test"}}
    refute_received {:mail, _}
    assert %DateTime{} = delivered_at()

    assert deliver(event_id) == :ok
    refute_received {:mail, _}
  end

  test "an SMTP error then a retry of the same event sends exactly once more" do
    event_id = Ecto.UUID.generate()
    Process.put(:transport_result, {:error, {:temporary_failure, "451"}})

    assert {:error, _} = deliver(event_id)
    assert_received {:mail, _}
    assert delivered_at() == nil

    Process.delete(:transport_result)

    assert deliver(event_id) == :ok
    assert_received {:mail, _}
    refute_received {:mail, _}
    assert %DateTime{} = delivered_at()
  end

  test "a second event with the same key after delivery sends nothing" do
    assert deliver(Ecto.UUID.generate()) == :ok
    assert_received {:mail, _}

    rows(
      "UPDATE phoenix.delivery_claims SET claimed_at = claimed_at - interval '11 minutes' WHERE provider_key = $1",
      [@key]
    )

    assert deliver(Ecto.UUID.generate()) == :ok
    refute_received {:mail, _}
  end

  test "a second event while the first holds an undelivered claim snoozes 600 s" do
    assert Delivery.claim(ScratchRepo, @handler, @key, Ecto.UUID.generate()) == :send

    assert deliver(Ecto.UUID.generate()) == {:snooze, 600}
    refute_received {:mail, _}
  end

  test "an undelivered claim older than 10 minutes is taken over" do
    now = DateTime.utc_now()
    first = Ecto.UUID.generate()
    second = Ecto.UUID.generate()

    assert Delivery.claim(ScratchRepo, @handler, @key, first, now) == :send
    assert Delivery.claim(ScratchRepo, @handler, @key, second, DateTime.add(now, 599)) == :held
    assert Delivery.claim(ScratchRepo, @handler, @key, second, DateTime.add(now, 601)) == :send
    assert [[event_id, nil]] = claim_row()
    assert Ecto.UUID.cast!(event_id) == second
  end

  test "two concurrent claims for one key: one sends, the other is held" do
    parent = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          result = Delivery.claim(ScratchRepo, @handler, @key, Ecto.UUID.generate())
          send(parent, :holding)

          receive do
            :release -> result
          end
        end)
      end)

    assert_receive :holding
    waiting = Ecto.UUID.generate()

    error =
      assert_raise Postgrex.Error, fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!("SET LOCAL lock_timeout = '200ms'")
          Delivery.claim(ScratchRepo, @handler, @key, waiting)
        end)
      end

    assert error.postgres.code == :lock_not_available

    send(holder.pid, :release)
    assert Task.await(holder) == {:ok, :send}
    assert Delivery.claim(ScratchRepo, @handler, @key, waiting) == :held
  end

  test "a crash after the server accepted the message resends on retry" do
    event_id = Ecto.UUID.generate()
    Process.put(:crash_after_send, true)

    assert_raise RuntimeError, fn -> deliver(event_id) end
    assert_received {:mail, _}
    assert delivered_at() == nil

    Process.delete(:crash_after_send)

    assert deliver(event_id) == :ok
    assert_received {:mail, _}
    refute_received {:mail, _}
    assert %DateTime{} = delivered_at()
  end

  test "Message-ID is deterministic per handler and key and appears in the encoded mail" do
    message_id = Delivery.message_id(@handler, @key)

    assert message_id == Delivery.message_id(@handler, @key)
    assert message_id =~ ~r/\A<[0-9a-f]{64}@dawarich\.mail>\z/
    refute message_id == Delivery.message_id(@handler, "welcome:2")
    refute message_id == Delivery.message_id("mail.other", @key)

    assert deliver(Ecto.UUID.generate()) == :ok
    assert_received {:mail, %{message_id: ^message_id} = message}

    {"multipart", "alternative", headers, _params, _parts} =
      message |> Smtp.encode() |> :mimemail.decode(encoding: :none)

    assert {"Message-ID", message_id} in headers
  end
end
