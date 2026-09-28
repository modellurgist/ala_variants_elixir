# Spray §1.6.1, ported to Elixir: procedures that call each other as peers, literals
# baked in, and hidden state in the process dictionary. Spray's literals, not ours.
defmodule BadThermometer do
  def smooth_temperature(t) do
    filtered = Process.get(:filtered, 0.0) * 9 / 10 + t / 10   # hidden shared state
    Process.put(:filtered, filtered)
    filtered
  end

  def display_temperature(t), do: IO.puts("Temperature: #{Float.round(t, 1)} C")

  def resample_temperature(t) do
    counter = Process.get(:counter, 0) + 1
    if counter >= 15 do
      Process.put(:counter, 0)
      display_temperature(t)                                   # peer call
    else
      Process.put(:counter, counter)
    end
  end

  def process_temperatures(adcs) do
    Enum.each(adcs, fn adc ->
      t = (adc + 4) * 8.3                                      # baked application literal, inline
      t = smooth_temperature(t)                                # peer call
      resample_temperature(t)                                  # peer call
    end)
  end
end
