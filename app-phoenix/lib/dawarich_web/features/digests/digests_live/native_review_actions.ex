defmodule DawarichWeb.DigestsLive.NativeReviewActions do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.Icon
  attr :locale, :string, required: true
  attr :href, :string, required: true

  def upgrade(assigns) do
    ~H"""
    <div id="native-digest-upgrade" class="card bg-base-200 shadow-xl mb-8 border border-primary/20">
      <div class="card-body text-center items-center">
        <h2 class="card-title">
          <Icon.icon name="sparkles" class="size-6" /> {t(
            @locale,
            "users.digests.show.want_more_insights",
            %{}
          )}
        </h2>
        <p class="text-gray-600 mb-4">
          {t(@locale, "users.digests.show.upgrade_to_pro_to_see_your_full_year_in_review", %{})}
        </p>
        <button class="btn btn-primary" phx-click="upgrade">{t(
          @locale,
          "users.digests.show.upgrade_to_pro",
          %{}
        )}</button>
      </div>
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :year, :integer, required: true
  attr :csrf, :string, default: ""

  def actions(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-4 justify-center">
      <a class="btn btn-outline" href="/digests">{t(
        @locale,
        "users.digests.show.back_to_all_digests",
        %{}
      )}</a>
      <button class="btn btn-outline" phx-click="open_share"><Icon.icon
        name="share"
        class="size-6"
      /> {t(@locale, "users.digests.show.share", %{})}</button>
      <form class="button_to" method="post" action={"/digests/#{@year}"} phx-submit="delete">
        <input type="hidden" name="_method" value="delete" /><button
          class="btn btn-outline btn-error"
          type="submit"
        ><Icon.icon name="trash-2" class="size-6" /> {t(@locale, "users.digests.show.delete", %{})}</button><input
          type="hidden"
          name="authenticity_token"
          value={@csrf}
        />
      </form>
    </div>
    """
  end
end
