defmodule YPhoenix.Presence do
  @moduledoc """
  Presence of the clients connected to a document, used by `YPhoenix.DocServer`
  to know when to stop.

  After `subscribe/1`, the subscribed process receives `{module, {:join, presence}}`
  and `{module, {:leave, presence}}`, where `module` is the presence module.
  """

  @callback track_user(topic :: String.t(), key :: String.t(), meta :: map()) ::
              {:ok, binary()} | {:error, term()}
  @callback subscribe(topic :: String.t()) :: :ok | {:error, term()}
  @callback list_users(topic :: String.t()) :: [map()]
end
