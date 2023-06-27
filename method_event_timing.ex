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

  def compare(old, new, ignore \\ []) do
    old = Enum.map(old, &make_atom/1) |> Enum.filter(&(not Enum.member?(ignore, &1)))
    new = Enum.map(new, &make_atom/1) |> Enum.filter(&(not Enum.member?(ignore, &1)))
    res = Enum.reduce(new, {0, 0, 0, 0}, fn({method, {new_time, new_count}}, {acc_d, acc_ot, acc_nt, acc_c} = acc) ->
       {old_time, old_count} = Keyword.get(old, method, {false, 0})
       if old_time do
          count = round((new_count+old_count)/2)
          delta = round(((new_time - old_time) / new_time) * 100) * -1
          IO.puts("#{method} is #{delta}% #{f_or_s(delta)} (#{old_time},#{new_time},#{count})")
          {acc_d + delta, acc_ot + old_time, acc_nt + new_time, acc_c + 1}
       else
          acc
       end
    end)
    {deltas, old_times, new_times, count} = res
    old_times_avg = round(old_times / count)
    new_times_avg = round(new_times / count)
    time_average = round(((new_times - old_times) / new_times) * 100) * -1
    delta_average = round(deltas / count)
    IO.puts("")
    IO.puts("Old time total: #{old_times}, average: #{old_times_avg}")
    IO.puts("New time total: #{new_times}, average: #{new_times_avg}")
    IO.puts("Time average - New is #{time_average}% #{f_or_s(time_average)} than old")
    IO.puts("Percent average - New is #{delta_average}% #{f_or_s(delta_average)} than old")
    IO.puts("")
  end

  defp f_or_s(t) when t >= 0, do: :faster
  defp f_or_s(_ ), do: :slower

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
      if MethodEventTiming.enabled?(unquote(module)),
         do: MethodEventTiming.do_update(unquote(method), unquote(time))
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
      {method, {round(time/count), count}}
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
