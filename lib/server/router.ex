defmodule Chat.Server.Router do
  require Logger

  def route(room_name, mod, fun, args) do
    if is_private?(room_name) do
      apply(mod, fun, args)
    else
      node_name = get_node(room_name)

      if node_name != nil do
        if node_name == node() do
          apply(mod, fun, args)
        else
          {Chat.Server.TaskSupervisor, node_name}
          |> Task.Supervisor.async(Chat.Server.Router, :route, [room_name, mod, fun, args])
          |> Task.await()
        end
      else
        {:error, :room_not_found}
      end
    end
  end

  def route_to(node_name, mod, fun, args) do
    {Chat.Server.TaskSupervisor, node_name}
    |> Task.Supervisor.async(mod, fun, args)
    |> Task.await()
  end

  def is_private?(room_name) do
    room_name =~ "@private" && Registry.lookup(RoomRegistry, room_name) != []
  end

  def is_member?(room_name, member) do
    if is_private?(room_name) do
      Chat.Room.is_member?(room_name, member)
    else
      case route(room_name, Chat.Room, :members, [room_name]) do
        {:error, :room_not_found} -> false
        members -> Enum.member?(members, member)
      end
    end
  end

  def get_node(room_name) do
    case Enum.find(:global.registered_names(), fn registered_name ->
           registered_name.type == :room && registered_name.room_name == room_name
         end) do
      nil -> nil
      registered_name -> registered_name.node_name
    end
  end

  def broadcast(members, text) do
    Enum.each(members, fn member ->
      Task.Supervisor.async({Chat.Server.TaskSupervisor, member.node_name}, fn ->
        Chat.Server.write_line(member.socket, {:ok, text})
      end)
    end)
  end
end
