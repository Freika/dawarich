defmodule DawarichWeb.FamiliesLive.Invitations do
  @moduledoc false
  use DawarichWeb, :live_view
  alias DawarichWeb.{FamilyNativeLive, FamilyNativeControls, FamilyNativeInvitations}
  @impl true
  def mount(_, _, socket), do: {:ok, FamilyNativeLive.mount(socket)}
  @impl true
  def handle_event(event, params, socket), do: FamilyNativeLive.event(event, params, socket)
  @impl true
  def handle_info(_, socket), do: {:noreply, socket}
  @impl true
  def handle_params(_, _, socket), do: {:noreply, socket}
  @impl true
  def render(assigns) do
    ~H"""
    <section
      id="family-invitations-shell"
      class="container mx-auto max-w-4xl py-8 min-w-0 [overflow-wrap:anywhere]"
    >
      <FamilyNativeControls.errors errors={@errors} />
      <header class="flex flex-wrap justify-between gap-3 mb-6">
        <h1 class="text-2xl font-semibold">{t(@locale, "family_invitations.index.title", %{})}</h1>
        <a
          href={if @page.live?, do: "/family", else: "/family/new"}
          class="btn btn-neutral h-auto whitespace-normal"
        >{t(@locale, "family_invitations.index.back_to_family", %{})}</a>
      </header>
      <FamilyNativeInvitations.invitations
        page={@page}
        locale={@locale}
        now={@now}
        email={@invitation_email}
      />
      <FamilyNativeControls.confirmation confirmation={@confirmation} page={@page} locale={@locale} />
    </section>
    """
  end
end
