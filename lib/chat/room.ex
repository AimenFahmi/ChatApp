defmodule Chat.Room do
  use Agent, restart: :temporary

  require Logger

  def start_link(room_name, owner, access, description \\ "Welcome !", members \\ [])

  def start_link(room_name, owner, "public", description, members) do
    case is_valid_room_globally?(room_name) do
      true ->
        {:error, :room_already_exists}

      false ->
        name = via_tuple(room_name)

        {:ok, pid} =
          Agent.start_link(
            fn -> %{description: description, members: [owner | members], admin: owner} end,
            name: name
          )

        :global.register_name(%{type: :room, room_name: room_name, node_name: node()}, pid)
    end
  end

  def start_link(room_name, owner, "private", description, members) do
    actual_name = convert_to_private_name(room_name)

    case is_valid_room_locally?(actual_name) do
      true ->
        {:error, :room_already_exists}

      false ->
        name = via_tuple(actual_name)

        Agent.start_link(
          fn -> %{description: description, members: [owner | members], admin: owner} end,
          name: name
        )
    end
  end

  def add_member(room_name, member) do
    if is_valid_room_locally?(room_name) do
      if !is_member?(room_name, member) do
        Agent.update(via_tuple(room_name), fn room ->
          %{room | members: [member | room.members]}
        end)
      else
        {:error, :member_already_exists}
      end
    else
      {:error, :room_not_found}
    end
  end

  def remove_member(room_name, member) do
    if is_valid_room_locally?(room_name) do
      if is_member?(room_name, member) do
        Agent.update(via_tuple(room_name), fn room ->
          %{room | members: List.delete(room.members, member)}
        end)
      else
        {:error, :member_not_found}
      end
    else
      {:error, :room_not_found}
    end
  end

  def set_description(room_name, new_description) do
    if is_valid_room_locally?(room_name) do
      Agent.update(via_tuple(room_name), fn room -> %{room | description: new_description} end)
    else
      {:error, :room_not_found}
    end
  end

  def update_member(room_name, user) do
    if admin(room_name).user_number == user.user_number do
      set_admin(room_name, user)
    end

    current_members = members(room_name)

    index =
      Enum.find_index(current_members, fn member -> member.user_number == user.user_number end)

    new_members = List.replace_at(current_members, index, user)
    Agent.update(via_tuple(room_name), fn room -> %{room | members: new_members} end)
  end

  def set_admin(room_name, new_admin) do
    if is_valid_room_locally?(room_name) do
      Agent.update(via_tuple(room_name), fn room -> %{room | admin: new_admin} end)
    end
  end

  def description(room_name) do
    if is_valid_room_locally?(room_name) do
      Agent.get(via_tuple(room_name), fn room -> room.description end)
    else
      {:error, :room_not_found}
    end
  end

  def admin(room_name) do
    if is_valid_room_locally?(room_name) do
      Agent.get(via_tuple(room_name), fn room -> room.admin end)
    else
      {:error, :room_not_found}
    end
  end

  def members(room_name) do
    if is_valid_room_locally?(room_name) do
      Agent.get(via_tuple(room_name), fn room -> room.members end)
    else
      {:error, :room_not_found}
    end
  end

  def is_member?(room_name, user) do
    Enum.member?(members(room_name), user)
  end

  def is_member_by_number?(room_name, user_number) do
    Enum.any?(members(room_name), fn member -> member.user_number == user_number end)
  end

  def is_admin?(room_name, member) do
    admin(room_name) == member
  end

  def inspect(room_name) do
    if is_valid_room_locally?(room_name) do
      Agent.get(via_tuple(room_name), fn room -> room end)
    else
      {:error, :room_not_found}
    end
  end

  def delete(room_name) do
    if is_valid_room_locally?(room_name) do
      Agent.stop(via_tuple(room_name), :normal)
    else
      {:error, :room_not_found}
    end
  end

  defp is_valid_room_locally?(room_name) do
    Registry.lookup(RoomRegistry, room_name) != []
  end

  def is_valid_room_globally?(room_name) do
    Enum.any?(:global.registered_names(), fn tuple ->
      tuple.type == :room && tuple.room_name == room_name
    end)
  end

  defp via_tuple(room_name) do
    {:via, Registry, {RoomRegistry, room_name}}
  end

  defp convert_to_private_name(room_name) do
    if room_name =~ "@private" do
      room_name
    else
      room_name <> "@private"
    end
  end
end
