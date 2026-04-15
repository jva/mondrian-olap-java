# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2003-2005 Julian Hyde
# Copyright (C) 2005-2020 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# MockMember implementing mondrian.olap.Member for use in SqlConstraintUtils tests.
# Defined at file level to avoid constant lookup issues.
MOCK_MEMBER_COUNTER = java.util.concurrent.atomic.AtomicInteger.new(0)

MockMember = Class.new do
  include Java::MondrianOlap::Member

  attr_accessor :calculated, :expression, :parent_child_leaf, :hierarchy_value

  def initialize(identifier, options = {})
    @identifier = identifier
    @uuid = MOCK_MEMBER_COUNTER.incrementAndGet
    @calculated = options.fetch(:calculated, false)
    @expression = options[:expression]
    @parent_child_leaf = options.fetch(:parent_child_leaf, false)
    @hierarchy_value = options[:hierarchy]
  end

  def to_s
    "#{@identifier}##{@uuid}"
  end

  def compareTo(other)
    @identifier <=> other.to_s
  end

  def hashCode
    @uuid
  end

  def equals(other)
    # Use unique id for object identity, matching Mockito mock default equals behavior.
    other.is_a?(MockMember) && @uuid == other.instance_variable_get(:@uuid)
  end

  def isNull; true; end
  def isAll; false; end
  def isParentChildLeaf; @parent_child_leaf; end
  def isParentChildPhysicalMember; false; end
  def isCalculated; @calculated; end
  def getExpression; @expression; end
  def getHierarchy; @hierarchy_value; end
end

# NullFunDef implementing mondrian.olap.FunDef.
# Equivalent to CrossJoinTest.NullFunDef in Java.
NullFunDef = Class.new do
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

# MockSetEvaluator implementing Evaluator.SetEvaluator.
# Returns a preconfigured TupleIterable when evaluateTupleIterable is called.
class MockSetEvaluator
  include Java::MondrianOlap::Evaluator::SetEvaluator

  def initialize(tuple_iterable)
    @tuple_iterable = tuple_iterable
  end

  def evaluateTupleIterable(*_args)
    @tuple_iterable
  end

  def currentOrdinal; 0; end

  def currentTuple; nil; end
end

# MockEvaluator using java.lang.reflect.Proxy for the Evaluator interface.
# Routes getSetEvaluator calls to a registered map of exp -> SetEvaluator.
class MockEvaluatorHandler
  include java.lang.reflect.InvocationHandler

  def initialize
    @set_evaluators = {}
  end

  def register_set_evaluator(exp, set_evaluator)
    # Store by Java object identity
    @set_evaluators[java.lang.System.identityHashCode(exp)] = set_evaluator
  end

  def invoke(_proxy, method, args)
    case method.getName
    when "getSetEvaluator"
      exp = args[0]
      key = java.lang.System.identityHashCode(exp)
      @set_evaluators[key]
    else
      nil
    end
  end
end

