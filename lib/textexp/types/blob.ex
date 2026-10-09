defmodule Textexp.Types.Blob do
  @moduledoc """
  Binaire stocké en BLOB SQLite.

  `ecto_libsql` envoie un binaire Elixir qui se trouve être de l'UTF-8 valide
  comme du TEXT, que SQLite tronque au premier octet nul à la relecture : une
  update Yjs sur ~50 était ainsi corrompue. On l'envoie donc explicitement
  comme `{:blob, octets}`, que le driver stocke toujours en BLOB ; il attend
  les octets sous forme de liste.
  """
  use Ash.Type

  @impl true
  def storage_type(_constraints), do: :binary

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}
  def cast_input(value, _constraints) when is_binary(value), do: {:ok, value}
  def cast_input(_value, _constraints), do: :error

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}
  def cast_stored(value, _constraints) when is_binary(value), do: {:ok, value}
  def cast_stored(_value, _constraints), do: :error

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(value, _constraints) when is_binary(value),
    do: {:ok, {:blob, :binary.bin_to_list(value)}}

  def dump_to_native(_value, _constraints), do: :error
end
