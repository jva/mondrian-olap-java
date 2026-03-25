# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (c) 2002-2020 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/olap/fun/CrossJoinTest.java
describe "CrossJoin" do
  before(:all) do
    create_olap_connection

    @cross_join = build_cross_join_fun_def
    @resolved_call = build_resolved_fun_call

    @m3 = [
      [make_mock_member("k"), make_mock_member("l")],
      [make_mock_member("m"), make_mock_member("n")]
    ]
    @m4 = [
      [make_mock_member("U"), make_mock_member("V")],
      [make_mock_member("W"), make_mock_member("X")],
      [make_mock_member("Y"), make_mock_member("Z")]
    ]
  end

  # -- Mock implementations --

  # Mock Member implementation equivalent to Java's TestMember.
  # Implements the mondrian.olap.Member interface with minimal stubs.
  MockMember = Class.new do
    include Java::MondrianOlap::Member

    def initialize(identifier)
      @identifier = identifier
    end

    def to_s
      @identifier
    end

    def compareTo(other)
      @identifier <=> other.to_s
    end

    def hashCode
      @identifier.hashCode
    end

    def equals(other)
      other.respond_to?(:to_s) && @identifier == other.to_s
    end

    def isNull; true; end
    def isAll; false; end
    def isParentChildLeaf; false; end
    def isParentChildPhysicalMember; false; end
  end

  def make_mock_member(identifier)
    MockMember.new(identifier)
  end

  # Build a NullFunDef (equivalent to CrossJoinTest.NullFunDef in Java).
  # Implements FunDef with stub methods, used as the dummy parameter for CrossJoinFunDef.
  def build_null_fun_def
    null_fun_def_class = Class.new do
      include Java::MondrianOlap::FunDef

      def getSyntax; Java::MondrianOlap::Syntax::Function; end
      def getName; ""; end
      def getDescription; ""; end
      def getReturnCategory; 0; end
      def getParameterCategories; [].to_java(:int); end
      def createCall(_validator, _args); nil; end
      def getSignature; ""; end
      def unparse(_args, _pw); end
      def compileCall(_call, _compiler); nil; end
    end
    null_fun_def_class.new
  end

  def build_cross_join_fun_def
    Java::MondrianOlapFun::CrossJoinFunDef.new(build_null_fun_def)
  end

  # Build a ResolvedFunCall with a SetType(TupleType(MemberType, MemberType)) return type.
  # Equivalent to CrossJoinTest.getResolvedFunCall() in Java.
  def build_resolved_fun_call
    args = Java::MondrianOlap::Exp[0].new
    member_type = Java::MondrianOlapType::MemberType.new(nil, nil, nil, nil)
    types = [member_type, member_type].to_java(Java::MondrianOlapType::Type)
    tuple_type = Java::MondrianOlapType::TupleType.new(types)
    return_type = Java::MondrianOlapType::SetType.new(tuple_type)

    # Use NullFunDef (not TestFunDef) — the FunDef is stored but not called during construction
    Java::MondrianMdx::ResolvedFunCall.new(build_null_fun_def, args, return_type)
  end

  # Create an ArrayTupleList from an array of member arrays.
  # Equivalent to CrossJoinTest.makeListTuple() in Java.
  def make_tuple_list(member_arrays)
    arity = member_arrays.first.length
    tuple_list = Java::MondrianCalcImpl::ArrayTupleList.new(arity)
    member_arrays.each do |members|
      java_list = java.util.ArrayList.new
      members.each { |m| java_list.add(m) }
      tuple_list.add(java_list)
    end
    tuple_list
  end

  # Format a TupleIterable or TupleList as a string.
  # Produces the same format as the Java test's toString(TupleIterable).
  # Example: "{[U, V], [W, X], [Y, Z]}"
  def tuple_iterable_to_s(iterable)
    parts = []
    iterable.each { |tuple| parts << tuple.toString }
    "{#{parts.join(', ')}}"
  end

  # Create an instance of a non-static inner class of CrossJoinFunDef via reflection.
  # Inner classes have an implicit first constructor parameter for the enclosing instance.
  def create_calc(inner_class_name)
    class_loader = Java::MondrianOlapFun::CrossJoinFunDef.java_class.class_loader
    inner_class = java.lang.Class.forName(
      "mondrian.olap.fun.CrossJoinFunDef$#{inner_class_name}", true, class_loader
    )
    constructor = inner_class.getDeclaredConstructors.first
    constructor.setAccessible(true)
    constructor.newInstance(@cross_join, @resolved_call, nil)
  end

  # Invoke a protected/package-private method via Java reflection.
  # Searches the class and its superclasses for the method.
  def invoke_method(object, method_name, param_class_names, *args)
    class_loader = object.getClass.getClassLoader
    param_types = param_class_names.map do |name|
      java.lang.Class.forName(name, true, class_loader)
    end

    cls = object.getClass
    method = nil
    while cls
      begin
        method = cls.getDeclaredMethod(method_name, param_types.to_java(java.lang.Class))
        break
      rescue java.lang.NoSuchMethodException
        cls = cls.getSuperclass
      end
    end

    method.setAccessible(true)
    method.invoke(object, *args)
  end

  def root_cause_message(exception)
    cause = exception
    cause = cause.cause while cause.cause && cause.cause != cause
    cause.message
  end

  # Execute a block within a Mondrian Locus context (required for CrossJoinIterCalc iteration).
  # Optionally accepts a custom Execution object (e.g., CountingExecution for call tracking).
  def with_locus(execution: nil)
    connection = @olap.raw_mondrian_connection
    statement = connection.getInternalStatement
    begin
      execution ||= Java::MondrianServer::Execution.new(statement, 0)
      Java::MondrianServer::Locus.execute(execution, "CrossJoinTest") { yield }
    ensure
      statement.close
    end
  end

  # Subclass of Execution that counts checkCancelOrTimeout calls.
  # Replaces Mockito's spy() + verify() pattern from the Java test.
  CountingExecution = Class.new(Java::MondrianServer::Execution) do
    def initialize(statement, timeout)
      super
      @check_count = java.util.concurrent.atomic.AtomicInteger.new(0)
    end

    def check_count
      @check_count.get
    end

    def checkCancelOrTimeout
      @check_count.incrementAndGet
      super
    end
  end

  # Look up FoodMart members by path segments using the schema reader.
  def lookup_member(*path_segments)
    schema_reader = @olap.raw_schema_reader
    segments = Java::MondrianOlap::Id::Segment.toList(*path_segments)
    schema_reader.getMemberByUniqueName(segments, true)
  end

  # -- Iterable tests --

  # Java: CrossJoinTest#testListTupleListTupleIterCalc
  it "CrossJoinIterCalc produces cross join via iterable" do
    with_properties(CheckCancelOrTimeoutInterval: 0) do
      calc = create_calc("CrossJoinIterCalc")

      l4 = make_tuple_list(@m4)
      assert_equal "{[U, V], [W, X], [Y, Z]}", tuple_iterable_to_s(l4)

      l3 = make_tuple_list(@m3)
      assert_equal "{[k, l], [m, n]}", tuple_iterable_to_s(l3)

      result = with_locus do
        invoke_method(calc, "makeIterable",
          %w[mondrian.calc.TupleIterable mondrian.calc.TupleIterable], l4, l3)
      end
      # Iterate within a Locus context since forward() calls Locus.peek()
      actual = with_locus { tuple_iterable_to_s(result) }
      expected = "{[U, V, k, l], [U, V, m, n], [W, X, k, l], " \
                 "[W, X, m, n], [Y, Z, k, l], [Y, Z, m, n]}"
      assert_equal expected, actual
    end
  end

  # Java: CrossJoinTest#testCrossJoinIterCalc_IterationCancellationOnForward
  # Verifies that checkCancelOrTimeout is called once per left-side tuple advancement
  # during cross join iteration when CheckCancelOrTimeoutInterval is 1.
  it "CrossJoinIterCalc checks cancellation on each forward of left tuple" do
    with_properties(CheckCancelOrTimeoutInterval: 1) do
      # Build product member list (8 members: Pot Scrubbers and Pots and Pans brands)
      product_members = Java::MondrianCalcImpl::UnaryTupleList.new
      [
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pot\ Scrubbers Cormorant],
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pot\ Scrubbers Denny],
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pot\ Scrubbers Red\ Wing],
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pots\ and\ Pans Cormorant],
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pots\ and\ Pans Denny],
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pots\ and\ Pans High\ Quality],
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pots\ and\ Pans Red\ Wing],
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pots\ and\ Pans Sunset]
      ].each do |path|
        member = lookup_member(*path)
        product_members.add(java.util.Collections.singletonList(member))
      end

      # Build gender member list from "select Gender.members on 0 from sales"
      connection = @olap.raw_mondrian_connection
      gender_query = connection.parseQuery("select Gender.members on 0 from sales")
      gender_result = connection.execute(gender_query)
      gender_members = Java::MondrianCalcImpl::UnaryTupleList.new
      gender_result.getAxes[0].getPositions.each do |position|
        gender_members.add(position)
      end

      # Create a counting execution to track checkCancelOrTimeout calls
      statement = gender_result.getQuery.getStatement
      counting_execution = CountingExecution.new(statement, 0)

      assert_equal 0, counting_execution.check_count

      # Iterate the cross join within a Locus using the counting execution
      total_count = Java::MondrianServer::Locus.execute(
        counting_execution, "CrossJoinTest"
      ) do
        calc = create_calc("CrossJoinIterCalc")
        iterable = invoke_method(calc, "makeIterable",
          %w[mondrian.calc.TupleIterable mondrian.calc.TupleIterable],
          product_members, gender_members)
        cursor = iterable.tupleCursor
        counter = 0
        counter += 1 while cursor.forward
        counter
      end

      # checkCancelOrTimeout is called once per left-side tuple advancement
      assert_equal product_members.size, counting_execution.check_count
      # Total iterations = product count × gender count
      assert_equal product_members.size * gender_members.size, total_count
    end
  end

  # -- Immutable list tests --

  # Java: CrossJoinTest#testImmutableListTupleListTupleListCalc
  it "ImmutableListCalc produces cross join and supports subList" do
    calc = create_calc("ImmutableListCalc")

    l4 = make_tuple_list(@m4)
    assert_equal "{[U, V], [W, X], [Y, Z]}", tuple_iterable_to_s(l4)

    l3 = make_tuple_list(@m3)
    assert_equal "{[k, l], [m, n]}", tuple_iterable_to_s(l3)

    list = invoke_method(calc, "makeList", %w[mondrian.calc.TupleList mondrian.calc.TupleList], l4, l3)
    assert_equal "{[U, V, k, l], [U, V, m, n], [W, X, k, l], " \
                 "[W, X, m, n], [Y, Z, k, l], [Y, Z, m, n]}",
                 tuple_iterable_to_s(list)

    # subList(0, 6) — full range
    sub_list = list.subList(0, 6)
    assert_equal 6, sub_list.size
    assert_equal "{[U, V, k, l], [U, V, m, n], [W, X, k, l], " \
                 "[W, X, m, n], [Y, Z, k, l], [Y, Z, m, n]}",
                 tuple_iterable_to_s(sub_list)

    # subList of subList — same range
    sub_list = sub_list.subList(0, 6)
    assert_equal 6, sub_list.size
    assert_equal "{[U, V, k, l], [U, V, m, n], [W, X, k, l], " \
                 "[W, X, m, n], [Y, Z, k, l], [Y, Z, m, n]}",
                 tuple_iterable_to_s(sub_list)

    # subList(1, 5) — middle portion
    sub_list = sub_list.subList(1, 5)
    assert_equal 4, sub_list.size
    assert_equal "{[U, V, m, n], [W, X, k, l], [W, X, m, n], [Y, Z, k, l]}",
                 tuple_iterable_to_s(sub_list)

    # subList(2, 4) — narrowing further
    sub_list = sub_list.subList(2, 4)
    assert_equal 2, sub_list.size
    assert_equal "{[W, X, m, n], [Y, Z, k, l]}", tuple_iterable_to_s(sub_list)

    # subList(1, 2) — single element
    sub_list = sub_list.subList(1, 2)
    assert_equal 1, sub_list.size
    assert_equal "{[Y, Z, k, l]}", tuple_iterable_to_s(sub_list)

    # subList from original list — various ranges
    sub_list = list.subList(1, 4)
    assert_equal 3, sub_list.size
    assert_equal "{[U, V, m, n], [W, X, k, l], [W, X, m, n]}", tuple_iterable_to_s(sub_list)

    sub_list = list.subList(2, 4)
    assert_equal 2, sub_list.size
    assert_equal "{[W, X, k, l], [W, X, m, n]}", tuple_iterable_to_s(sub_list)

    sub_list = list.subList(2, 3)
    assert_equal 1, sub_list.size
    assert_equal "{[W, X, k, l]}", tuple_iterable_to_s(sub_list)

    # Empty subList
    sub_list = list.subList(4, 4)
    assert_equal 0, sub_list.size
    assert_equal "{}", tuple_iterable_to_s(sub_list)
  end

  # -- Mutable list tests --

  # Java: CrossJoinTest#testMutableListTupleListTupleListCalc
  it "MutableListCalc produces cross join and supports sort and remove" do
    calc = create_calc("MutableListCalc")

    l1 = make_tuple_list(@m3)
    assert_equal "{[k, l], [m, n]}", tuple_iterable_to_s(l1)

    l2 = make_tuple_list(@m4)
    assert_equal "{[U, V], [W, X], [Y, Z]}", tuple_iterable_to_s(l2)

    list = invoke_method(calc, "makeList", %w[mondrian.calc.TupleList mondrian.calc.TupleList], l1, l2)
    assert_equal "{[k, l, U, V], [k, l, W, X], [k, l, Y, Z], " \
                 "[m, n, U, V], [m, n, W, X], [m, n, Y, Z]}",
                 tuple_iterable_to_s(list)

    # Sort using a member comparator
    member_comparator = java.util.Comparator.impl do |_, tuple1, tuple2|
      result = 0
      tuple1.size.times do |i|
        c = tuple1.get(i).compareTo(tuple2.get(i))
        if c != 0
          result = c
          break
        end
      end
      result
    end
    java.util.Collections.sort(list, member_comparator)
    assert_equal "{[k, l, U, V], [k, l, W, X], [k, l, Y, Z], " \
                 "[m, n, U, V], [m, n, W, X], [m, n, Y, Z]}",
                 tuple_iterable_to_s(list)

    # Remove element at index 1
    list.remove(1)
    assert_equal "{[k, l, U, V], [k, l, Y, Z], [m, n, U, V], " \
                 "[m, n, W, X], [m, n, Y, Z]}",
                 tuple_iterable_to_s(list)
  end

  # -- Result limit tests --

  # Java: CrossJoinTest#testResultLimitWithinCrossjoin
  it "throws when crossjoin result exceeds limit" do
    with_properties(ResultLimit: 1000) do
      expression = "Hierarchize(Crossjoin(" \
                   "Union({[Gender].CurrentMember}, [Gender].Children), " \
                   "Union({[Product].CurrentMember}, [Product].[Brand Name].Members)))"
      mdx = "SELECT {#{expression}} ON 0 FROM [Sales]"
      error = assert_raises(Mondrian::OLAP::Error) { @olap.execute(mdx) }
      assert_match(/exceeded limit \(1,000\)/, root_cause_message(error))
    end
  end
end