# Java: mondrian/rolap/SqlConstraintUtilsTest.java
describe "SqlConstraintUtils" do
  SqlConstraintUtils = Java::MondrianRolap::SqlConstraintUtils
  TupleConstraintStruct = Java::MondrianRolap::TupleConstraintStruct
  MemberExpr = Java::MondrianMdx::MemberExpr
  ResolvedFunCall = Java::MondrianMdx::ResolvedFunCall
  NullType = Java::MondrianOlapType::NullType
  DecimalType = Java::MondrianOlapType::DecimalType
  TupleType = Java::MondrianOlapType::TupleType
  Category = Java::MondrianOlap::Category
  ParenthesesFunDef = Java::MondrianOlapFun::ParenthesesFunDef
  AggregateFunDef = Java::MondrianOlapFun::AggregateFunDef
  UnaryTupleList = Java::MondrianCalcImpl::UnaryTupleList

  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # -- Helper methods --

  def create_mock_evaluator
    handler = MockEvaluatorHandler.new
    evaluator_interface = Java::MondrianOlap::Evaluator.java_class
    proxy = java.lang.reflect.Proxy.newProxyInstance(
      evaluator_interface.getClassLoader,
      [evaluator_interface].to_java(java.lang.Class),
      handler
    )
    [proxy, handler]
  end

  def make_noncalculated_member(name)
    MockMember.new("mock[#{name}]", calculated: false)
  end

  def make_supported_expression_for_calculated_member
    member_expr = MemberExpr.new(MockMember.new("inner"))
    assert_equal true, SqlConstraintUtils.isSupportedExpressionForCalculatedMember(member_expr)
    member_expr
  end

  def make_unsupported_expression_for_calculated_member
    null_fun_def_expr = ResolvedFunCall.new(
      NullFunDef.new, [].to_java(Java::MondrianOlap::Exp), NullType.new
    )
    assert_equal false, SqlConstraintUtils.isSupportedExpressionForCalculatedMember(null_fun_def_expr)
    null_fun_def_expr
  end

  def make_unsupported_calculated_member(name)
    member_exp = make_unsupported_expression_for_calculated_member
    member = MockMember.new("mock[#{name}]", calculated: true, expression: member_exp)

    assert_equal true, member.isCalculated
    assert_equal false, SqlConstraintUtils.isSupportedCalculatedMember(member)

    member
  end

  def make_member_expr_member(result_member)
    member_exp = MemberExpr.new(result_member)
    MockMember.new("memberExpr", calculated: true, expression: member_exp)
  end

  def make_aggregate_expr_member(evaluator_handler, end_members)
    aggregated_member = MockMember.new("aggregated")
    aggregate_arg = MemberExpr.new(aggregated_member)

    # Build AggregateFunDef with a dummy FunDef
    dummy = NullFunDef.new
    fun_def = AggregateFunDef.new(dummy)
    args = [aggregate_arg].to_java(Java::MondrianOlap::Exp)
    return_type = DecimalType.new(1, 1)
    member_exp = ResolvedFunCall.new(fun_def, args, return_type)

    member = MockMember.new("aggregate", calculated: true, expression: member_exp)

    # Register the set evaluator for this aggregate arg
    tuple_list = UnaryTupleList.new(java.util.ArrayList.new(end_members))
    set_evaluator = MockSetEvaluator.new(tuple_list)
    evaluator_handler.register_set_evaluator(aggregate_arg, set_evaluator)

    assert_equal true, member.isCalculated
    assert_equal true, SqlConstraintUtils.isSupportedCalculatedMember(member)

    member
  end

  def make_parentheses_expr_member(result_member, name)
    parentheses_arg = MemberExpr.new(result_member)
    fun_def = ParenthesesFunDef.new(Category::Member)
    args = [parentheses_arg].to_java(Java::MondrianOlap::Exp)
    return_type = DecimalType.new(1, 1)
    member_exp = ResolvedFunCall.new(fun_def, args, return_type)

    member = MockMember.new("mock[#{name}]", calculated: true, expression: member_exp)

    assert_equal true, member.isCalculated
    assert_equal true, SqlConstraintUtils.isSupportedCalculatedMember(member)

    member
  end

  def assert_same_content(msg, expected, actual)
    if expected.nil?
      assert_nil actual, msg
      return
    end
    assert_equal expected.size, actual.size, "#{msg} size"
    expected.each_with_index do |exp_member, i|
      assert_same exp_member, actual.get(i), "#{msg} [#{i}]"
    end
  end

  def assert_every_expand_supported_calculated_members(msg, expected_members, arg_members, evaluator)
    expected_list = java.util.Collections.unmodifiableList(java.util.ArrayList.new(expected_members))
    arg_list = java.util.Collections.unmodifiableList(java.util.ArrayList.new(arg_members))

    result1 = SqlConstraintUtils.expandSupportedCalculatedMembers(arg_list, evaluator)
    assert_same_content("#{msg} - (list, eval)", expected_list, result1.getMembers)

    result2 = SqlConstraintUtils.expandSupportedCalculatedMembers(arg_list, evaluator, false)
    assert_same_content("#{msg} - (list, eval, false)", expected_list, result2.getMembers)

    result3 = SqlConstraintUtils.expandSupportedCalculatedMembers(arg_list, evaluator, true)
    assert_same_content("#{msg} - (list, eval, true)", expected_list, result3.getMembers)
  end

  def assert_apart_expand_supported_calculated_members(msg, expected_by_default, expected_on_disjoint, arg_members, evaluator)
    expected_list_by_default = java.util.Collections.unmodifiableList(java.util.ArrayList.new(expected_by_default))
    expected_list_on_disjoint = java.util.Collections.unmodifiableList(java.util.ArrayList.new(expected_on_disjoint))
    arg_list = java.util.Collections.unmodifiableList(java.util.ArrayList.new(arg_members))

    result1 = SqlConstraintUtils.expandSupportedCalculatedMembers(arg_list, evaluator)
    assert_same_content("#{msg} - (list, eval)", expected_list_by_default, result1.getMembers)

    result2 = SqlConstraintUtils.expandSupportedCalculatedMembers(arg_list, evaluator, false)
    assert_same_content("#{msg} - (list, eval, false)", expected_list_by_default, result2.getMembers)

    result3 = SqlConstraintUtils.expandSupportedCalculatedMembers(arg_list, evaluator, true)
    assert_same_content("#{msg} - (list, eval, true)", expected_list_on_disjoint, result3.getMembers)
  end

  def set_slicer_context(evaluator, member)
    members = java.util.ArrayList.new
    members.add(member)
    members_by_hierarchy = java.util.HashMap.new
    member_set = java.util.HashSet.new(members)
    members_by_hierarchy.put(member.getHierarchy, member_set)
    evaluator.setSlicerContext(members, members_by_hierarchy)
  end

  def find_java_class(name)
    class_loader = Java::MondrianRolap::SqlConstraintUtils.java_class.getClassLoader
    java.lang.Class.forName(name, true, class_loader)
  end

  def get_unsafe
    unsafe_field = java.lang.Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe")
    unsafe_field.accessible = true
    unsafe_field.get(nil)
  end

  # Invoke a package-private static method via reflection
  def invoke_static_method(java_class, method_name, param_types, *args)
    method = java_class.getDeclaredMethod(method_name, param_types.to_java(java.lang.Class))
    method.setAccessible(true)
    method.invoke(nil, *args)
  end

  # Create a CompoundSlicerRolapMember placeholder that returns the given hierarchy.
  # Uses Unsafe allocation and a RolapMember Proxy for the delegate.
  def create_placeholder_member(hierarchy)
    unsafe = get_unsafe
    placeholder_class = find_java_class("mondrian.rolap.RolapResult$CompoundSlicerRolapMember")
    placeholder_member = unsafe.allocateInstance(placeholder_class)

    # DelegatingRolapMember delegates getHierarchy() to its member field.
    # Create a RolapMember Proxy that returns the desired hierarchy.
    delegating_class = find_java_class("mondrian.rolap.DelegatingRolapMember")
    member_field = delegating_class.getDeclaredField("member")
    member_field.setAccessible(true)

    rolap_member_interface = find_java_class("mondrian.rolap.RolapMember")
    class_loader = rolap_member_interface.getClassLoader

    hierarchy_ref = hierarchy
    handler = Class.new do
      include java.lang.reflect.InvocationHandler

      def initialize(hierarchy)
        @hierarchy = hierarchy
      end

      def invoke(_proxy, method, _args)
        case method.getName
        when "getHierarchy"
          @hierarchy
        when "isCalculated", "isParentChildLeaf", "isParentChildPhysicalMember",
             "isAll", "isNull", "isMeasure", "isHidden", "isEvaluated"
          false
        when "getOrdinal", "getSolveOrder", "getDepth"
          java.lang.Integer.new(0)
        else
          nil
        end
      end
    end.new(hierarchy_ref)

    fake_member = java.lang.reflect.Proxy.newProxyInstance(
      class_loader,
      [rolap_member_interface].to_java(java.lang.Class),
      handler
    )
    member_field.set(placeholder_member, fake_member)

    placeholder_member
  end

  # -- Tests --

  # Java: SqlConstraintUtilsTest#testIsSupportedExpressionForCalculatedMember
  it "isSupportedExpressionForCalculatedMember" do
    # null expression
    assert_equal false, SqlConstraintUtils.isSupportedExpressionForCalculatedMember(nil),
      "null expression"

    # MemberExpr
    member_expr = MemberExpr.new(MockMember.new("test"))
    assert_equal true, SqlConstraintUtils.isSupportedExpressionForCalculatedMember(member_expr),
      "MemberExpr"

    # ResolvedFunCall-NullFunDef
    null_fun_def_expr = ResolvedFunCall.new(
      NullFunDef.new, [].to_java(Java::MondrianOlap::Exp), NullType.new
    )
    assert_equal false, SqlConstraintUtils.isSupportedExpressionForCalculatedMember(null_fun_def_expr),
      "ResolvedFunCall-NullFunDef"

    # ResolvedFunCall arguments
    arg_unsupported = ResolvedFunCall.new(
      NullFunDef.new, [].to_java(Java::MondrianOlap::Exp), NullType.new
    )
    arg_supported = MemberExpr.new(MockMember.new("supported"))
    assert_equal false, SqlConstraintUtils.isSupportedExpressionForCalculatedMember(arg_unsupported)
    assert_equal true, SqlConstraintUtils.isSupportedExpressionForCalculatedMember(arg_supported)

    no_args = [].to_java(Java::MondrianOlap::Exp)
    args_1_unsupported = [arg_unsupported].to_java(Java::MondrianOlap::Exp)
    args_1_supported = [arg_supported].to_java(Java::MondrianOlap::Exp)
    args_2_different = [arg_unsupported, arg_supported].to_java(Java::MondrianOlap::Exp)

    # Parentheses with various args
    parentheses_fun_def = ParenthesesFunDef.new(Category::Member)
    parentheses_return_type = DecimalType.new(1, 1)

    parentheses_expr = ResolvedFunCall.new(parentheses_fun_def, no_args, parentheses_return_type)
    assert_equal true, SqlConstraintUtils.isSupportedExpressionForCalculatedMember(parentheses_expr),
      "ResolvedFunCall-Parentheses()"

    parentheses_expr = ResolvedFunCall.new(parentheses_fun_def, args_1_unsupported, parentheses_return_type)
    assert_equal false, SqlConstraintUtils.isSupportedExpressionForCalculatedMember(parentheses_expr),
      "ResolvedFunCall-Parentheses(N)"

    parentheses_expr = ResolvedFunCall.new(parentheses_fun_def, args_1_supported, parentheses_return_type)
    assert_equal true, SqlConstraintUtils.isSupportedExpressionForCalculatedMember(parentheses_expr),
      "ResolvedFunCall-Parentheses(Y)"

    parentheses_expr = ResolvedFunCall.new(parentheses_fun_def, args_2_different, parentheses_return_type)
    assert_equal true, SqlConstraintUtils.isSupportedExpressionForCalculatedMember(parentheses_expr),
      "ResolvedFunCall-Parentheses(N,Y)"

    # Aggregate with various args
    dummy = NullFunDef.new
    aggregate_fun_def = AggregateFunDef.new(dummy)
    aggregate_return_type = DecimalType.new(1, 1)

    aggregate_expr = ResolvedFunCall.new(aggregate_fun_def, no_args, aggregate_return_type)
    assert_equal true, SqlConstraintUtils.isSupportedExpressionForCalculatedMember(aggregate_expr),
      "ResolvedFunCall-Aggregate()"

    aggregate_expr = ResolvedFunCall.new(aggregate_fun_def, args_1_unsupported, aggregate_return_type)
    assert_equal true, SqlConstraintUtils.isSupportedExpressionForCalculatedMember(aggregate_expr),
      "ResolvedFunCall-Aggregate(N)"

    aggregate_expr = ResolvedFunCall.new(aggregate_fun_def, args_1_supported, aggregate_return_type)
    assert_equal true, SqlConstraintUtils.isSupportedExpressionForCalculatedMember(aggregate_expr),
      "ResolvedFunCall-Aggregate(Y)"

    aggregate_expr = ResolvedFunCall.new(aggregate_fun_def, args_2_different, aggregate_return_type)
    assert_equal true, SqlConstraintUtils.isSupportedExpressionForCalculatedMember(aggregate_expr),
      "ResolvedFunCall-Aggregate(N,Y)"
  end

  # Java: SqlConstraintUtilsTest#testIsSupportedCalculatedMember
  it "isSupportedCalculatedMember" do
    # Non-calculated member
    member = MockMember.new("test")
    assert_equal false, member.isCalculated
    assert_equal false, SqlConstraintUtils.isSupportedCalculatedMember(member)

    # Calculated but null expression
    member = MockMember.new("test", calculated: true)
    assert_nil member.getExpression
    assert_equal false, SqlConstraintUtils.isSupportedCalculatedMember(member)

    # Calculated with unsupported expression
    member = MockMember.new("test", calculated: true,
      expression: make_unsupported_expression_for_calculated_member)
    assert_equal false, SqlConstraintUtils.isSupportedCalculatedMember(member)

    # Calculated with supported expression
    member = MockMember.new("test", calculated: true,
      expression: make_supported_expression_for_calculated_member)
    assert_equal true, SqlConstraintUtils.isSupportedCalculatedMember(member)
  end

  # Java: SqlConstraintUtilsTest#testReplaceCompoundSlicerPlaceholder
  it "replaceCompoundSlicerPlaceholder" do
    connection = @olap.raw_mondrian_connection

    query_text = "SELECT {[Measures].[Customer Count]} ON 0 " \
      "FROM [Sales] " \
      "WHERE [Time].[1997]"

    query = connection.parseQuery(query_text)
    query_slicer_axis = query.getSlicerAxis
    slicer_member = query_slicer_axis.getSet.getMember
    slicer_hierarchy = query.getCube.getTimeHierarchy(nil)

    execution = Java::MondrianServer::Execution.new(query.getStatement, 0)
    # RolapEvaluatorRoot is package-private; use reflection
    root_class = find_java_class("mondrian.rolap.RolapEvaluatorRoot")
    root_constructor = root_class.getDeclaredConstructor(
      [Java::MondrianServer::Execution.java_class].to_java(java.lang.Class)
    )
    root_constructor.setAccessible(true)
    root = root_constructor.newInstance(execution)

    evaluator_class = find_java_class("mondrian.rolap.RolapEvaluator")
    evaluator_constructor = evaluator_class.getDeclaredConstructor(
      [root_class].to_java(java.lang.Class)
    )
    evaluator_constructor.setAccessible(true)
    evaluator = evaluator_constructor.newInstance(root)

    expected_member = slicer_member
    set_slicer_context(evaluator, expected_member)

    placeholder_member = create_placeholder_member(slicer_hierarchy)

    # Call the package-private replaceCompoundSlicerPlaceholder
    scu_class = Java::MondrianRolap::SqlConstraintUtils.java_class
    result = invoke_static_method(
      scu_class, "replaceCompoundSlicerPlaceholder",
      [Java::MondrianOlap::Member.java_class, find_java_class("mondrian.rolap.RolapEvaluator")],
      placeholder_member, evaluator
    )

    assert_same expected_member, result
  end

  # Java: SqlConstraintUtilsTest#testExpandSupportedCalculatedMember_notCalculated
  it "expandSupportedCalculatedMember with non-calculated member" do
    evaluator, _handler = create_mock_evaluator

    member = make_noncalculated_member("0")

    constraint = TupleConstraintStruct.new
    SqlConstraintUtils.expandSupportedCalculatedMember(member, evaluator, constraint)
    result = constraint.getMembers

    refute_nil result
    assert_equal 1, result.size
    assert_same member, result.get(0)
  end

  # Java: SqlConstraintUtilsTest#testExpandSupportedCalculatedMember_calculated_unsupported
  it "expandSupportedCalculatedMember with unsupported calculated member" do
    evaluator, _handler = create_mock_evaluator

    member = make_unsupported_calculated_member("0")

    constraint = TupleConstraintStruct.new
    SqlConstraintUtils.expandSupportedCalculatedMember(member, evaluator, constraint)
    result = constraint.getMembers

    refute_nil result
    assert_equal 1, result.size
    assert_same member, result.get(0)
  end

  # Java: SqlConstraintUtilsTest#testExpandSupportedCalculatedMember_calculated_memberExpr
  it "expandSupportedCalculatedMember with MemberExpr calculated member" do
    evaluator, _handler = create_mock_evaluator

    result_member = make_noncalculated_member("0")
    member = make_member_expr_member(result_member)

    constraint = TupleConstraintStruct.new
    SqlConstraintUtils.expandSupportedCalculatedMember(member, evaluator, constraint)
    result = constraint.getMembers

    refute_nil result
    assert_equal 1, result.size
    assert_same result_member, result.get(0)
  end

  # Java: SqlConstraintUtilsTest#testExpandSupportedCalculatedMember_calculated_aggregate
  it "expandSupportedCalculatedMember with aggregate calculated member" do
    _evaluator, handler = create_mock_evaluator

    end_member0 = MockMember.new("end0")
    end_member1 = MockMember.new("end1")
    end_member2 = MockMember.new("end2")

    # 0 members in aggregate
    evaluator0, handler0 = create_mock_evaluator
    aggregated_members = []
    member = make_aggregate_expr_member(handler0, aggregated_members)
    constraint = TupleConstraintStruct.new
    SqlConstraintUtils.expandSupportedCalculatedMember(member, evaluator0, true, constraint)
    result = constraint.getMembers
    assert_same_content("", aggregated_members, result)

    # 1 member in aggregate
    evaluator1, handler1 = create_mock_evaluator
    aggregated_members = [end_member0]
    member = make_aggregate_expr_member(handler1, aggregated_members)
    constraint = TupleConstraintStruct.new
    SqlConstraintUtils.expandSupportedCalculatedMember(member, evaluator1, constraint)
    result = constraint.getMembers
    assert_same_content("", aggregated_members, result)

    # 2 members in aggregate
    evaluator2, handler2 = create_mock_evaluator
    aggregated_members = [end_member0, end_member1]
    member = make_aggregate_expr_member(handler2, aggregated_members)
    constraint = TupleConstraintStruct.new
    SqlConstraintUtils.expandSupportedCalculatedMember(member, evaluator2, constraint)
    result = constraint.getMembers
    assert_same_content("", aggregated_members, result)

    # 3 members in aggregate
    evaluator3, handler3 = create_mock_evaluator
    aggregated_members = [end_member0, end_member1, end_member2]
    member = make_aggregate_expr_member(handler3, aggregated_members)
    constraint = TupleConstraintStruct.new
    SqlConstraintUtils.expandSupportedCalculatedMember(member, evaluator3, constraint)
    result = constraint.getMembers
    assert_same_content("", aggregated_members, result)
  end

  # Java: SqlConstraintUtilsTest#testExpandSupportedCalculatedMember_calculated_parentheses
  it "expandSupportedCalculatedMember with parentheses calculated member" do
    evaluator, _handler = create_mock_evaluator

    result_member = MockMember.new("result")
    member = make_parentheses_expr_member(result_member, "0")

    constraint = TupleConstraintStruct.new
    SqlConstraintUtils.expandSupportedCalculatedMember(member, evaluator, constraint)
    result = constraint.getMembers

    refute_nil result
    assert_equal 1, result.size
    assert_same result_member, result.get(0)
  end

  # Java: SqlConstraintUtilsTest#testExpandSupportedCalculatedMembers
  it "expandSupportedCalculatedMembers" do
    end_member0 = MockMember.new("end0")
    end_member1 = MockMember.new("end1")
    end_member2 = MockMember.new("end2")

    # ()
    evaluator_a, _handler_a = create_mock_evaluator
    assert_every_expand_supported_calculated_members(
      "()", [], [], evaluator_a
    )

    # (0, 2)
    evaluator_b, _handler_b = create_mock_evaluator
    assert_every_expand_supported_calculated_members(
      "(0, 2)", [end_member0, end_member2], [end_member0, end_member2], evaluator_b
    )

    # (Aggr(0, 1), 2)
    evaluator_c, handler_c = create_mock_evaluator
    arg_member0 = make_aggregate_expr_member(handler_c, [end_member0, end_member1])
    arg_member1 = end_member2
    assert_every_expand_supported_calculated_members(
      "(Aggr(0, 1), 2)",
      [end_member0, end_member1, end_member2],
      [arg_member0, arg_member1],
      evaluator_c
    )

    # (Aggr(0, 1), Aggr(3, 2)) - note: Java test reassigns argMember1 = endMember2
    evaluator_d, handler_d = create_mock_evaluator
    arg_member0 = make_aggregate_expr_member(handler_d, [end_member0, end_member1])
    # The Java test creates a second aggregate but then overwrites argMember1 = endMember2
    arg_member1 = end_member2
    assert_every_expand_supported_calculated_members(
      "(Aggr(0, 1), Aggr(3, 2))",
      [end_member0, end_member1, end_member2],
      [arg_member0, arg_member1],
      evaluator_d
    )
  end

  # Java: SqlConstraintUtilsTest#testExpandSupportedCalculatedMembers2
  # Test with a placeholder member
  it "expandSupportedCalculatedMembers with placeholder member" do
    connection = @olap.raw_mondrian_connection

    query_text = "SELECT {[Measures].[Customer Count]} ON 0 " \
      "FROM [Sales] " \
      "WHERE [Time].[1997]"

    query = connection.parseQuery(query_text)
    query_slicer_axis = query.getSlicerAxis
    slicer_member = query_slicer_axis.getSet.getMember
    slicer_hierarchy = query.getCube.getTimeHierarchy(nil)

    execution = Java::MondrianServer::Execution.new(query.getStatement, 0)
    # RolapEvaluatorRoot is package-private
    root_class = find_java_class("mondrian.rolap.RolapEvaluatorRoot")
    root_constructor = root_class.getDeclaredConstructor(
      [Java::MondrianServer::Execution.java_class].to_java(java.lang.Class)
    )
    root_constructor.setAccessible(true)
    root = root_constructor.newInstance(execution)

    evaluator_class = find_java_class("mondrian.rolap.RolapEvaluator")
    evaluator_constructor = evaluator_class.getDeclaredConstructor(
      [root_class].to_java(java.lang.Class)
    )
    evaluator_constructor.setAccessible(true)
    evaluator = evaluator_constructor.newInstance(root)

    expected_member = slicer_member
    set_slicer_context(evaluator, expected_member)

    placeholder_member = create_placeholder_member(slicer_hierarchy)

    end_member0 = make_noncalculated_member("0")

    # (0, placeholder)
    arg_members = [end_member0, placeholder_member]
    expected_members = [end_member0, slicer_member]
    expected_members_on_disjoint = [end_member0]

    assert_apart_expand_supported_calculated_members(
      "(0, placeholder)",
      expected_members, expected_members_on_disjoint, arg_members, evaluator
    )
  end

  # Java: SqlConstraintUtilsTest#testGetSetFromCalculatedMember
  # Calculation test for non-disjoint tuples
  it "getSetFromCalculatedMember" do
    list_column1 = java.util.ArrayList.new
    list_column2 = java.util.ArrayList.new

    list_column1.add(MockMember.new("elem1_col1"))
    list_column1.add(MockMember.new("elem2_col1"))
    list_column2.add(MockMember.new("elem1_col2"))
    list_column2.add(MockMember.new("elem2_col2"))

    table = java.util.ArrayList.new
    table.add(list_column1)
    table.add(list_column2)

    result = get_calculated_member(table, 1)
    array_res = result.getMembers

    assert_equal 4, array_res.size
    assert_equal list_column1.get(0), array_res.get(0)
    assert_equal list_column1.get(1), array_res.get(1)
    assert_equal list_column2.get(0), array_res.get(2)
    assert_equal list_column2.get(1), array_res.get(3)
  end

  # Java: SqlConstraintUtilsTest#testGetSetFromCalculatedMember_disjoint
  # Calculation test for disjoint tuples
  it "getSetFromCalculatedMember disjoint" do
    arity = 2

    list_column1 = java.util.ArrayList.new
    list_column2 = java.util.ArrayList.new

    list_column1.add(MockMember.new("elem1_col1"))
    list_column1.add(MockMember.new("elem2_col1"))
    list_column2.add(MockMember.new("elem1_col2"))
    list_column2.add(MockMember.new("elem2_col2"))

    table = java.util.ArrayList.new
    table.add(list_column1)
    table.add(list_column2)

    result = get_calculated_member(table, arity)

    tuple = result.getDisjoinedTupleLists.get(0)

    assert result.getMembers.isEmpty
    assert_equal arity, tuple.getArity
    assert_equal list_column1.get(0), tuple.get(0).get(0)
    assert_equal list_column1.get(1), tuple.get(0).get(1)
    assert_equal list_column2.get(0), tuple.get(1).get(0)
    assert_equal list_column2.get(1), tuple.get(1).get(1)
  end

  # Java: SqlConstraintUtilsTest#testRemoveCalculatedAndDefaultMembers
  it "removeCalculatedAndDefaultMembers" do
    # Create a mock Hierarchy via Proxy
    hierarchy_interface = Java::MondrianOlap::Hierarchy.java_class
    default_member_holder = { member: nil }

    hierarchy_handler = Class.new do
      include java.lang.reflect.InvocationHandler

      def initialize(holder)
        @holder = holder
      end

      def invoke(_proxy, method, _args)
        if method.getName == "getDefaultMember"
          @holder[:member]
        else
          nil
        end
      end
    end.new(default_member_holder)

    hierarchy = java.lang.reflect.Proxy.newProxyInstance(
      hierarchy_interface.getClassLoader,
      [hierarchy_interface].to_java(java.lang.Class),
      hierarchy_handler
    )

    # Create members
    members = java.util.ArrayList.new
    members.add(create_member_mock(false, false, hierarchy)) # 0: passed
    members.add(create_member_mock(true, false, hierarchy))  # 1: not passed (calculated, not parent-child leaf)
    members.add(create_member_mock(true, true, hierarchy))   # 2: passed (calculated, parent-child leaf)
    members.add(create_member_mock(false, true, hierarchy))  # 3: passed
    members.add(create_member_mock(false, true, hierarchy))  # 4: default, not passed
    members.add(create_member_mock(false, false, hierarchy)) # 5: passed
    members.add(create_member_mock(true, false, hierarchy))  # 6: not passed (calculated, not parent-child leaf)

    default_member_holder[:member] = members.get(4)

    new_members = SqlConstraintUtils.removeCalculatedAndDefaultMembers(members)

    assert_equal 4, new_members.size
    assert new_members.contains(members.get(0))
    assert new_members.contains(members.get(2))
    assert new_members.contains(members.get(3))
    assert new_members.contains(members.get(5))
  end

  # Java: SqlConstraintUtilsTest#testConstrainLevel
  it "constrainLevel" do
    unsafe = get_unsafe
    connection = @olap.raw_mondrian_connection

    dialect = Java::MondrianSpi::DialectManager.createDialect(connection.getDataSource, nil)
    sql_query = Java::MondrianRolapSql::SqlQuery.new(dialect)

    # Create RolapCubeLevel, RolapCube, RolapStar.Column via Unsafe
    level_class = find_java_class("mondrian.rolap.RolapCubeLevel")
    cube_class = find_java_class("mondrian.rolap.RolapCube")
    column_class = find_java_class("mondrian.rolap.RolapStar$Column")

    level = unsafe.allocateInstance(level_class)
    base_cube = unsafe.allocateInstance(cube_class)
    column = unsafe.allocateInstance(column_class)

    # Set the cube field on the level so getCube() returns our cube
    cube_field = level_class.getDeclaredField("cube")
    cube_field.setAccessible(true)
    cube_field.set(level, base_cube)

    # Set the fact field on the cube so isVirtual() returns false.
    # isVirtual() returns (fact == null), so we need fact to be non-null.
    # Use an Unsafe-allocated MondrianDef.Table as a dummy Relation.
    mondrian_def_table_class = find_java_class("mondrian.olap.MondrianDef$Table")
    dummy_fact = unsafe.allocateInstance(mondrian_def_table_class)
    fact_field = cube_class.getDeclaredField("fact")
    fact_field.setAccessible(true)
    fact_field.set(base_cube, dummy_fact)

    # Set up level.getStarKeyColumn() to return column (used by getBaseStarKeyColumn when not virtual)
    star_key_column_field = level_class.getDeclaredField("starKeyColumn")
    star_key_column_field.setAccessible(true)
    star_key_column_field.set(level, column)

    # Set up column.getNameColumn() to return column (itself)
    name_column_field = column_class.getDeclaredField("nameColumn")
    name_column_field.setAccessible(true)
    name_column_field.set(column, column)

    # Set up column.generateExprString(query) to return "dummyName"
    # generateExprString calls getExpression().getExpression(query)
    # Create a MondrianDef.Expression proxy that returns "dummyName" directly
    expression_field = column_class.getDeclaredField("expression")
    expression_field.setAccessible(true)

    expression_interface = find_java_class("mondrian.olap.MondrianDef$Expression")
    expr_handler = Class.new do
      include java.lang.reflect.InvocationHandler

      def initialize(expr_string)
        @expr_string = expr_string
      end

      def invoke(_proxy, method, _args)
        case method.getName
        when "getExpression"
          @expr_string
        when "getGenericExpression"
          @expr_string
        when "getTableAlias"
          nil
        else
          nil
        end
      end
    end.new("dummyName")

    dummy_expression = java.lang.reflect.Proxy.newProxyInstance(
      expression_interface.getClassLoader,
      [expression_interface, find_java_class("org.eigenbase.xom.NodeDef")].to_java(java.lang.Class),
      expr_handler
    )
    expression_field.set(column, dummy_expression)

    column_value = ["dummyValue"].to_java(:string)

    level_str = SqlConstraintUtils.constrainLevel(level, sql_query, base_cube, nil, column_value, false)
    assert_equal "dummyName = 'dummyValue'", level_str
  end

  private

  def create_member_mock(is_calculated, is_parent_child_leaf, hierarchy)
    MockMember.new(
      "member_#{is_calculated}_#{is_parent_child_leaf}",
      calculated: is_calculated,
      parent_child_leaf: is_parent_child_leaf,
      hierarchy: hierarchy
    )
  end

  # Replicates the Java getCalculatedMember helper method.
  # Creates a mock member with a ResolvedFunCall expression and a mock evaluator
  # that returns the table as a TupleIterable, then calls expandSetFromCalculatedMember.
  def get_calculated_member(table, arity)
    # Build the inner ResolvedFunCall (the argument to the outer call)
    inner_fun_def = NullFunDef.new
    inner_args = [].to_java(Java::MondrianOlap::Exp)
    inner_type = build_tuple_type
    fun_call_arg = ResolvedFunCall.new(inner_fun_def, inner_args, inner_type)

    # Build the outer ResolvedFunCall
    outer_fun_def = NullFunDef.new
    outer_args = [fun_call_arg].to_java(Java::MondrianOlap::Exp)
    outer_type = build_tuple_type
    fun_call = ResolvedFunCall.new(outer_fun_def, outer_args, outer_type)

    member = MockMember.new("calcMember", calculated: true, expression: fun_call)

    # Create a TupleIterable that returns the table data
    tuple_iterable = build_tuple_iterable(table, arity)

    # Create mock SetEvaluator
    set_evaluator = MockSetEvaluator.new(tuple_iterable)

    # Create mock Evaluator that returns the set evaluator for fun_call_arg
    handler = MockEvaluatorHandler.new
    handler.register_set_evaluator(fun_call_arg, set_evaluator)
    evaluator_interface = Java::MondrianOlap::Evaluator.java_class
    evaluator = java.lang.reflect.Proxy.newProxyInstance(
      evaluator_interface.getClassLoader,
      [evaluator_interface].to_java(java.lang.Class),
      handler
    )

    constraint = TupleConstraintStruct.new
    SqlConstraintUtils.expandSetFromCalculatedMember(evaluator, member, constraint)
    constraint
  end

  def build_tuple_type
    member_type = Java::MondrianOlapType::MemberType.new(nil, nil, nil, nil)
    types = [member_type, member_type].to_java(Java::MondrianOlapType::Type)
    TupleType.new(types)
  end

  # Build a TupleIterable using AbstractTupleCursor for the given table and arity.
  # Uses java.lang.reflect.Proxy to implement TupleIterable.
  def build_tuple_iterable(table, arity)
    table_ref = table
    arity_val = arity

    iterable_handler = TupleIterableHandler.new(table_ref, arity_val)

    class_loader = Java::MondrianCalc::TupleIterable.java_class.getClassLoader
    interfaces = [
      Java::MondrianCalc::TupleIterable.java_class,
      java.lang.Iterable.java_class
    ].to_java(java.lang.Class)

    java.lang.reflect.Proxy.newProxyInstance(class_loader, interfaces, iterable_handler)
  end
end

# Handler for TupleIterable proxy.
# Defined at file level to avoid JRuby class lookup issues.
class TupleIterableHandler
  include java.lang.reflect.InvocationHandler

  def initialize(table, arity)
    @table = table
    @arity = arity
  end

  def invoke(_proxy, method, _args)
    case method.getName
    when "getArity"
      java.lang.Integer.new(@arity)
    when "iterator"
      @table.iterator
    when "tupleCursor"
      build_cursor
    when "tupleIterator"
      @table.iterator
    when "slice"
      nil
    else
      nil
    end
  end

  private

  def build_cursor
    table = @table
    arity = @arity

    # Create a concrete AbstractTupleCursor subclass
    cursor_class = Class.new(Java::MondrianCalcImpl::AbstractTupleCursor) do
      def initialize(arity, table)
        super(arity)
        @iterator = table.iterator
        @cur_list = nil
      end

      def forward
        if @iterator.hasNext
          @cur_list = @iterator.next
          true
        else
          @cur_list = nil
          false
        end
      end

      def current
        @cur_list
      end
    end

    cursor_class.new(arity, table)
  end
end
