defmodule Chat.Server.Command do
  @moduledoc """
  Module responsible of parsing and running the servers incoming commands.

  This is the most important module because it is the one implementing the
  architecture of the whole application. It is in this module that the choices
  are made on how to approach problems such as creating rooms, deleting them,
  joining them, leaving them...

  ## Commands

  The following commands can be written to the server on `PORT 4040`.

  * `LOGIN user_number user_name` the users number, name, node name and socket
    are stored in a global registry which can be accessed by any node.

  * `CREATE ROOM room_name` creates a public room on the admins node. The room
  can be joined by any user on the system. The admin is set to the user who has
  created the room.

  * `CREATE PRIVATE ROOM room_name` creates a private room on the admins node
  which cannot be 'JOIN'ed by anyone. Instead, a member of the room can 'INVITE'
  others to it. The admin is set to the user who has created the room.

  * `JOIN ROOM room_name` adds the user to the appropriate room.

  * `ROOM room_name LEAVE` removes the user from the room.

  * `ROOM room_name REMOVE MEMBER user_number` removes the appropriate user from
  the room. **Only the admin can make use of this command**.

  * `ROOM room_name SET DESCRIPTION TO new_description` sets the description of
  the room to `new_description`. **Only the admin can make use of this command**.

  * `ROOM room_name GET DESCRIPTION` returns the description of the room

  * `ROOM room_name GET MEMBERS` returns a list of all the members of the room

  * `ROOM room_name INSPECT` returns the internal representation of the room
  (namely an `Elixir.Map`)

  * `ROOM room_name ON WHICH NODE ?` returns the node on which the public room
  exists.

  * `ROOM room_name DELETE` deletes the room. **Only the admin can makes use of
  this command**.

  * `ROOM room_name SEND message` send the message to all members of the room.

  * `ROOM room_name INVTE user_number` adds the `INVITE`ed user to the room. If
  it is private, a copy of that room will be started on the new users node.

  * `LIST JOINED ROOMS` returns a list containing all the joined rooms (private
  and public)

  * `LIST ACCESSIBLE ROOMS` returns a list of all the public rooms on the system

  * `GET MYSELF` returns the internal representation of the user (namely as an
  `Elixir.Map`)

  * `SET MY DESCRIPTION TO new_description` sets the description of the user to
  `new_description` and updates all the rooms containing the user to mirror the change.

  * `SET MY USER NAME TO new_user_name` sets the name of the user to
  `new_user_name` and updates all the rooms containing the user to mirror the change.

  """
  alias Chat.Server.Router

  require Logger

  def parse(line) do
    case String.split(line) do
      ["LOGIN", user_number, user_name] ->
        {:ok, {:login, user_number, user_name}}

      ["CREATE", "ROOM", room_name] ->
        {:ok, {:create_public_room, room_name}}

      ["CREATE", "PRIVATE", "ROOM", room_name] ->
        {:ok, {:create_private_room, room_name}}

      ["JOIN", "ROOM", room_name] ->
        {:ok, {:join_room, room_name}}

      ["ROOM", room_name, "LEAVE"] ->
        {:ok, {:leave_room, room_name}}

      ["ROOM", room_name, "REMOVE", "MEMBER", user_number] ->
        {:ok, {:remove_member, room_name, user_number}}

      ["ROOM", room_name, "SET", "DESCRIPTION", "TO" | new_description] ->
        {:ok, {:set_room_description, room_name, Enum.join(new_description, " ")}}

      ["ROOM", room_name, "GET", "DESCRIPTION"] ->
        {:ok, {:get_description, room_name}}

      ["ROOM", room_name, "GET", "MEMBERS"] ->
        {:ok, {:get_members, room_name}}

      ["ROOM", room_name, "INSPECT"] ->
        {:ok, {:inspect, room_name}}

      ["ROOM", room_name, "ON", "WHICH", "NODE", "?"] ->
        {:ok, {:get_node, room_name}}

      ["ROOM", room_name, "DELETE"] ->
        {:ok, {:delete_room, room_name}}

      ["ROOM", room_name, "SEND" | message] ->
        {:ok, {:send, room_name, Enum.join(message, " ")}}

      ["LIST", "JOINED", "ROOMS"] ->
        {:ok, {:list_joined_rooms}}

      ["LIST", "ACCESSIBLE", "ROOMS"] ->
        {:ok, {:list_accessible_rooms}}

      ["GET", "MYSELF"] ->
        {:ok, {:get_myself}}

      ["SET", "MY", "DESCRIPTION", "TO" | new_description] ->
        {:ok, {:set_user_description, Enum.join(new_description, " ")}}

      ["SET", "MY", "USER", "NAME", "TO", new_user_name] ->
        {:ok, {:set_user_name, new_user_name}}

      ["ROOM", room_name, "INVITE", user_number] ->
        {:ok, {:invite_user, room_name, user_number}}

      ["LOG", "OUT"] ->
        {:ok, {:log_out}}

      _ ->
        {:error, :unknown_command}
    end
  end

  def run(socket, {:log_out}) do
    me = Chat.get_user_by_socket(socket)

    public_rooms =
      for registered_name <- :global.registered_names(),
          registered_name.type == :room,
          Enum.member?(
            Router.route(registered_name.room_name, Chat.Room, :members, [
              registered_name.room_name
            ]),
            me
          ),
          do: registered_name.room_name

    private_rooms =
      for room <- Enum.filter(Chat.rooms(), fn room -> room.room_name =~ "@private" end),
          do: room.room_name

    joined_rooms = List.flatten([private_rooms | public_rooms])

    for joined_room <- joined_rooms do
      if joined_room =~ "@private" do
        Router.apply_to_all_members(joined_room, Chat.Room, :remove_member, [joined_room, me])
      else
        Router.route(joined_room, Chat.Room, :remove_member, [joined_room, me])
      end
    end

    user_name = me.user_name
    Chat.User.delete(me.user_number)
    {:ok, formatted_response("See you soon #{user_name}")}
  end

  def run(socket, {:remove_member, room_name, user_number}) do
    me = Chat.get_user_by_socket(socket)

    if Router.is_member?(room_name, me) do
      if Router.is_admin?(room_name, me) do
        if !(me.user_number == user_number) do
          if Chat.User.is_logged_in?(user_number) do
            user = Chat.User.get_user(user_number)

            if room_name =~ "@private" do
              Router.apply_to_all_members(room_name, Chat.Room, :remove_member, [room_name, user])
            else
              Router.route(room_name, Chat.Room, :remove_member, [room_name, user])
            end

            {:ok,
             format_for_room_messages(
               room_name,
               "Removed user '#{user_number}' from room '#{room_name}'"
             )}
          else
            {:ok, format_for_room_messages(room_name, "User '#{user_number}' does not exist")}
          end
        else
          {:ok,
           format_for_room_messages(
             room_name,
             "If you want to leave the room please use: ROOM #{room_name} LEAVE"
           )}
        end
      else
        {:ok,
         format_for_room_messages(
           room_name,
           "You cannot remove a member because you are not the admin of this room"
         )}
      end
    else
      {:ok,
       format_for_room_messages(
         room_name,
         "You are not a member of '#{room_name}' or the room does not exist"
       )}
    end
  end

  def run(socket, {:invite_user, room_name, user_number}) do
    me = Chat.get_user_by_socket(socket)

    if Router.is_member?(room_name, me) do
      case Chat.User.get_user(user_number) do
        {:error, :user_not_found} ->
          {:ok, format_for_room_messages(room_name, "User '#{user_number}' does not exist")}

        user ->
          members = Router.route(room_name, Chat.Room, :members, [room_name])

          if !Router.is_member_by_number?(room_name, user_number) do
            if room_name =~ "@private" do
              Chat.Room.add_member(room_name, user)
              admin = Chat.Room.admin(room_name)
              description = Chat.Room.description(room_name)

              Router.route_to(user.node_name, Chat.Room, :start_link, [
                room_name,
                admin,
                "private",
                description,
                List.delete(members, admin)
              ])

              Router.apply_to_all_members(room_name, Chat.Room, :add_member, [room_name, user])

              {:ok,
               format_for_room_messages(
                 room_name,
                 "Added member '#{inspect({user.user_name, user.user_number})}' to room '#{
                   room_name
                 }' and started a copy of the room on node #{user.node_name}"
               ), [user | members]}
            else
              Router.route(room_name, Chat.Room, :add_member, [room_name, user])

              {:ok,
               format_for_room_messages(
                 room_name,
                 "Added member '#{inspect({user.user_name, user.user_number})}' to room '#{
                   room_name
                 }'"
               ), [user | members]}
            end
          else
            {:ok,
             format_for_room_messages(
               room_name,
               "User '#{user_number}' is already a member of the room '#{room_name}'"
             )}
          end
      end
    else
      {:ok,
       format_for_room_messages(
         room_name,
         "You are not a member of '#{room_name}' or the room does not exist"
       )}
    end
  end

  @doc """

  """
  def run(socket, {:login, user_number, user_name}) do
    # if String.match?(user_number, ~r/(\+41|0)78\d{7}/) do
    case Chat.User.start_link(user_number, user_name, node(), socket) do
      {:error, :user_already_logged_in} ->
        {:ok, formatted_response("You are already logged in")}

      {:error, :someone_else_already_logged_in, current_user_on_socket} ->
        {:ok,
         formatted_response(
           "You are currently logged in as #{
             inspect({current_user_on_socket.user_name, current_user_on_socket.user_number})
           }. You can log out using: LOG OUT"
         )}

      _ ->
        {:ok, formatted_response("We welcome the glorious #{user_name} !")}
    end

    # else
    #  {:ok, formatted_response("The number has the wrong format")}
    # end
  end

  def run(socket, {:create_public_room, room_name}) do
    me = Chat.get_user_by_socket(socket)
    actual_room_name = Chat.Room.convert_to_public_name(room_name)

    case Chat.Room.start_link(room_name, me, "public") do
      {:error, :room_already_exists} ->
        {:ok,
         format_for_room_messages(
           actual_room_name,
           "Name '#{actual_room_name}' is taken by an already existing public room."
         )}

      _ ->
        {:ok,
         format_for_room_messages(actual_room_name, "Created public room '#{actual_room_name}'")}
    end
  end

  def run(socket, {:create_private_room, room_name}) do
    me = Chat.get_user_by_socket(socket)
    actual_room_name = Chat.Room.convert_to_private_name(room_name)

    case Chat.Room.start_link(room_name, me, "private") do
      {:error, :room_already_exists} ->
        {:ok,
         format_for_room_messages(
           actual_room_name,
           "Name '#{actual_room_name}' is taken by an already existing private room."
         )}

      _ ->
        {:ok,
         format_for_room_messages(actual_room_name, "Created private room '#{actual_room_name}'")}
    end
  end

  def run(socket, {:join_room, room_name}) do
    if room_name =~ "@private" do
      {:ok, format_for_room_messages(room_name, "You can't join a private room")}
    else
      me = Chat.get_user_by_socket(socket)

      case Router.route(room_name, Chat.Room, :add_member, [room_name, me]) do
        {:error, :member_already_exists} ->
          {:ok, format_for_room_messages(room_name, "You are already a member of '#{room_name}'")}

        {:error, :room_not_found} ->
          {:ok, format_for_room_messages(room_name, "Room '#{room_name}' does not exist")}

        _ ->
          {:ok,
           format_for_room_messages(
             room_name,
             "Added member '#{inspect({me.user_name, me.user_number})}' to room '#{room_name}'"
           ), Router.route(room_name, Chat.Room, :members, [room_name])}
      end
    end
  end

  def run(socket, {:leave_room, room_name}) do
    me = Chat.get_user_by_socket(socket)

    if Router.is_member?(room_name, me) do
      members = Router.route(room_name, Chat.Room, :members, [room_name])

      if length(members) == 1 do
        run(socket, {:delete_room, room_name})
      else
        if room_name =~ "@private" do
          Router.apply_to_all_members(room_name, Chat.Room, :remove_member, [room_name, me])

          if Router.route(room_name, Chat.Room, :is_admin?, [room_name, me]) do
            new_members = Router.route(room_name, Chat.Room, :members, [room_name])
            new_admin = Enum.at(new_members, 0)

            Router.apply_to_all_members(room_name, Chat.Room, :set_admin, [
              room_name,
              new_admin
            ])

            {:ok,
             format_for_room_messages(
               room_name,
               "Removed member '#{inspect({me.user_name, me.user_number})}' from room '#{
                 room_name
               }'. The admin has been updated to #{inspect(new_admin.node_name)}"
             ), members}
          end
        else
          Router.route(room_name, Chat.Room, :remove_member, [room_name, me])

          if Router.route(room_name, Chat.Room, :is_admin?, [room_name, me]) do
            description = Router.route(room_name, Chat.Room, :description, [room_name])
            new_members = Router.route(room_name, Chat.Room, :members, [room_name])
            new_admin = Enum.at(new_members, 0)

            Router.route(room_name, Chat.Room, :delete, [room_name])

            Router.route_to(new_admin.node_name, Chat.Room, :start_link, [
              room_name,
              new_admin,
              "public",
              description,
              List.delete(new_members, new_admin)
            ])

            {:ok,
             format_for_room_messages(
               room_name,
               "Removed member '#{inspect({me.user_name, me.user_number})}' from room '#{
                 room_name
               }' and since the latter was the admin, the room has been moved to node #{
                 inspect(new_admin.node_name)
               }"
             ), members}
          else
            {:ok,
             format_for_room_messages(
               room_name,
               "Removed member '#{inspect({me.user_name, me.user_number})}' from room '#{
                 room_name
               }'"
             ), members}
          end
        end
      end
    else
      {:ok,
       format_for_room_messages(
         room_name,
         "You are not a member of '#{room_name}' or the room does not exist"
       )}
    end
  end

  def run(socket, {:set_room_description, room_name, new_description}) do
    me = Chat.get_user_by_socket(socket)

    if Router.is_member?(room_name, me) do
      if Router.is_admin?(room_name, me) do
        if room_name =~ "@private" do
          Router.apply_to_all_members(room_name, Chat.Room, :set_description, [
            room_name,
            new_description
          ])
        else
          Router.route(room_name, Chat.Room, :set_description, [room_name, new_description])
        end

        {:ok,
         format_for_room_messages(
           room_name,
           "Description of room '#{room_name}' was set to '#{new_description}'"
         ), Router.route(room_name, Chat.Room, :members, [room_name])}
      else
        {:ok,
         format_for_room_messages(
           room_name,
           "You can't set the description because you are not the admin of this room"
         )}
      end
    else
      {:ok,
       format_for_room_messages(
         room_name,
         "You are not a member of '#{room_name}' or the room does not exist"
       )}
    end
  end

  def run(socket, {:get_description, room_name}) do
    me = Chat.get_user_by_socket(socket)

    if Router.is_member?(room_name, me) do
      description = Router.route(room_name, Chat.Room, :description, [room_name])

      {:ok,
       format_for_room_messages(
         room_name,
         "Description of room '#{room_name}' is '#{description}'"
       ), Router.route(room_name, Chat.Room, :members, [room_name])}
    else
      {:ok,
       format_for_room_messages(
         room_name,
         "You are not a member of '#{room_name}' or the room does not exist"
       )}
    end
  end

  def run(socket, {:get_members, room_name}) do
    me = Chat.get_user_by_socket(socket)

    if Router.is_member?(room_name, me) do
      members = Router.route(room_name, Chat.Room, :members, [room_name])
      {:ok, format_for_room_messages(room_name, "Members: #{inspect(members)}")}
    else
      {:ok,
       format_for_room_messages(
         room_name,
         "You are not a member of '#{room_name}' or the room does not exist"
       )}
    end
  end

  def run(socket, {:inspect, room_name}) do
    me = Chat.get_user_by_socket(socket)

    if Router.is_member?(room_name, me) do
      room = Router.route(room_name, Chat.Room, :inspect, [room_name])
      {:ok, format_for_room_messages(room_name, "#{inspect(room)}")}
    else
      {:ok,
       format_for_room_messages(
         room_name,
         "You are not a member of '#{room_name}' or the room does not exist"
       )}
    end
  end

  def run(_socket, {:get_node, room_name}) do
    case Router.get_node(room_name) do
      nil ->
        {:ok,
         format_for_room_messages(
           room_name,
           "Room '#{room_name}' does not seem to exist on any node"
         )}

      node_name ->
        {:ok,
         format_for_room_messages(room_name, "Room '#{room_name}' exists on node #{node_name}")}
    end
  end

  def run(socket, {:delete_room, room_name}) do
    me = Chat.get_user_by_socket(socket)

    if Router.is_member?(room_name, me) do
      members = Router.route(room_name, Chat.Room, :members, [room_name])

      if Router.route(room_name, Chat.Room, :is_admin?, [room_name, me]) do
        if room_name =~ "@private" do
          Router.apply_to_all_members(room_name, Chat.Room, :delete, [room_name])
        else
          Router.route(room_name, Chat.Room, :delete, [room_name])
        end

        {:ok, format_for_room_messages(room_name, "Room '#{room_name}' got deleted"), members}
      else
        {:ok,
         format_for_room_messages(
           room_name,
           "You can't delete the room because you are not the admin"
         )}
      end
    else
      {:ok,
       format_for_room_messages(
         room_name,
         "You are not a member of '#{room_name}' or the room does not exist"
       )}
    end
  end

  def run(socket, {:send, room_name, message}) do
    me = Chat.get_user_by_socket(socket)

    if Router.is_member?(room_name, me) do
      {:ok, "#{me.user_name} (#{room_name}): #{message}\r\n",
       Router.route(room_name, Chat.Room, :members, [room_name])}
    else
      {:ok,
       formatted_response("You are not a member of '#{room_name}' or the room does not exist")}
    end
  end

  def run(socket, {:get_myself}) do
    me = Chat.get_user_by_socket(socket)
    {:ok, formatted_response("#{inspect(me)}")}
  end

  def run(socket, {:set_user_description, new_description}) do
    me = Chat.get_user_by_socket(socket)
    Chat.User.set_description(me.user_number, new_description)
    new_me = Chat.get_user_by_socket(socket)
    update_joined_rooms(new_me)
    {:ok, formatted_response("Your description has been set to '#{new_description}'")}
  end

  def run(socket, {:set_user_name, new_user_name}) do
    me = Chat.get_user_by_socket(socket)
    Chat.User.set_user_name(me.user_number, new_user_name)
    new_me = Chat.get_user_by_socket(socket)
    update_joined_rooms(new_me)
    {:ok, formatted_response("Your name has been set to '#{new_user_name}'")}
  end

  def run(socket, {:list_joined_rooms}) do
    me = Chat.get_user_by_socket(socket)

    public_rooms =
      for registered_name <- :global.registered_names(),
          registered_name.type == :room,
          Enum.member?(
            Router.route(registered_name.room_name, Chat.Room, :members, [
              registered_name.room_name
            ]),
            me
          ),
          do: registered_name.room_name

    private_rooms =
      for room <- Enum.filter(Chat.rooms(), fn room -> room.room_name =~ "@private" end),
          do: room.room_name

    {:ok, formatted_response("#{inspect(List.flatten([private_rooms | public_rooms]))}")}
  end

  def run(_socket, {:list_accessible_rooms}) do
    public_rooms =
      for registered_name <- :global.registered_names(),
          registered_name.type == :room,
          do: registered_name.room_name

    {:ok, formatted_response("#{inspect(List.flatten([public_rooms]))}")}
  end

  def update_joined_rooms(me) do
    room_names =
      for registered_name <- :global.registered_names(),
          registered_name.type == :room,
          Router.is_member_by_number?(registered_name.room_name, me.user_number),
          do: registered_name.room_name

    private_rooms = Enum.filter(Chat.rooms(), fn room -> room.room_name =~ "@private" end)

    for private_room <- private_rooms,
        Router.is_member_by_number?(private_room.room_name, me.user_number) do
      Router.apply_to_all_members(private_room.room_name, Chat.Room, :update_member, [
        private_room.room_name,
        me
      ])
    end

    Logger.info("Updated: #{inspect(List.flatten([private_rooms | room_names]))}")

    for room_name <- room_names do
      Router.route(room_name, Chat.Room, :update_member, [room_name, me])
    end
  end

  defp format_for_room_messages(room_name, message) do
    "(" <> room_name <> "): " <> "\#\# " <> message <> " \#\#\r\n"
  end

  defp formatted_response(string) do
    "\#\# " <> string <> " \#\#\r\n"
  end
end
