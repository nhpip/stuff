defmodule MethodEventTiming do

  alias CollectionServer.Server

  defmacro update(method, time) do
    prepare_update(method, time, __CALLER__.module)
  end

  def stats(raw \\ nil) do
    if enabled?(),
       do: do_stats(raw),
       else: []
  end

  def compare(old), do:
    compare(old, stats(true))

  def compare(old, new) do
    old = Enum.map(old, &make_atom/1)
    new = Enum.map(new, &make_atom/1)
    Enum.each(new, fn {method, new_time} ->
       old_time = Keyword.get(old, method, false)
       if old_time do
          delta = round(((old_time - new_time) / old_time) * 100)
          IO.puts("#{method} is #{delta}% faster/slower")
       end
    end)
  end

  def clear(), do: :ets.delete_all_objects(:method_event_timing)

  def enable(type) do
     :persistent_term.put(:method_event_timing_state, type)
     init_db()
  end

  def disable() do
     :persistent_term.erase(:method_event_timing_state)
     :ets.delete(:method_event_timing)
  end

  def enabled?() do
    if :persistent_term.get(:method_event_timing_state, false),
      do: true,
      else: false
  end

  def enabled?(CollectionServer.Server = module) do
     stat_type = :persistent_term.get(:method_event_timing_state, false)
     if stat_type == :all || stat_type == module,
        do: Server.Repo.in_transaction?() == false,
        else: false
  end

  def enabled?(module) do
    stat_type = :persistent_term.get(:method_event_timing_state, false)
    if stat_type == :all || stat_type == module,
       do: true,
       else: false
  end

  def do_update(method, time) do
    if not :ets.member(:method_event_timing, {method, :count}) do
      :ets.insert(:method_event_timing, {{method, :count}, 1})
      :ets.insert(:method_event_timing, {{method, :time}, time})
    else
      :ets.update_counter(:method_event_timing, {method, :count}, {2,1})
      :ets.update_counter(:method_event_timing, {method, :time}, {2,time})
    end
  end

  defp init_db() do
    if :ets.info(:method_event_timing) == :undefined,
       do: :ets.new(:method_event_timing, [:named_table, :public, {:write_concurrency, true}]),
       else: clear()
  end

  defp prepare_update(method, time, module) do
    quote do
      if MethodTimes.enabled?(unquote(module)),
         do: MethodTimes.do_update(unquote(method), unquote(time))
    end
  end

  defp do_stats(:raw) do
    :ets.tab2list(:method_event_timing)
    |> Enum.map(fn({{method,_},_}) -> method end)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn method ->
      time = :ets.lookup_element(:method_event_timing, {method, :time}, 2)
      count = :ets.lookup_element(:method_event_timing, {method, :count}, 2)
      {method, round(time/count)}
    end)
  end

  defp do_stats(_) do
    :ets.tab2list(:method_event_timing)
    |> Enum.map(fn({{method,_},_}) -> method end)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.each(fn method ->
      time = :ets.lookup_element(:method_event_timing, {method, :time}, 2)
      count = :ets.lookup_element(:method_event_timing, {method, :count}, 2)
      IO.puts("Method: #{inspect(method)}, count: #{count}, average time: #{inspect(round(time/count))}")
    end)
  end

  defp make_atom({k, v}) when is_binary(k), do:
    {String.to_atom(k), v}

  defp make_atom({k, v}) when is_tuple(k), do:
    {:io_lib.format("~p",[k]) |> List.flatten() |> to_string() |> String.to_atom(), v}

  defp make_atom(kv), do:
    kv

end