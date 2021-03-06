defmodule Chat.User do
  use Agent, restart: :temporary

  def start_link(
        user_number,
        user_name,
        node_name,
        socket,
        description \\ "Hey ! I'm new to this amazingly original app"
      ) do
    current_user_on_socket = Chat.get_user_by_socket(socket)

    if current_user_on_socket != nil do
      {:error, :someone_else_already_logged_in, current_user_on_socket}
    else
      if is_logged_in?(user_number) do
        {:error, :user_already_logged_in}
      else
        {:ok, pid} =
          Agent.start_link(fn ->
            %{
              user_number: user_number,
              user_name: user_name,
              node_name: node_name,
              socket: socket,
              description: description
            }
          end)

        :global.register_name(%{type: :user, user_number: user_number}, pid)
      end
    end
  end

  def get_user(user_number) do
    if is_logged_in?(user_number) do
      Agent.get(pid(user_number), fn user -> user end)
    else
      {:error, :user_not_found}
    end
  end

  def set_description(user_number, new_description) do
    if is_logged_in?(user_number) do
      Agent.update(pid(user_number), fn user -> %{user | description: new_description} end)
    else
      {:error, :user_not_found}
    end
  end

  def set_user_name(user_number, new_user_name) do
    if is_logged_in?(user_number) do
      Agent.update(pid(user_number), fn user -> %{user | user_name: new_user_name} end)
    else
      {:error, :user_not_found}
    end
  end

  defp pid(user_number) do
    :global.whereis_name(%{type: :user, user_number: user_number})
  end

  def is_logged_in?(user_number) do
    Enum.any?(:global.registered_names(), fn registered_name ->
      registered_name.type == :user && registered_name.user_number == user_number
    end)
  end

  def delete(user_number) do
    if is_logged_in?(user_number) do
      Agent.stop(pid(user_number), :normal)
    else
      {:error, :user_not_found}
    end
  end
end
