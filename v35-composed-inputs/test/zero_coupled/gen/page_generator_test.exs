defmodule ZeroCoupled.Gen.PageGeneratorTest do
  @moduledoc """
  The generator tested in isolation against a minimal two-feature
  manifest fixture. This is the concrete win of committed codegen over
  V29's `@before_compile`: the diagram compiler is an ordinary function
  with ordinary inputs, so its output is directly asserted — no page has
  to compile, no macro expansion has to be dumped.
  """
  use ExUnit.Case, async: true

  alias ZeroCoupled.Gen.{FlowsGenerator, PageGenerator}
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

  test "emits declared_facts/0 so the page can forward external fact structs", %{src: src} do
    assert src =~ "def declared_facts do"
    assert src =~ "[ZeroCoupled.GenFixtures.Alpha.Facts.Made]"
  end

  describe "the flows channel (V33)" do
    test "emits web-side flow glue: milestones, step URLs, param translation", %{src: src} do
      assert src =~ "def flow_milestones(:wizard) do"
      assert src =~ ~s|[one: "One", two: "Two"]|
      assert src =~ "def flow_path(:wizard, :one) do"
      assert src =~ ~s|"/w"|
      assert src =~ "def flow_path(:wizard, :two) do"
      assert src =~ ~s|"/w/two"|
      # steps without a path fall through to nil (no patch emitted)
      assert src =~ "def flow_path(_flow, _step) do"
      assert src =~ "def flow_param_step(:wizard, params)"
    end

    test "flows_source merges page flows into the neutral core module" do
      src = FlowsGenerator.flows_source([GenFixtures.Page])
      assert src =~ "defmodule ZeroCoupled.Flows"
      assert src =~ "def initial(:wizard) do"
      assert src =~ "def advance(:wizard, :one, :go) do"
      assert src =~ "def advance(:wizard, :two, :finish) do"
      assert src =~ "def advance(:wizard, _from, _event) do"
      assert src =~ ":no_transition"
      assert src =~ "def steps(:wizard) do"
      assert src =~ "[:one, :two, :done]"
      assert {:defmodule, _, _} = Code.string_to_quoted!(src)
    end

    test "flows_source is nil when no page declares flows" do
      assert FlowsGenerator.flows_source([]) == nil
    end
  end
end
