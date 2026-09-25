defmodule ZeroCoupled.Gen.PageGeneratorTest do
  @moduledoc """
  The generator tested in isolation against a minimal two-feature
  manifest fixture. This is the concrete win of committed codegen over
  V29's `@before_compile`: the diagram compiler is an ordinary function
  with ordinary inputs, so its output is directly asserted — no page has
  to compile, no macro expansion has to be dumped.
  """
  use ExUnit.Case, async: true

  alias ZeroCoupled.Gen.PageGenerator
  alias ZeroCoupled.GenFixtures

  setup_all do
    %{src: PageGenerator.generate(GenFixtures.Page)}
  end

  test "emits a Session struct with one field per slot, built from each feature's init/1", %{src: src} do
    assert src =~ "defmodule ZeroCoupled.GenFixtures.Page.Session"
    assert src =~ "defstruct alpha: nil, beta: nil"
    assert src =~ "alpha: ZeroCoupled.GenFixtures.Alpha.init(opts)"
    assert src =~ "beta: ZeroCoupled.GenFixtures.Beta.init(opts)"
  end

  test "emits a struct-matched apply_fact/2 clause per react entry", %{src: src} do
    assert src =~ "def apply_fact(session, %ZeroCoupled.GenFixtures.Alpha.Facts.Made{} = fact)"
    assert src =~ "ZeroCoupled.GenFixtures.Beta.Intents.receive_item(Map.fetch!(session, :beta), payload)"
    # the loud fallback for undeclared facts
    assert src =~ "undeclared fact"
  end

  test "splices the manifest's transform source verbatim (emitter vocab → reactor port)", %{src: src} do
    # &%{item: &1.widget} translates Alpha's :widget into Beta's :item port,
    # so the default Map.from_struct projection must NOT be used here.
    assert src =~ "payload = (&%{item: &1.widget}).(fact)"
  end

  test "emits a page_event/4 clause with the intent's param casts", %{src: src} do
    assert src =~ ~s|def page_event("make", params, socket, run)|
    assert src =~ "ZeroCoupledWeb.PageCheck.cast_params(params, n: :int)"
    assert src =~ "ZeroCoupled.GenFixtures.Alpha.Intents.make(session, args)"
  end

  test "emits per-slot assigns for change tracking via structural sharing", %{src: src} do
    assert src =~ "assign(:alpha_slot, Map.fetch!(session, :alpha))"
    assert src =~ "assign(:beta_slot, Map.fetch!(session, :beta))"
  end

  test "output is deterministic and syntactically valid Elixir", %{src: src} do
    assert PageGenerator.generate(GenFixtures.Page) == src
    # Parses without raising ⇒ the committed file will compile.
    assert {:__block__, _, _} = Code.string_to_quoted!(src)
  end
end
