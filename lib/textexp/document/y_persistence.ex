defmodule Textexp.Document.YPersistence do
  @moduledoc """
  Persistance Yjs d'un `Textexp.Document.Document`.

  - au chargement (`bind/3`) : on applique le snapshot puis les writings ;
  - à chaque modification (`update_v1/4`) : on ajoute un writing ;
  - flush (compactage de tous les writings dans le snapshot) :
    - tous les 400 writings (`@flush_every_writings`) ;
    - toutes les 5 minutes, via `flush/3` appelé par le DocServer ;
    - à l'arrêt du DocServer (`unbind/3`), y compris à l'arrêt de l'application ;
    - au chargement, s'il reste des writings (DocServer arrêté brutalement).

  L'état de persistance compte les writings non compactés (`:pending`).

  Les updates appliquées au chargement portent l'origine `origin/0`, que le
  DocServer doit ignorer pour ne pas les réenregistrer comme des writings.
  """
  @behaviour Yex.Sync.SharedDoc.PersistenceBehaviour

  alias Textexp.Document

  @origin :persistence
  @flush_every_writings 400
  @broadcast_interval_ms 5_000

  def origin, do: @origin

  @doc """
  Topic PubSub sur lequel est diffusé `{:document_updated, document_id, at}`
  quand le contenu du document change (au plus une fois toutes les 5 s).
  """
  def topic(document_id), do: "document:#{document_id}"

  @impl true
  def bind(state, document_id, doc) do
    document = Document.get_document!(document_id)
    writings = Document.list_writings!(document_id)
    updates = List.wrap(document.snapshot) ++ Enum.map(writings, & &1.value)

    Yex.Doc.transaction(doc, @origin, fn ->
      Enum.each(updates, &Yex.apply_update(doc, &1))
    end)

    state
    |> Map.put(:pending, length(writings))
    |> flush(document_id, doc)
  end

  @impl true
  def unbind(state, document_id, doc) do
    flush(state, document_id, doc)
    :ok
  end

  @doc """
  Compacte les writings en attente dans le snapshot ; ne fait rien s'il n'y en a pas.
  """
  def flush(%{pending: 0} = state, _document_id, _doc), do: state

  # Le DocServer est le seul à écrire des writings pour ce document : tous ceux
  # insérés jusqu'ici sont donc déjà dans `doc`.
  def flush(state, document_id, doc) do
    document_id
    |> Document.get_document!()
    |> Document.compact_document!(Yex.encode_state_as_update!(doc), DateTime.utc_now())

    Map.put(state, :pending, 0)
  end

  @impl true
  def update_v1(state, update, document_id, doc) do
    writing = Document.add_writing!(document_id, update)
    state = Map.update(state, :pending, 1, &(&1 + 1))

    state =
      if state.pending >= @flush_every_writings,
        do: flush(state, document_id, doc),
        else: state

    maybe_broadcast(state, document_id, writing.inserted_at)
  end

  defp maybe_broadcast(state, document_id, at) do
    now = System.monotonic_time(:millisecond)

    if now - Map.get(state, :last_broadcast, now - @broadcast_interval_ms) >=
         @broadcast_interval_ms do
      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        topic(document_id),
        {:document_updated, document_id, at}
      )

      Map.put(state, :last_broadcast, now)
    else
      state
    end
  end
end
