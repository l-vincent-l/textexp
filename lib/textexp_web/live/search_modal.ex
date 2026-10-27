defmodule TextexpWeb.SearchModal do
  @moduledoc """
  A modal searching the documents the user can read, opened from a document's
  menu, in `index`: a `Textexp.Document.SearchIndex` started by the LiveView,
  which stops it when the modal closes, freeing the index. Each search runs in
  a task, as it waits for the index while it is being built.

  Closing (its button, a click outside, Escape) sends `close_search` to the
  LiveView, which stops rendering it.
  """
  use TextexpWeb, :live_component

  import TextexpWeb.DocumentComponents

  alias Textexp.Document.SearchIndex

  def mount(socket) do
    {:ok,
     socket
     |> assign(
       form: to_form(%{"query" => ""}, as: "search"),
       loading?: false,
       failed?: false,
       searched?: false
     )
     |> stream(:results, [])}
  end

  def render(assigns) do
    ~H"""
    <div class="modal modal-open" phx-window-keydown="close_search" phx-key="Escape">
      <section
        id="search-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="search-title"
        class="modal-box flex max-h-[80dvh] w-11/12 max-w-2xl flex-col border-2 border-base-content bg-base-100 p-5 shadow-hard sm:p-6"
      >
        <div class="flex items-start justify-between gap-4">
          <h2 id="search-title" class="text-sm uppercase">Rechercher</h2>
          <button
            id="search-close"
            type="button"
            phx-click="close_search"
            aria-label="Fermer"
            class="btn btn-ghost btn-sm btn-square -mt-1 -mr-2"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        <.form
          for={@form}
          id="search-modal-form"
          phx-change="search"
          phx-submit="search"
          phx-target={@myself}
          class="mt-3"
        >
          <label class="flex items-center gap-3 border-2 border-base-content bg-base-100 px-4 py-2.5">
            <.icon name="hero-magnifying-glass" class="size-5 shrink-0 text-base-content/50" />
            <input
              id="search-modal-query"
              name={@form[:query].name}
              type="search"
              value={@form[:query].value}
              placeholder="Rechercher dans les documents"
              autocomplete="off"
              phx-debounce="300"
              phx-mounted={JS.focus()}
              phx-hook="SearchNav"
              role="combobox"
              aria-expanded="true"
              aria-autocomplete="list"
              aria-controls="search-results"
              class="grow bg-transparent text-sm outline-none placeholder:text-base-content/50"
            />
            <span
              :if={@loading?}
              id="search-modal-loading"
              class="loading loading-spinner loading-sm text-base-content/40"
              aria-label="Recherche en cours"
            ></span>
          </label>
        </.form>
        <%!-- Best match first. ↑ ↓ and Enter in the field select and open them
             (see the SearchNav hook). Its padding leaves room for the selected or
             hovered card, raised with a shadow, which it would otherwise cut. --%>
        <ul
          id="search-results"
          role="listbox"
          aria-label="Résultats"
          phx-update="stream"
          class="-mr-2 -ml-1 mt-3 flex min-h-0 flex-col gap-3 overflow-y-auto pt-1 pr-2 pb-2 pl-1"
        >
          <li
            id="search-results-empty"
            class="hidden py-6 text-center text-sm text-base-content/60 only:block"
          >
            <%= cond do %>
              <% @failed? -> %>
                La recherche n'est pas disponible
              <% @searched? -> %>
                Aucun résultat
              <% true -> %>
                Titres et contenu des documents
            <% end %>
          </li>
          <li
            :for={{id, document} <- @streams.results}
            id={id}
            role="option"
            class="[&[aria-selected=true]>a]:-translate-x-0.5 [&[aria-selected=true]>a]:-translate-y-0.5 [&[aria-selected=true]>a]:shadow-hard"
          >
            <.document_card document={document} snippet={document.snippet} />
          </li>
        </ul>
        <p class="mt-3 hidden text-xs text-base-content/60 sm:block">
          ↑ ↓ pour choisir · Entrée pour ouvrir · Échap pour fermer
        </p>
      </section>
      <button
        type="button"
        class="modal-backdrop"
        phx-click="close_search"
        aria-label="Fermer"
        tabindex="-1"
      ></button>
    </div>
    """
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket = assign(socket, form: to_form(%{"query" => query}, as: "search"))

    socket =
      case String.trim(query) do
        "" ->
          socket
          |> assign(loading?: false, searched?: false)
          |> stream(:results, [], reset: true)

        query ->
          index = socket.assigns.index

          socket
          |> assign(loading?: true)
          |> start_async(:search, fn -> {query, SearchIndex.search(index, query)} end)
      end

    {:noreply, socket}
  end

  # A search replaced by another one is dropped by LiveView; one answering a
  # query since cleared, here.
  def handle_async(:search, {:ok, {query, result}}, socket) do
    if query == String.trim(socket.assigns.form[:query].value) do
      {:noreply, show_results(socket, result)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:search, {:exit, _reason}, socket),
    do: {:noreply, show_results(socket, {:error, :exit})}

  defp show_results(socket, {:ok, documents}) do
    socket
    |> assign(loading?: false, failed?: false, searched?: true)
    |> stream(:results, documents, reset: true)
  end

  defp show_results(socket, {:error, _reason}) do
    socket
    |> assign(loading?: false, failed?: true)
    |> stream(:results, [], reset: true)
  end
end
