defmodule YPhoenix.Persistence do
  @moduledoc """
  Persistence of a Yjs document served by `YPhoenix.DocServer`.

  Extends `Yex.Sync.SharedDoc.PersistenceBehaviour` with `flush/3`, called
  periodically by the DocServer to save the document.

  Updates applied on load (`bind/3`) must use the `origin/0` origin, so that
  the DocServer does not treat them as edits.
  """

  @callback bind(state :: term(), doc_name :: String.t(), doc :: Yex.Doc.t()) :: term()
  @callback unbind(state :: term(), doc_name :: String.t(), doc :: Yex.Doc.t()) :: :ok
  @callback update_v1(
              state :: term(),
              update :: binary(),
              doc_name :: String.t(),
              doc :: Yex.Doc.t()
            ) :: term()
  @callback flush(state :: term(), doc_name :: String.t(), doc :: Yex.Doc.t()) :: term()

  def origin, do: :persistence
end
