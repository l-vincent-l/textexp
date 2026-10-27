defmodule YPhoenix.Access do
  @moduledoc """
  Who may read or write a document served by `YPhoenix.DocServer`.

  The DocServer loads the document's rights when it starts (`init/1`), answers
  the clients joining it (`permission/2`), and keeps the rights up to date
  with the messages it receives (`handle_info/2`): a client whose permission
  changes is told at once (see `YPhoenix.Channel`).

  The rights are only kept while the DocServer runs: `init/1` must subscribe
  to their changes before loading them, so that none is missed.
  """

  @type permission :: :write | :read | :none

  @doc "The document's rights, or `:not_found` for an unknown document, which no one joins."
  @callback init(doc_name :: String.t()) :: {:ok, term()} | :not_found
  @callback permission(state :: term(), actor :: term()) :: permission()
  @doc "`{:ok, state}` for a change of the rights, `:ignore` for any other message."
  @callback handle_info(msg :: term(), state :: term()) :: {:ok, term()} | :ignore
end
