defmodule TextexpWeb.YDocRoomChannelTest do
  use Textexp.DataCase

  import Phoenix.ChannelTest

  alias TextexpWeb.{UserSocket, YDocRoomChannel}

  @endpoint TextexpWeb.Endpoint

  defp register_user do
    Textexp.Accounts.User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: "channel-#{System.unique_integer([:positive])}@example.com",
      password: "a-long-password",
      password_confirmation: "a-long-password"
    })
    |> Ash.create!(authorize?: false)
  end

  setup do
    %{user: register_user()}
  end

  test "joining an unknown document is refused", %{user: user} do
    assert {:error, %{reason: "unauthorized"}} =
             UserSocket
             |> socket("user_socket:#{user.id}", %{current_user: user})
             |> subscribe_and_join(YDocRoomChannel, "y_doc_room:#{Ash.UUID.generate()}")
  end
end
