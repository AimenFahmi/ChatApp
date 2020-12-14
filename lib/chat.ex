defmodule Chat do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      {Chat.Supervisor, name: Chat.Supervisor},
      {Chat.Server.Supervisor, name: Chat.Server.Supervisor}
    ]

    Supervisor.start_link(children, name: Supervisor, strategy: :one_for_one)
  end

  def rooms do
    Registry.select(RoomRegistry, [
      {{:"$1", :"$2", :_}, [], [%{room_name: :"$1", room_pid: :"$2"}]}
    ])
  end

  def private_rooms do
    Enum.filter(rooms(), fn room -> room.room_name =~ "@private" end)
  end

  def inspect_rooms do
    Enum.map(Chat.rooms(), fn room -> Chat.Room.inspect(room.room_name) end)
  end

  def users do
    Enum.filter(:global.registered_names(), fn registered_name ->
      registered_name.type == :user
    end)
  end

  def inspect_users do
    Enum.map(Chat.users(), fn user -> Chat.User.get_user(user.user_number) end)
  end

  def get_user_by_socket(socket) do
    users = Chat.inspect_users()

    Logger.info("#{inspect(users)}")

    Enum.find(users, fn user ->
      user.socket == socket
    end)
  end
end
