# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2001-2005 Julian Hyde
# Copyright (C) 2005-2020 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../../test_helper"

# Mock Execution subclass that tracks checkCancelOrTimeout calls.
# Extends the real Execution class, passing nil as the statement.
class MockSorterExecution < Java::MondrianServer::Execution
  attr_reader :cancel_check_count

  def initialize
    super(nil, 0)
    @cancel_check_count = 0
  end

  def checkCancelOrTimeout
    @cancel_check_count += 1
  end

  def getCheckCancelOrTimeoutInterval
    1
  end
end

# Java: mondrian/olap/fun/sort/SorterTest.java
describe "Sorter" do
  Sorter = Java::MondrianOlapFunSort::Sorter
  SortKeySpec = Java::MondrianOlapFunSort::SortKeySpec
  TupleCollections = Java::MondrianCalc::TupleCollections
  BreakTupleComparator = Java::MondrianOlapFunSort::TupleExpMemoComparator::BreakTupleComparator
  HierarchicalTupleKeyComparator = Java::MondrianOlapFunSort::HierarchicalTupleKeyComparator
  HierarchicalTupleComparator = Java::MondrianOlapFunSort::HierarchicalTupleComparator
  MemberOrderKeyCalcImpl = Java::MondrianOlapFun::MemberOrderKeyFunDef::CalcImpl

  # -- Mock implementations --

  MockMember = Class.new do
    include Java::MondrianOlap::Member

    def initialize(hierarchy)
      @hierarchy = hierarchy
    end

    def getHierarchy
      @hierarchy
    end

    def to_s
      "MockMember(#{@hierarchy})"
    end

    def compareTo(other)
      to_s <=> other.to_s
    end

    def hashCode
      to_s.hashCode
    end

    def equals(other)
      equal?(other)
    end

    def isNull; true; end
    def isAll; false; end
    def isParentChildLeaf; false; end
    def isParentChildPhysicalMember; false; end
  end

  MockHierarchy = Class.new do
    include Java::MondrianOlap::Hierarchy

    def initialize(name)
      @name = name
    end

    def to_s
      @name
    end
  end

  # Mock Calc that tracks dependsOn calls and supports configurable isWrapperFor.
  MockCalc = Class.new do
    include Java::MondrianCalc::Calc

    attr_reader :depends_on_calls

    def initialize(is_order_key_calc, depends_on_map, return_value)
      @is_order_key_calc = is_order_key_calc
      @depends_on_map = depends_on_map
      @return_value = return_value
      @depends_on_calls = []
    end

    def isWrapperFor(_iface)
      @is_order_key_calc
    end

    def unwrap(_iface)
      nil
    end

    def dependsOn(hierarchy)
      @depends_on_calls << hierarchy
      @depends_on_map.fetch(hierarchy, false)
    end

    def evaluate(_evaluator)
      @return_value
    end

    def getType
      nil
    end

    def accept(_calc_writer); end
    def getResultStyle; nil; end
  end

  # -- Helper methods --

  # Calls the package-private applySortSpecToComparator via reflection.
  def apply_sort_spec(evaluator, arity, chain, key)
    method = Sorter.java_class.declared_method(
      :applySortSpecToComparator,
      Java::MondrianOlap::Evaluator.java_class,
      Java::int,
      Java::OrgApacheCommonsCollectionsComparators::ComparatorChain.java_class,
      SortKeySpec.java_class
    )
    method.accessible = true
    method.invoke(nil, evaluator, java.lang.Integer.new(arity), chain, key)
  end

  # Retrieves comparators from a ComparatorChain via reflection.
  def get_chain_comparators(chain)
    field = chain.getClass.getDeclaredField("comparatorChain")
    field.accessible = true
    field.get(chain).to_a
  end

  # Retrieves the ordering bits from a ComparatorChain via reflection.
  def get_chain_ordering_bits(chain)
    field = chain.getClass.getDeclaredField("orderingBits")
    field.accessible = true
    field.get(chain)
  end

  # Creates mock evaluator, query, statement, and execution wired together.
  # Returns [evaluator_proxy, execution].
  def create_mock_evaluator_chain
    execution = MockSorterExecution.new

    # Statement proxy (interface) returning our mock execution
    statement_proxy = java.lang.reflect.Proxy.newProxyInstance(
      Java::MondrianServer::Statement.java_class.getClassLoader,
      [Java::MondrianServer::Statement.java_class].to_java(java.lang.Class),
      ->(_, method, _args) {
        case method.getName
        when "getCurrentExecution" then execution
        end
      }
    )

    # Query via Unsafe allocation (bypasses complex constructor)
    unsafe_field = java.lang.Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe")
    unsafe_field.accessible = true
    unsafe = unsafe_field.get(nil)
    query = unsafe.allocateInstance(Java::MondrianOlap::Query.java_class)
    stmt_field = Java::MondrianOlap::Query.java_class.getDeclaredField("statement")
    stmt_field.accessible = true
    stmt_field.set(query, statement_proxy)

    # Evaluator proxy (interface) returning the query
    evaluator_proxy = java.lang.reflect.Proxy.newProxyInstance(
      Java::MondrianOlap::Evaluator.java_class.getClassLoader,
      [Java::MondrianOlap::Evaluator.java_class].to_java(java.lang.Class),
      ->(_, method, args) {
        case method.getName
        when "getQuery" then query
        when "setContext" then nil
        when "savepoint" then java.lang.Integer.new(0)
        when "restore" then nil
        end
      }
    )

    [evaluator_proxy, execution]
  end

  def gen_list(member1, member2)
    tuple_list = TupleCollections.createList(2)
    1000.times do
      tuple_list.add(java.util.Arrays.asList(member1, member2))
    end
    tuple_list
  end

  # Creates a recording proxy for TupleIterable that tracks all method calls.
  # Used to verify zero interactions (replaces Mockito's verifyZeroInteractions).
  def create_recording_tuple_iterable
    calls = []
    interfaces = [Java::MondrianCalc::TupleIterable.java_class, java.lang.Iterable.java_class]
    proxy = java.lang.reflect.Proxy.newProxyInstance(
      Java::MondrianCalc::TupleIterable.java_class.getClassLoader,
      interfaces.to_java(java.lang.Class),
      ->(_, method, _args) {
        calls << method.getName
        nil
      }
    )
    [proxy, calls]
  end

  # -- Comparator selection tests --
  # tuple sort paths:
  # +--------------+---------------------+------------------------------+
  # |              |Breaking             |Non-breaking                  |
  # +--------------+---------------------+------------------------------+
  # |OrderByKey    | BreakTupleComparator|HierarchicalTupleKeyComparator|
  # +--------------+---------------------+------------------------------+
  # |Not-OrderByKey| BreakTupleComparator|HierarchicalTupleComparator   |
  # +--------------+---------------------+------------------------------+

  # Java: SorterTest#testComparatorSelectionBrkOrderByKey
  it "selects BreakTupleComparator for breaking order-by-key sort" do
    calc1 = MockCalc.new(true, {}, 1)
    calc2 = MockCalc.new(true, {}, 2)
    key1 = SortKeySpec.new(calc1, Sorter::Flag::BASC)
    key2 = SortKeySpec.new(calc2, Sorter::Flag::BDESC)

    chain = Java::OrgApacheCommonsCollectionsComparators::ComparatorChain.new
    apply_sort_spec(nil, 2, chain, key1)
    apply_sort_spec(nil, 2, chain, key2)

    comparators = get_chain_comparators(chain)
    assert_equal 2, comparators.size
    assert_kind_of BreakTupleComparator, comparators[0]
    assert_kind_of BreakTupleComparator, comparators[1]

    # Verify direction: BASC → not reversed, BDESC → reversed
    bits = get_chain_ordering_bits(chain)
    assert_equal false, bits.get(0)
    assert_equal true, bits.get(1)
  end

  # Java: SorterTest#testComparatorSelectionBrkNotOrderByKey
  it "selects BreakTupleComparator for breaking non-order-by-key sort" do
    calc1 = MockCalc.new(false, {}, 1)
    calc2 = MockCalc.new(false, {}, 2)
    key1 = SortKeySpec.new(calc1, Sorter::Flag::BASC)
    key2 = SortKeySpec.new(calc2, Sorter::Flag::BDESC)

    chain = Java::OrgApacheCommonsCollectionsComparators::ComparatorChain.new
    apply_sort_spec(nil, 2, chain, key1)
    apply_sort_spec(nil, 2, chain, key2)

    comparators = get_chain_comparators(chain)
    assert_equal 2, comparators.size
    assert_kind_of BreakTupleComparator, comparators[0]
    assert_kind_of BreakTupleComparator, comparators[1]

    bits = get_chain_ordering_bits(chain)
    assert_equal false, bits.get(0)
    assert_equal true, bits.get(1)
  end

  # Java: SorterTest#testComparatorSelectionNotBreakingOrderByKey
  it "selects HierarchicalTupleKeyComparator for non-breaking order-by-key sort" do
    calc1 = MockCalc.new(true, {}, 1)
    calc2 = MockCalc.new(true, {}, 2)
    key1 = SortKeySpec.new(calc1, Sorter::Flag::ASC)
    key2 = SortKeySpec.new(calc2, Sorter::Flag::DESC)

    chain = Java::OrgApacheCommonsCollectionsComparators::ComparatorChain.new
    apply_sort_spec(nil, 2, chain, key1)
    apply_sort_spec(nil, 2, chain, key2)

    comparators = get_chain_comparators(chain)
    assert_equal 2, comparators.size
    assert_kind_of HierarchicalTupleKeyComparator, comparators[0]
    assert_kind_of HierarchicalTupleKeyComparator, comparators[1]

    bits = get_chain_ordering_bits(chain)
    assert_equal false, bits.get(0)
    assert_equal true, bits.get(1)
  end

  # Java: SorterTest#testComparatorSelectionNotBreaking
  it "selects HierarchicalTupleComparator for non-breaking non-order-by-key sort" do
    calc1 = MockCalc.new(false, {}, 1)
    calc2 = MockCalc.new(false, {}, 2)
    key1 = SortKeySpec.new(calc1, Sorter::Flag::ASC)
    key2 = SortKeySpec.new(calc2, Sorter::Flag::DESC)

    chain = Java::OrgApacheCommonsCollectionsComparators::ComparatorChain.new
    apply_sort_spec(nil, 2, chain, key1)
    apply_sort_spec(nil, 2, chain, key2)

    comparators = get_chain_comparators(chain)
    assert_equal 2, comparators.size
    assert_kind_of HierarchicalTupleComparator, comparators[0]
    assert_kind_of HierarchicalTupleComparator, comparators[1]

    # Non-breaking comparator handles ordering internally, so both are added as non-reversed
    bits = get_chain_ordering_bits(chain)
    assert_equal false, bits.get(0)
    assert_equal false, bits.get(1)
  end

  # -- Sort and cancellation tests --

  # Java: SorterTest#testSortTuplesBreakingByKey
  it "sorts tuples with breaking order-by-key and preserves all entries" do
    evaluator, _execution = create_mock_evaluator_chain
    hierarchy1 = MockHierarchy.new("h1")
    hierarchy2 = MockHierarchy.new("h2")
    member1 = MockMember.new(hierarchy1)
    member2 = MockMember.new(hierarchy2)

    calc1 = MockCalc.new(true, {hierarchy1 => true}, 1)
    calc2 = MockCalc.new(true, {hierarchy2 => true}, 2)
    key1 = SortKeySpec.new(calc1, Sorter::Flag::BASC)
    key2 = SortKeySpec.new(calc2, Sorter::Flag::BDESC)

    tuple_list = gen_list(member1, member2)
    # Recording proxy replaces Mockito's verifyZeroInteractions(tupleIterable)
    iterable_proxy, iterable_calls = create_recording_tuple_iterable

    result = Sorter.sortTuples(
      evaluator,
      iterable_proxy,  # should not be touched when tupleList is provided
      tuple_list,
      java.util.Arrays.asList(key1, key2),
      2
    )

    # Verify the iterable was not used (list was passed in, used instead)
    assert_empty iterable_calls
    assert_equal 1000, result.size

    # Verify dependsOn was called with both hierarchies for each calc
    assert_equal true, calc1.depends_on_calls.any? { |h| h.equal?(hierarchy1) }
    assert_equal true, calc1.depends_on_calls.any? { |h| h.equal?(hierarchy2) }
    assert_equal true, calc2.depends_on_calls.any? { |h| h.equal?(hierarchy1) }
    assert_equal true, calc2.depends_on_calls.any? { |h| h.equal?(hierarchy2) }
  end

  # Java: SorterTest#testCancel
  it "checks cancellation when iterating tuples from iterable" do
    evaluator, execution = create_mock_evaluator_chain
    hierarchy1 = MockHierarchy.new("h1")
    hierarchy2 = MockHierarchy.new("h2")
    member1 = MockMember.new(hierarchy1)
    member2 = MockMember.new(hierarchy2)

    calc1 = MockCalc.new(true, {hierarchy1 => true}, 1)
    calc2 = MockCalc.new(true, {hierarchy2 => true}, 2)
    key1 = SortKeySpec.new(calc1, Sorter::Flag::ASC)
    key2 = SortKeySpec.new(calc2, Sorter::Flag::DESC)

    # Pass iterable but null tupleList to trigger iterableToList path,
    # which checks cancellation while building the list from the iterable.
    iterable = gen_list(member1, member2)
    Sorter.sortTuples(
      evaluator,
      iterable,
      nil,
      java.util.Arrays.asList(key1, key2),
      2
    )

    assert_operator execution.cancel_check_count, :>, 0
  end
end
