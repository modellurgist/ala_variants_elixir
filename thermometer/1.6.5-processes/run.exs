Code.require_file("../shared/dataflow.ex", __DIR__)
Code.require_file("stage.ex", __DIR__)
Code.require_file("thermometer.ex", __DIR__)

program = Thermometer.start()
for i <- 1..30, do: Stage.push(program, 400 + rem(i, 7))
# Casts are async; give the last stage time to print before the script exits.
Process.sleep(100)
