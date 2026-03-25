# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (c) 2002-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Mock member extending RolapMemberBase with constant hashCode (31).
# Tests that union results are independent of hash collisions.
# Equivalent to UnionFunDefTest.MemberForTest in Java.
MemberForTest = Class.new(Java::MondrianRolap::RolapMemberBase) do
  def initialize(identifier)
    super()
    @identifier = identifier
  end

  def getUniqueName
    @identifier
  end

  def hashCode
    31
  end
end

# Java: mondrian/olap/fun/UnionFunDefTest.java
describe "UnionFunDef" do
  before(:all) do
    create_olap_connection
  end

  private

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

  def build_resolved_fun_call
    args = Java::MondrianOlap::Exp[0].new
    member_type = Java::MondrianOlapType::MemberType.new(nil, nil, nil, nil)
    types = [member_type, member_type].to_java(Java::MondrianOlapType::Type)
    tuple_type = Java::MondrianOlapType::TupleType.new(types)
    return_type = Java::MondrianOlapType::SetType.new(tuple_type)
    Java::MondrianMdx::ResolvedFunCall.new(build_null_fun_def, args, return_type)
  end

  def create_immutable_list_calc
    cross_join = build_cross_join_fun_def
    resolved_call = build_resolved_fun_call
    class_loader = Java::MondrianOlapFun::CrossJoinFunDef.java_class.class_loader
    inner_class = java.lang.Class.forName(
      "mondrian.olap.fun.CrossJoinFunDef$ImmutableListCalc", true, class_loader
    )
    constructor = inner_class.getDeclaredConstructors.first
    constructor.setAccessible(true)
    constructor.newInstance(cross_join, resolved_call, nil)
  end

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

  public

  # Java: UnionFunDefTest#testMondrian2250
  # Test for MONDRIAN-2250 issue.
  # Tests that the result is independent of the hashCode.
  it "union result is independent of hashCode collisions" do
    dates = (25..28).map { |i| MemberForTest.new("[Consumption Date.Calendar].[2014-07-#{i}]") }
    unary_tuple_list = Java::MondrianCalcImpl::UnaryTupleList.new(java.util.Arrays.asList(dates.to_java(Java::MondrianOlap::Member)))

    consumption_method = MemberForTest.new("[Consumption Method].[PVR]")
    measures_average_timeshift = MemberForTest.new("[Measures].[Average Timeshift]")
    hours = %w[00 14 15 16 23]
    times = hours.map { |h| MemberForTest.new("[Consumption Time.Time].[#{h}:00]") }

    arity = 3
    array_tuple_list = Java::MondrianCalcImpl::ArrayTupleList.new(arity)
    times.each do |time|
      current_list = java.util.ArrayList.new
      current_list.add(consumption_method)
      current_list.add(measures_average_timeshift)
      current_list.add(time)
      array_tuple_list.add(current_list)
    end

    calc = create_immutable_list_calc
    list_for_union1 = invoke_method(calc, "makeList",
      %w[mondrian.calc.TupleList mondrian.calc.TupleList],
      unary_tuple_list, array_tuple_list)

    unary_tuple_list2 = Java::MondrianCalcImpl::UnaryTupleList.new(java.util.Arrays.asList(dates.to_java(Java::MondrianOlap::Member)))

    measures_total_viewing_time = MemberForTest.new("[Measures].[Total Viewing Time]")
    array_tuple_list2 = Java::MondrianCalcImpl::ArrayTupleList.new(arity)
    times.each do |time|
      current_list = java.util.ArrayList.new
      current_list.add(consumption_method)
      current_list.add(measures_total_viewing_time)
      current_list.add(time)
      array_tuple_list2.add(current_list)
    end

    list_for_union2 = invoke_method(calc, "makeList",
      %w[mondrian.calc.TupleList mondrian.calc.TupleList],
      unary_tuple_list2, array_tuple_list2)

    # UnionFunDef is package-private — use reflection to instantiate and call union.
    class_loader = Java::MondrianOlapFun::CrossJoinFunDef.java_class.class_loader
    union_class = java.lang.Class.forName("mondrian.olap.fun.UnionFunDef", true, class_loader)
    constructor = union_class.getDeclaredConstructors.first
    constructor.setAccessible(true)
    union_fun_def = constructor.newInstance(build_null_fun_def)

    union_method = union_class.getDeclaredMethod("union",
      [java.lang.Class.forName("mondrian.calc.TupleList", true, class_loader),
       java.lang.Class.forName("mondrian.calc.TupleList", true, class_loader),
       java.lang.Boolean::TYPE].to_java(java.lang.Class))
    union_method.setAccessible(true)
    tuple_list = union_method.invoke(union_fun_def, list_for_union1, list_for_union2, false)
    assert_equal 40, tuple_list.size
  end

  # Java: UnionFunDefTest#testArity4TupleUnion
  it "arity-4 tuple union removes duplicates" do
    tuple_set =
      "CrossJoin( [Customers].[USA].Children," \
      " CrossJoin( Time.[1997].children, { (Gender.F, [Marital Status].M ) }) ) "
    expected =
      "{[Customers].[USA].[CA], [Time].[1997].[Q1], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[USA].[CA], [Time].[1997].[Q2], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[USA].[CA], [Time].[1997].[Q3], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[USA].[CA], [Time].[1997].[Q4], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[USA].[OR], [Time].[1997].[Q1], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[USA].[OR], [Time].[1997].[Q2], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[USA].[OR], [Time].[1997].[Q3], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[USA].[OR], [Time].[1997].[Q4], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[USA].[WA], [Time].[1997].[Q1], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[USA].[WA], [Time].[1997].[Q2], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[USA].[WA], [Time].[1997].[Q3], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[USA].[WA], [Time].[1997].[Q4], [Gender].[F], [Marital Status].[M]}"

    assert_axis_returns @olap, "Union( #{tuple_set}, #{tuple_set})", expected
  end

  # Java: UnionFunDefTest#testArity5TupleUnion
  it "arity-5 tuple union removes duplicates" do
    tuple_set =
      "CrossJoin( [Customers].[Canada].Children, " \
      "CrossJoin( [Time].[1997].lastChild, " \
      "CrossJoin ([Education Level].children,{ (Gender.F, [Marital Status].M ) })) )"
    expected =
      "{[Customers].[Canada].[BC], [Time].[1997].[Q4], [Education Level].[Bachelors Degree], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q4], [Education Level].[Graduate Degree], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q4], [Education Level].[High School Degree], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q4], [Education Level].[Partial College], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q4], [Education Level].[Partial High School], [Gender].[F], [Marital Status].[M]}"

    assert_axis_returns @olap, tuple_set, expected
    assert_axis_returns @olap, "Union( #{tuple_set}, #{tuple_set})", expected
  end

  # Java: UnionFunDefTest#testArity5TupleUnionAll
  it "arity-5 tuple union ALL retains duplicates" do
    tuple_set =
      "CrossJoin( [Customers].[Canada].Children, " \
      "CrossJoin( [Time].[1998].firstChild, " \
      "CrossJoin ([Education Level].members,{ (Gender.F, [Marital Status].M ) })) )"
    expected =
      "{[Customers].[Canada].[BC], [Time].[1998].[Q1], [Education Level].[All Education Levels], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1998].[Q1], [Education Level].[Bachelors Degree], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1998].[Q1], [Education Level].[Graduate Degree], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1998].[Q1], [Education Level].[High School Degree], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1998].[Q1], [Education Level].[Partial College], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1998].[Q1], [Education Level].[Partial High School], [Gender].[F], [Marital Status].[M]}"

    assert_axis_returns @olap, tuple_set, expected
    assert_axis_returns @olap, "Union( #{tuple_set}, #{tuple_set}, ALL)", "#{expected}\n#{expected}"
  end

  # Java: UnionFunDefTest#testArity6TupleUnion
  it "arity-6 tuple union removes duplicates" do
    tuple_set1 =
      "CrossJoin( [Customers].[Canada].Children, " \
      "CrossJoin( [Time].[1997].firstChild, " \
      "CrossJoin ([Education Level].lastChild," \
      "CrossJoin ([Yearly Income].lastChild," \
      "{ (Gender.F, [Marital Status].M ) })) ) )"
    tuple_set2 =
      "CrossJoin( [Customers].[Canada].Children, " \
      "CrossJoin( [Time].[1997].firstChild, " \
      "CrossJoin ([Education Level].lastChild," \
      "CrossJoin ([Yearly Income].children," \
      "{ (Gender.F, [Marital Status].M ) })) ) )"

    tuple_set1_expected =
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$90K - $110K], [Gender].[F], [Marital Status].[M]}"
    assert_axis_returns @olap, tuple_set1, tuple_set1_expected

    tuple_set2_expected =
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$10K - $30K], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$110K - $130K], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$130K - $150K], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$150K +], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$30K - $50K], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$50K - $70K], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$70K - $90K], [Gender].[F], [Marital Status].[M]}\n" \
      "#{tuple_set1_expected}"
    assert_axis_returns @olap, tuple_set2, tuple_set2_expected

    assert_axis_returns @olap, "Union( #{tuple_set2}, #{tuple_set1})", tuple_set2_expected
  end

  # Java: UnionFunDefTest#testArity6TupleUnionAll
  it "arity-6 tuple union ALL retains duplicates" do
    tuple_set1 =
      "CrossJoin( [Customers].[Canada].Children, " \
      "CrossJoin( [Time].[1997].firstChild, " \
      "CrossJoin ([Education Level].lastChild," \
      "CrossJoin ([Yearly Income].lastChild," \
      "{ (Gender.F, [Marital Status].M ) })) ) )"
    tuple_set2 =
      "CrossJoin( [Customers].[Canada].Children, " \
      "CrossJoin( [Time].[1997].firstChild, " \
      "CrossJoin ([Education Level].lastChild," \
      "CrossJoin ([Yearly Income].children," \
      "{ (Gender.F, [Marital Status].M ) })) ) )"

    tuple_set1_expected =
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$90K - $110K], [Gender].[F], [Marital Status].[M]}"
    assert_axis_returns @olap, tuple_set1, tuple_set1_expected

    tuple_set2_expected =
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$10K - $30K], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$110K - $130K], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$130K - $150K], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$150K +], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$30K - $50K], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$50K - $70K], [Gender].[F], [Marital Status].[M]}\n" \
      "{[Customers].[Canada].[BC], [Time].[1997].[Q1], [Education Level].[Partial High School], [Yearly Income].[$70K - $90K], [Gender].[F], [Marital Status].[M]}\n" \
      "#{tuple_set1_expected}"
    assert_axis_returns @olap, tuple_set2, tuple_set2_expected

    assert_axis_returns @olap, "Union( #{tuple_set1}, #{tuple_set2}, ALL)",
      "#{tuple_set1_expected}\n#{tuple_set2_expected}"
  end
end
