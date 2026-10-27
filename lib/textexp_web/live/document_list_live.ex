defmodule TextexpWeb.DocumentListLive do
  use TextexpWeb, :live_view

  import TextexpWeb.DocumentComponents

  alias Phoenix.LiveView.AsyncResult
  alias Textexp.Document
  alias Textexp.Document.{Search, YPersistence}

  on_mount {TextexpWeb.LiveUserAuth, :live_user_required}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} full_width>
      <div id="documents-page" class="mx-auto w-full max-w-2xl px-4 py-10 sm:py-14">
        <.form
          for={@search_form}
          id="search-form"
          phx-change="search"
          phx-submit="search"
          class="mb-3"
        >
          <label class="group flex items-center gap-3 border-2 border-base-content bg-base-100 px-4 py-2.5 transition duration-150 focus-within:shadow-hard">
            <.icon
              name="hero-magnifying-glass"
              class="size-5 shrink-0 text-base-content/50 transition-colors group-focus-within:text-base-content"
            />
            <input
              id="search-query"
              name="query"
              type="search"
              value={@search_form[:query].value}
              placeholder="Rechercher dans les documents"
              autocomplete="off"
              phx-debounce="300"
              class="grow bg-transparent text-sm outline-none placeholder:text-base-content/50"
            />
            <span
              :if={@index && @index.loading}
              id="search-loading"
              class="loading loading-spinner loading-sm text-base-content/40"
              aria-label="Recherche en cours"
            ></span>
          </label>
        </.form>

        <%!-- Shaped like document cards, highlighted. Outside the stream so that
             the empty state below keeps working. --%>
        <div class="grid gap-3 sm:grid-cols-2">
          <button
            id="new-document"
            type="button"
            phx-click="new_document"
            class="group flex w-full cursor-pointer items-center gap-4 border-2 border-base-content bg-primary px-5 py-4 text-left text-primary-content transition duration-150 ease-out hover:-translate-x-0.5 hover:-translate-y-0.5 hover:shadow-hard focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-base-content phx-click-loading:pointer-events-none phx-click-loading:opacity-60"
          >
            <span class="flex size-9 shrink-0 items-center justify-center border-2 border-primary-content">
              <.icon name="hero-plus" class="size-5" />
            </span>
            <span class="flex flex-col">
              <span class="text-sm font-medium uppercase tracking-wide">Nouveau document</span>
              <span class="text-xs opacity-75">Commencer une page vierge</span>
            </span>
          </button>

          <%!-- Each file chosen is converted in the browser and sent to the
               server (see the DocumentImport hook) --%>
          <label
            id="import-document"
            data-import
            class="group flex cursor-pointer items-center gap-4 border-2 border-base-content bg-base-100 px-5 py-4 text-left transition duration-150 ease-out hover:-translate-x-0.5 hover:-translate-y-0.5 hover:shadow-hard focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-base-content aria-busy:pointer-events-none aria-busy:opacity-60"
          >
            <span class="flex size-9 shrink-0 items-center justify-center border-2 border-base-content bg-base-300">
              <.icon name="hero-arrow-up-tray" class="size-5 group-aria-busy:hidden" />
              <span class="loading loading-spinner loading-sm hidden group-aria-busy:inline-block"></span>
            </span>
            <span class="flex flex-col">
              <span class="text-sm font-medium uppercase tracking-wide">Importer</span>
              <span class="text-xs text-base-content/60">Markdown, HTML ou texte</span>
            </span>
            <input
              id="import-files"
              type="file"
              multiple
              accept=".md,.markdown,.txt,.html,.htm,text/markdown,text/plain,text/html"
              phx-hook="DocumentImport"
              class="sr-only"
            />
          </label>
        </div>

        <%!-- Sorted by last update, most recent first; by relevance when searching --%>
        <ul id="documents" class="mt-4 flex flex-col gap-4" phx-update="stream">
          <li
            id="documents-empty"
            class="hidden only:block border-2 border-dashed border-base-content/40 px-4 py-10 text-center text-sm text-base-content/60"
          >
            {if @searching?, do: "Aucun résultat", else: "Aucun document"}
          </li>
          <li :for={{id, document} <- @streams.documents} id={id}>
            <.document_card document={document} snippet={document.snippet} />
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Textexp.PubSub, YPersistence.documents_topic())
    end

    {:ok,
     socket
     |> assign(
       page_title: "Documents",
       search_form: to_form(%{"query" => ""}),
       searching?: false,
       index: nil
     )
     |> stream(:documents, list_documents(socket.assigns.current_user))}
  end

  # An empty document was left and deleted (see YPersistence).
  def handle_info({:document_deleted, document_id}, socket) do
    {:noreply, stream_delete_by_dom_id(socket, :documents, "documents-#{document_id}")}
  end

  def handle_event("new_document", _params, socket) do
    {:ok, document} = Document.create_document(socket.assigns.current_user)
    {:noreply, push_navigate(socket, to: ~p"/documents/#{document.id}")}
  end

  # A file converted by the DocumentImport hook: its Yjs state, in base64.
  def handle_event("import_document", %{"name" => name, "state" => state}, socket) do
    title = name |> Path.rootname() |> String.trim()

    with {:ok, snapshot} <- Base.decode64(state),
         {:ok, document} <-
           Document.import_document(socket.assigns.current_user, title, snapshot) do
      {:reply, %{id: document.id},
       socket
       |> stream_insert(:documents, document, at: 0)
       |> put_flash(:info, "« #{title} » importé")}
    else
      _ -> {:reply, %{}, put_flash(socket, :error, "Impossible d'importer « #{name} »")}
    end
  end

  def handle_event("import_failed", %{"name" => name, "reason" => reason}, socket) do
    message =
      case reason do
        "too_large" -> "« #{name} » est trop volumineux (2 Mo au plus)"
        _ -> "Impossible de lire « #{name} »"
      end

    {:reply, %{}, put_flash(socket, :error, message)}
  end

  # The search index is only built for the first search, in the background: it
  # then stays in memory until the page is left.
  def handle_event("search", %{"query" => query}, socket) do
    socket = assign(socket, search_form: to_form(%{"query" => query}))

    socket =
      case socket.assigns.index do
        nil when query != "" ->
          user = socket.assigns.current_user

          socket
          |> assign(index: AsyncResult.loading())
          |> start_async(:index, fn -> Search.new_index(user) end)

        _ ->
          show_results(socket)
      end

    {:noreply, socket}
  end

  def handle_async(:index, {:ok, {:ok, index}}, socket) do
    {:noreply,
     socket
     |> assign(index: AsyncResult.ok(socket.assigns.index, index))
     |> show_results()}
  end

  def handle_async(:index, result, socket) do
    reason = with {:ok, {:error, reason}} <- result, do: reason

    {:noreply,
     socket
     |> assign(index: AsyncResult.failed(socket.assigns.index, reason))
     |> put_flash(:error, "La recherche n'est pas disponible")}
  end

  # The documents matching the query, or all of them without query. While the
  # index is loading, the list is left as it is.
  defp show_results(socket) do
    query = String.trim(socket.assigns.search_form[:query].value)

    case {query, socket.assigns.index} do
      {"", _index} ->
        socket
        |> assign(searching?: false)
        |> stream(:documents, list_documents(socket.assigns.current_user), reset: true)

      {query, %AsyncResult{ok?: true, result: index}} ->
        socket
        |> assign(searching?: true)
        |> stream(:documents, Search.search(index, query, socket.assigns.current_user),
          reset: true
        )

      _loading_or_failed ->
        socket
    end
  end

  defp list_documents(user), do: Document.list_documents(user)
end
