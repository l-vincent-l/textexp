defmodule Textexp.Types.Blob do
  @moduledoc """
  Binary stored as a SQLite BLOB.

  `ecto_libsql` sends an Elixir binary that happens to be valid UTF-8 as TEXT,
  which SQLite truncates at the first NUL byte when reading it back: about one
  Yjs update in 50 got corrupted this way. So it is sent explicitly as
  `{:blob, bytes}`, which the driver always stores as a BLOB; it expects the
  bytes as a list.
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
