defmodule Textexp.Document.YPersistence do
  @moduledoc """
  Persistance Yjs d'un `Textexp.Document.Document`.

  - au chargement (`bind/3`) : on applique le snapshot puis les writings ;
  - à chaque modification (`update_v1/4`) : on ajoute un writing ;
  - à l'arrêt du DocServer (`unbind/3`), ou au chargement s'il y a trop de
    writings : on compacte tout dans le snapshot.

  Les updates appliquées au chargement portent l'origine `origin/0`, que le
  DocServer doit ignorer pour ne pas les réenregistrer comme des writings.
  """
  @behaviour Yex.Sync.SharedDoc.PersistenceBehaviour

  alias Textexp.Document

  @origin :persistence
  @compact_threshold 400

  def origin, do: @origin

  @impl true
  def bind(state, document_id, doc) do
    document = Document.get_document!(document_id)
    writings = Document.list_writings!(document_id)
    updates = List.wrap(document.snapshot) ++ Enum.map(writings, & &1.value)

    Yex.Doc.transaction(doc, @origin, fn ->
      Enum.each(updates, &Yex.apply_update(doc, &1))
    end)

    if length(writings) > @compact_threshold, do: compact(document, doc)

    state
  end

  @impl true
  def unbind(_state, document_id, doc) do
    document_id |> Document.get_document!() |> compact(doc)
    :ok
  end

  @impl true
  def update_v1(state, update, document_id, _doc) do
    Document.add_writing!(document_id, update)
    state
  end

  # Le DocServer est le seul à écrire des writings pour ce document : tous ceux
  # insérés jusqu'ici sont donc déjà dans `doc`.
  defp compact(document, doc) do
    Document.compact_document!(document, Yex.encode_state_as_update!(doc), DateTime.utc_now())
  end
end
