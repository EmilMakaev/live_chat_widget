defmodule LiveChatWidget.Messengers.Registry do
  @moduledoc "Maps a `MessengerChannel.type` to the adapter module implementing it."

  @adapters %{
    telegram: LiveChatWidget.Messengers.Telegram
  }

  def adapter_for(type) when is_atom(type), do: Map.fetch!(@adapters, type)
  def adapter_for(type) when is_binary(type), do: adapter_for(String.to_existing_atom(type))
end
