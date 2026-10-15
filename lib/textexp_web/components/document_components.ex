defmodule TextexpWeb.DocumentComponents do
  @moduledoc """
  Components displaying documents.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: TextexpWeb.Endpoint,
    router: TextexpWeb.Router,
    statics: TextexpWeb.static_paths()

  @doc """
  A document of a list, as a card linking to it: its title, last update and
  excerpt (the first lines of its body).

  The document needs its `title`, `excerpt` and `last_update`.
  """
  attr :document, :map, required: true

  def document_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/documents/#{@document.id}"}
      class="group block rounded-box border border-base-300 bg-base-100 px-5 py-4 transition duration-150 ease-out hover:-translate-y-0.5 hover:border-base-content/20 hover:shadow-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
    >
      <div class="flex items-baseline justify-between gap-4">
        <h2 class={[
          "truncate text-base font-semibold",
          if(@document.title, do: "text-base-content", else: "text-base-content/40")
        ]}>
          {@document.title || "Sans titre"}
        </h2>
        <time
          datetime={DateTime.to_iso8601(@document.last_update)}
          class="shrink-0 text-xs tabular-nums text-base-content/50"
        >
          {Calendar.strftime(@document.last_update, "%d/%m/%Y %H:%M")} UTC
        </time>
      </div>
      <p
        :if={@document.excerpt}
        class="mt-1.5 line-clamp-3 whitespace-pre-line text-sm leading-relaxed text-base-content/70"
      >
        {@document.excerpt}
      </p>
    </.link>
    """
  end
end
