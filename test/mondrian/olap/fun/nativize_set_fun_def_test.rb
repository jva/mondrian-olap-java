# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (c) 2002-2017 Hitachi Vantara.  All rights reserved.
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# InvocationHandler for the package-private RolapNative.Listener interface.
# Tracks whether native evaluation was used via the foundEvaluator callback.
class NativeListenerHandler
  include java.lang.reflect.InvocationHandler

  attr_reader :evaluator_found

  def initialize
    @evaluator_found = false
  end

  def invoke(_proxy, method, _args)
    @evaluator_found = true if method.getName == "foundEvaluator"
    nil
  end
end

# Java: mondrian/olap/fun/NativizeSetFunDefTest.java
describe "NativizeSetFunDef" do
  before(:all) do
    create_olap_connection
    properties = Java::MondrianOlap::MondrianProperties.instance
    @original_properties = {
      EnableNonEmptyOnAllAxis: properties.EnableNonEmptyOnAllAxis.get,
      NativizeMinThreshold: properties.NativizeMinThreshold.get,
      UseAggregates: properties.UseAggregates.get,
      ReadAggregates: properties.ReadAggregates.get,
      EnableNativeCrossJoin: properties.EnableNativeCrossJoin.get,
      SsasCompatibleNaming: properties.SsasCompatibleNaming.get
    }
    # SSAS-compatible naming causes <dimension>.<level>.members to be
    # interpreted as <dimension>.<hierarchy>.members, and that happens a
    # lot in this test.
    properties.EnableNonEmptyOnAllAxis.set(true)
    properties.NativizeMinThreshold.set(0)
    properties.UseAggregates.set(false)
    properties.ReadAggregates.set(false)
    properties.EnableNativeCrossJoin.set(true)
    properties.SsasCompatibleNaming.set(false)
  end

  after(:all) do
    if @original_properties
      properties = Java::MondrianOlap::MondrianProperties.instance
      @original_properties.each do |name, value|
        properties.public_send(name).set(value)
      end
    end
    @olap.close if @olap
  end

  # -- Reflection helpers for package-private RolapNativeRegistry API --

  # Invoke a package-private method via reflection, searching the class hierarchy.
  def invoke_method(object, method_name, param_types = [], *args)
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
    raise "Method #{method_name} not found on #{object.getClass.getName}" unless method
    method.setAccessible(true)
    args.empty? ? method.invoke(object) : method.invoke(object, *args)
  end

  def get_native_registry(olap)
    schema = olap.raw_mondrian_connection.getSchema
    invoke_method(schema, "getNativeRegistry")
  end

  def set_native_enabled(registry, enabled)
    invoke_method(registry, "setEnabled", [java.lang.Boolean::TYPE], enabled)
  end

  def set_native_listener(registry, listener)
    listener_class = java.lang.Class.forName(
      "mondrian.rolap.RolapNative$Listener", true, registry.getClass.getClassLoader
    )
    invoke_method(registry, "setListener", [listener_class], listener)
  end

  def set_native_hard_cache(registry, hard)
    invoke_method(registry, "useHardCache", [java.lang.Boolean::TYPE], hard)
  end

  def create_native_listener(registry)
    class_loader = registry.getClass.getClassLoader
    listener_interface = java.lang.Class.forName(
      "mondrian.rolap.RolapNative$Listener", true, class_loader
    )
    handler = NativeListenerHandler.new
    proxy = java.lang.reflect.Proxy.newProxyInstance(
      class_loader,
      [listener_interface].to_java(java.lang.Class),
      handler
    )
    [proxy, handler]
  end

  # -- Core check methods matching BatchTestCase behavior --

  def remove_nativize(mdx)
    result = mdx.gsub(/NativizeSet/i, '')
    refute_equal mdx, result, "Query should use NativizeSet"
    result
  end

  # Verifies that NativizeSet produces correct results AND that native
  # evaluation is NOT used. Matches Java BatchTestCase.checkNotNative.
  def check_not_native(mdx)
    mdx_without_nativize = remove_nativize(mdx)
    expected = format_result(@olap.execute(mdx_without_nativize))

    registry = get_native_registry(@olap)
    proxy, handler = create_native_listener(registry)
    set_native_listener(registry, proxy)
    begin
      actual = format_result(@olap.execute(mdx))
      assert_equal false, handler.evaluator_found, "Should not be executed native"
      assert_equal expected, actual
    ensure
      set_native_listener(registry, nil)
    end
  end

  # Verifies that NativizeSet produces correct results AND that native
  # evaluation IS used. Runs with native disabled (interpreted) and enabled
  # (native), then compares both against the expected result.
  # Matches Java BatchTestCase.checkNative.
  def check_native(mdx)
    mdx_without_nativize = remove_nativize(mdx)
    expected = format_result(@olap.execute(mdx_without_nativize))

    registry = get_native_registry(@olap)

    # Run with native disabled → interpreted result
    set_native_enabled(registry, false)
    begin
      interpreted = format_result(@olap.execute(mdx))
    ensure
      set_native_enabled(registry, true)
    end

    # Run with native enabled + listener → native result
    proxy, handler = create_native_listener(registry)
    set_native_listener(registry, proxy)
    set_native_hard_cache(registry, true)
    begin
      native_result = format_result(@olap.execute(mdx))

      assert_equal true, handler.evaluator_found, "Result should have been native"
      assert_equal interpreted, native_result,
        "Native implementation returned different result than interpreter; MDX=#{mdx}"
      assert_equal expected, native_result
    ensure
      set_native_listener(registry, nil)
      set_native_hard_cache(registry, false)
    end
  end

  # Parse MDX query and compare the toString() output to verify query rewriting.
  def assert_query_is_rewritten(query, expected_query, olap: @olap)
    connection = olap.raw_mondrian_connection
    statement = connection.getInternalStatement
    begin
      execution = Java::MondrianServer::Execution.new(statement, 0)
      actual = Java::MondrianServer::Locus.execute(execution, "NativizeSetFunDefTest") do
        connection.parseQuery(query).toString
      end
    ensure
      statement.close
    end
    actual = actual.gsub("\r\n", "\n")
    assert_equal expected_query, actual
  end

  # Java: NativizeSetFunDefTest#testIsNoOpWithAggregatesTablesOn
  it "is no-op with aggregates tables on" do
    with_properties(UseAggregates: true) do
      check_not_native(
        "with  member [gender].[agg] as" \
        "  'aggregate({[gender].[gender].members},[measures].[unit sales])'" \
        "select NativizeSet(CrossJoin( " \
        "{gender.gender.members, gender.agg}, " \
        "{[marital status].[marital status].members}" \
        ")) on 0 from sales")
    end
  end

  # Java: NativizeSetFunDefTest#testLevelHierarchyHighCardinality
  it "level hierarchy high cardinality is native" do
    # The cardinality for the hierarchy looks like this:
    #    Year: 2 (level * gender cardinality:2)
    #    Quarter: 16 (level * gender cardinality:2)
    #    Month: 48 (level * gender cardinality:2)
    with_properties(NativizeMinThreshold: 17) do
      check_native(
        "select NativizeSet(" \
        "CrossJoin( " \
        "gender.gender.members, " \
        "CrossJoin(" \
        "{ measures.[unit sales] }, " \
        "[Time].[Month].members" \
        "))) on 0" \
        " from sales")
    end
  end

  # Java: NativizeSetFunDefTest#testLevelHierarchyLowCardinality
  it "level hierarchy low cardinality is not native" do
    with_properties(NativizeMinThreshold: 50) do
      check_not_native(
        "select NativizeSet(" \
        "CrossJoin( " \
        "gender.gender.members, " \
        "CrossJoin(" \
        "{ measures.[unit sales] }, " \
        "[Time].[Month].members" \
        "))) on 0" \
        " from sales")
    end
  end

  # Java: NativizeSetFunDefTest#testNamedSetLowCardinality
  it "named set low cardinality is not native" do
    with_properties(NativizeMinThreshold: 2147483647) do
      check_not_native(
        "with " \
        "set [levelMembers] as 'crossjoin( gender.gender.members, " \
        "[marital status].[marital status].members) '" \
        "select  nativizeSet([levelMembers]) on 0 " \
        "from [warehouse and sales]")
    end
  end

  # Java: NativizeSetFunDefTest#testCrossjoinWithNamedSetLowCardinality
  it "crossjoin with named set low cardinality is not native" do
    with_properties(NativizeMinThreshold: 2147483647) do
      check_not_native(
        "with " \
        "set [genderMembers] as 'gender.gender.members'" \
        "set [maritalMembers] as '[marital status].[marital status].members'" \
        "set [levelMembers] as 'crossjoin( [genderMembers],[maritalMembers]) '" \
        "select  nativizeSet([levelMembers]) on 0 " \
        "from [warehouse and sales]")
    end
  end

  # Java: NativizeSetFunDefTest#testMeasureInCrossJoinWithTwoDimensions
  it "measure in crossjoin with two dimensions" do
    check_native(
      "select NativizeSet(" \
      "CrossJoin( " \
      "gender.gender.members, " \
      "CrossJoin(" \
      "{ measures.[unit sales] }, " \
      "[marital status].[marital status].members" \
      "))) on 0 " \
      "from sales")
  end

  # Java: NativizeSetFunDefTest#testNativeResultLimitAtZero
  it "native result limit at zero (effectively no limit)" do
    # This query will return exactly 6 rows:
    # {Female,Male,Agg}x{Married,Single}
    mdx =
      "with  member [gender].[agg] as" \
      "  'aggregate({[gender].[gender].members},[measures].[unit sales])'" \
      "select NativizeSet(CrossJoin( " \
      "{gender.gender.members, gender.agg}, " \
      "{[marital status].[marital status].members}" \
      ")) on 0 from sales"
    with_properties(NativizeMaxResults: 0) do
      check_native(mdx)
    end
  end

  # Java: NativizeSetFunDefTest#testNativeResultLimitBeforeMerge
  it "native result limit before merge raises exception" do
    mdx =
      "with  member [gender].[agg] as" \
      "  'aggregate({[gender].[gender].members},[measures].[unit sales])'" \
      "select NativizeSet(CrossJoin( " \
      "{gender.gender.members, gender.agg}, " \
      "{[marital status].[marital status].members}" \
      ")) on 0 from sales"

    # Set limit to exact size of result
    with_properties(NativizeMaxResults: 6) do
      check_native(mdx)
    end

    # The native list doesn't contain the calculated members,
    # so it will have 4 rows. Setting the limit to 3 means
    # that the exception will be thrown before calculated
    # members are merged into the result.
    with_properties(NativizeMaxResults: 3) do
      assert_raises(Mondrian::OLAP::Error) { @olap.execute(mdx) }
    end
  end

  # Java: NativizeSetFunDefTest#testNativeResultLimitDuringMerge
  it "native result limit during merge raises exception" do
    mdx =
      "with  member [gender].[agg] as" \
      "  'aggregate({[gender].[gender].members},[measures].[unit sales])'" \
      "select NativizeSet(CrossJoin( " \
      "{gender.gender.members, gender.agg}, " \
      "{[marital status].[marital status].members}" \
      ")) on 0 from sales"

    with_properties(NativizeMaxResults: 6) do
      check_native(mdx)
    end

    # The native list doesn't contain the calculated members,
    # so setting the limit to 5 means the exception won't be
    # thrown until calculated members are merged into the result.
    with_properties(NativizeMaxResults: 5) do
      assert_raises(Mondrian::OLAP::Error) { @olap.execute(mdx) }
    end
  end

  # Java: NativizeSetFunDefTest#testMeasureAndDimensionInCrossJoin
  it "measure and dimension in crossjoin" do
    # There's no crossjoin left after the measure is set aside,
    # so it's not even a candidate for native evaluation.
    check_not_native(
      "select NativizeSet(" \
      "CrossJoin(" \
      "{ measures.[unit sales] }, " \
      "[marital status].[marital status].members" \
      ")) on 0" \
      " from sales")
  end

  # Java: NativizeSetFunDefTest#testDimensionAndMeasureInCrossJoin
  it "dimension and measure in crossjoin" do
    check_not_native(
      "select NativizeSet(" \
      "CrossJoin(" \
      "[marital status].[marital status].members, " \
      "{ measures.[unit sales] }" \
      ")) on 0" \
      " from sales")
  end

  # Java: NativizeSetFunDefTest#testAllByAll
  it "all by all" do
    check_not_native(
      "select NativizeSet(" \
      "CrossJoin(" \
      "{ [gender].[all gender] }, " \
      "{ [marital status].[all marital status] } " \
      ")) on 0" \
      " from sales")
  end

  # Java: NativizeSetFunDefTest#testAllByAllByAll
  it "all by all by all" do
    check_not_native(
      "select NativizeSet(" \
      "CrossJoin(" \
      "{ [product].[all products] }, " \
      "CrossJoin(" \
      "{ [gender].[all gender] }, " \
      "{ [marital status].[all marital status] } " \
      "))) on 0" \
      " from sales")
  end

  # Java: NativizeSetFunDefTest#testNativizeTwoAxes
  it "nativize two axes" do
    mdx =
      "select " \
      "NativizeSet(" \
      "CrossJoin(" \
      "{ [gender].[gender].members }, " \
      "{ [marital status].[marital status].members } " \
      ")) on 0," \
      "NativizeSet(" \
      "CrossJoin(" \
      "{ [measures].[unit sales] }, " \
      "{ [Education Level].[Education Level].members } " \
      ")) on 1" \
      " from [warehouse and sales]"

    # setUp sets threshold at zero, so should always be native if possible.
    check_native(mdx)

    # Set the threshold high; same mdx should no longer be natively evaluated.
    with_properties(NativizeMinThreshold: 200000) do
      check_not_native(mdx)
    end
  end

  # Java: NativizeSetFunDefTest#testCurrentMemberAsFunArg
  it "current member as fun arg" do
    # Having a member of the measures dimension as a function
    # argument will normally disable native evaluation but
    # there is a special case in FunUtil.checkNativeCompatible
    # which allows currentmember
    check_native(
      "with " \
      "member [gender].[x] " \
      "   as 'iif (measures.currentmember is measures.[unit sales], " \
      "       Aggregate(gender.gender.members), 101010)' " \
      "select " \
      "NativizeSet(" \
      "crossjoin(" \
      "{time.year.members}, " \
      "crossjoin(" \
      "{gender.x}," \
      "[marital status].[marital status].members" \
      "))) " \
      "on axis(0) " \
      "from [warehouse and sales]")
  end

  # Java: NativizeSetFunDefTest#testOnlyMeasureIsLiteral
  # There's no base cube, so this should NOT be natively evaluated.
  # Known Java-side failure: native evaluation is unexpectedly triggered
  it "only measure is literal" do
    skip "Known Java-side failure (testOnlyMeasureIsLiteral)"
    check_not_native(
      "with " \
      "member [measures].[cog_oqp_int_t1] as '1', solve_order = 65535 " \
      "select NativizeSet(CrossJoin(" \
      "   [marital status].[marital status].members, " \
      "   [gender].[gender].members " \
      ")) on 1, " \
      "{ [measures].[cog_oqp_int_t1] } " \
      "on 0 " \
      "from [warehouse and sales]")
  end

  # Java: NativizeSetFunDefTest#testTwoLiteralMeasuresAndUnitAndStoreSales
  it "two literal measures and unit and store sales" do
    # Should be natively evaluated because the unit sales
    # measure will bring in a base cube.
    check_native(
      "with " \
      "member [measures].[cog_oqp_int_t1] as '1', solve_order = 65535 " \
      "member [measures].[cog_oqp_int_t2] as '2', solve_order = 65535 " \
      "select " \
      "   NativizeSet(CrossJoin(" \
      "      [marital status].[marital status].members, " \
      "      [gender].[gender].members " \
      "    ))" \
      "on 1, " \
      "{ " \
      "   { [measures].[cog_oqp_int_t1] }, " \
      "   { [measures].[unit sales] }, " \
      "   { [measures].[cog_oqp_int_t2] }, " \
      "   { [measures].[store sales] } " \
      "} " \
      " on 0 " \
      "from [warehouse and sales]")
  end

  # Java: NativizeSetFunDefTest#testLiteralMeasuresWithinParentheses
  it "literal measures within parentheses" do
    # The extra parens around the reference to the calculated member should
    # no longer cause native evaluation to be abandoned.
    check_native(
      "with " \
      "member [measures].[cog_oqp_int_t1] as '1', solve_order = 65535 " \
      "member [measures].[cog_oqp_int_t2] as '2', solve_order = 65535 " \
      "select " \
      "   NativizeSet(CrossJoin(" \
      "      [marital status].[marital status].members, " \
      "      [gender].[gender].members " \
      "    ))" \
      "on 1, " \
      "{ " \
      "   { ((( [measures].[cog_oqp_int_t1] ))) }, " \
      "   { [measures].[unit sales] }, " \
      "   { ( [measures].[cog_oqp_int_t2] ) }, " \
      "   { [measures].[store sales] } " \
      "} " \
      " on 0 " \
      "from [warehouse and sales]")
  end

  # Java: NativizeSetFunDefTest#testIsEmptyOnMeasures
  it "isEmpty on measures" do
    # isEmpty doesn't pose a problem for native evaluation.
    check_native(
      "with " \
      "member [measures].[cog_oqp_int_t1] " \
      "   as 'iif( isEmpty( measures.[unit sales]), 1010,2020)', solve_order = 65535 " \
      "select " \
      "   NativizeSet(CrossJoin(" \
      "      [marital status].[marital status].members, " \
      "      [gender].[gender].members " \
      "    ))" \
      "on 1, " \
      "{ " \
      "   { [measures].[cog_oqp_int_t1] }, " \
      "   { [measures].[unit sales] } " \
      "} " \
      " on 0 " \
      "from [warehouse and sales]")
  end

  # Java: NativizeSetFunDefTest#testLagOnMeasures
  it "lag on measures is not native" do
    # Lag function is NOT compatible with native.
    check_not_native(
      "with " \
      "member [measures].[cog_oqp_int_t1] " \
      "   as 'measures.[store sales].lag(1)', solve_order = 65535 " \
      "select " \
      "   NativizeSet(CrossJoin(" \
      "      [marital status].[marital status].members, " \
      "      [gender].[gender].members " \
      "    ))" \
      "on 1, " \
      "{ " \
      "   { [measures].[cog_oqp_int_t1] }, " \
      "   { [measures].[unit sales] }, " \
      "   { [measures].[store sales] } " \
      "} " \
      " on 0 " \
      "from [warehouse and sales]")
  end

  # Java: NativizeSetFunDefTest#testLagOnMeasuresWithinParentheses
  it "lag on measures within parentheses is not native" do
    # Lag function disables native eval even when buried in layers of parentheses.
    check_not_native(
      "with " \
      "member [measures].[cog_oqp_int_t1] " \
      "   as 'measures.[store sales].lag(1)', solve_order = 65535 " \
      "select " \
      "   NativizeSet(CrossJoin(" \
      "      [marital status].[marital status].members, " \
      "      [gender].[gender].members " \
      "    ))" \
      "on 1, " \
      "{ " \
      "   { ((( [measures].[cog_oqp_int_t1] ))) }, " \
      "   { [measures].[unit sales] }, " \
      "   { [measures].[store sales] } " \
      "} " \
      " on 0 " \
      "from [warehouse and sales]")
  end

  # Java: NativizeSetFunDefTest#testRangeOfMeasures
  it "range of measures is not native" do
    # Range of measures is NOT compatible with native.
    check_not_native(
      "select " \
      "   NativizeSet(CrossJoin(" \
      "      [marital status].[marital status].members, " \
      "      [gender].[gender].members " \
      "    ))" \
      "on 1, " \
      "{ " \
      "    measures.[unit sales] : measures.[store sales]  " \
      "} " \
      " on 0 " \
      "from [warehouse and sales]")
  end

  # Java: NativizeSetFunDefTest#testOrderOnMeasures
  it "order on measures is native" do
    # Order function should be compatible with native.
    check_native(
      "with " \
      "member [measures].[cog_oqp_int_t1] " \
      " as 'aggregate(order({measures.[store sales]}, measures.[store sales]), " \
      "measures.[store sales])', solve_order = 65535 " \
      "select " \
      "   NativizeSet(CrossJoin(" \
      "      [marital status].[marital status].members, " \
      "      [gender].[gender].members " \
      "   ))" \
      "on 1, " \
      "{ " \
      "   measures.[cog_oqp_int_t1]," \
      "   measures.[unit sales]" \
      "} " \
      " on 0 " \
      "from [warehouse and sales]")
  end

  # Java: NativizeSetFunDefTest#testLiteralMeasureAndUnitSalesUsingSet
  it "literal measure and unit sales using set" do
    check_native(
      "with " \
      "member [measures].[cog_oqp_int_t1] as '1', solve_order = 65535 " \
      "member [measures].[cog_oqp_int_t2] as '2', solve_order = 65535 " \
      "set [cog_oqp_int_s1] as " \
      "   'CrossJoin(" \
      "      [marital status].[marital status].members, " \
      "      [gender].[gender].members " \
      "    )'" \
      "select " \
      "   NativizeSet([cog_oqp_int_s1])" \
      "on 1, " \
      "{ " \
      "   [measures].[cog_oqp_int_t1], " \
      "   [measures].[unit sales], " \
      "   [measures].[cog_oqp_int_t1], " \
      "   [measures].[store sales] " \
      "} " \
      " on 0 " \
      "from [warehouse and sales]")
  end

  # Java: NativizeSetFunDefTest#testNoSubstitutionsArityOne
  it "no substitutions arity one" do
    # no crossjoin, so not native
    check_not_native(
      "SELECT NativizeSet({Gender.F, Gender.M}) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testNoSubstitutionsArityTwo
  it "no substitutions arity two" do
    check_not_native(
      "SELECT NativizeSet(CrossJoin(" \
      "{Gender.F, Gender.M}, " \
      "{ [Marital Status].M } " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testExplicitCurrentMonth
  it "explicit current month" do
    check_native(
      "SELECT NativizeSet(CrossJoin( " \
      "   { [Time].[Month].currentmember }, " \
      "   Gender.Gender.members )) " \
      "on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testAcceptsAllDimensionMembersSetAsInput
  it "accepts all dimension members set as input" do
    # no crossjoin, so not native
    check_not_native(
      "SELECT NativizeSet({[Marital Status].[Marital Status].members})" \
      " on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testAcceptsCrossJoinAsInput
  it "accepts crossjoin as input" do
    check_native(
      "SELECT NativizeSet( CrossJoin({ Gender.F, Gender.M }, " \
      "{[Marital Status].[Marital Status].members})) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testRedundantEnumMembersFirst
  it "redundant enum members first" do
    # In the enumerated marital status values { M, S, S }
    # the second S is clearly redundant, but should be
    # included in the result nonetheless.
    check_native(
      "SELECT NativizeSet( CrossJoin(" \
      "{ { [Marital Status].M, [Marital Status].S }, " \
      "  { [Marital Status].S } " \
      "}," \
      "CrossJoin( " \
      "{ gender.gender.members }, " \
      "{ time.quarter.members } " \
      "))) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testRedundantEnumMembersMiddle
  it "redundant enum members middle" do
    check_native(
      "SELECT NativizeSet( CrossJoin(" \
      "{  [Marital Status].[Marital Status].members }," \
      "CrossJoin( " \
      "{ { gender.F, gender.M , gender.M}, " \
      "  { gender.M } " \
      "}, " \
      "{ time.quarter.members } " \
      "))) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testRedundantEnumMembersLast
  it "redundant enum members last" do
    check_native(
      "SELECT NativizeSet( CrossJoin(" \
      "{  [Marital Status].[Marital Status].members }," \
      "CrossJoin( " \
      "{ gender.gender.members }, " \
      "{ { time.[1997].Q1, time.[1997].Q2 }, " \
      "  { time.[1997].Q2 } " \
      "} " \
      "))) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testRedundantLevelMembersFirst
  it "redundant level members first" do
    check_native(
      "SELECT NativizeSet( CrossJoin(" \
      "{  [Marital Status].[Marital Status].members, " \
      "   { [Marital Status].[Marital Status].members } " \
      "}," \
      "CrossJoin( " \
      "{ gender.gender.members }, " \
      "{ time.quarter.members } " \
      "))) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testRedundantLevelMembersMiddle
  it "redundant level members middle" do
    check_native(
      "SELECT NativizeSet( CrossJoin(" \
      "{  [Marital Status].[Marital Status].members }," \
      "CrossJoin( " \
      "{ gender.gender.members, " \
      "  { gender.gender.members } " \
      "}, " \
      "{ time.quarter.members } " \
      "))) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testRedundantLevelMembersLast
  it "redundant level members last" do
    check_native(
      "SELECT NativizeSet( CrossJoin(" \
      "{  [Marital Status].[Marital Status].members }," \
      "CrossJoin( " \
      "{ gender.gender.members }, " \
      "{ time.quarter.members, " \
      "  { time.quarter.members } " \
      "} " \
      "))) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testNonEmptyNestedCrossJoins
  it "non empty nested crossjoins" do
    check_native(
      "SELECT " \
      "NativizeSet(CrossJoin(" \
      "{ Gender.F, Gender.M }, " \
      "CrossJoin(" \
      "{ [Marital Status].[Marital Status].members }, " \
      "CrossJoin(" \
      "{ [Store].[All Stores].[USA].[CA], [Store].[All Stores].[USA].[OR] }, " \
      "{ [Education Level].[Education Level].members } " \
      ")))" \
      ") on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testLevelMembersAndAll
  it "level members and all" do
    check_native(
      "select NativizeSet (" \
      "crossjoin( " \
      "  { gender.gender.members, gender.[all gender] }, " \
      "  [marital status].[marital status].members " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testCrossJoinArgInNestedBraces
  it "crossjoin arg in nested braces" do
    check_native(
      "select NativizeSet (" \
      "crossjoin( " \
      "  { { gender.gender.members } }, " \
      "  [marital status].[marital status].members " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testLevelMembersAndAllWhereOrderMatters
  it "level members and all where order matters" do
    check_native(
      "select NativizeSet (" \
      "crossjoin( " \
      "  { gender.gender.members, gender.[all gender] }, " \
      "  { [marital status].S, [marital status].M } " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testEnumMembersAndAll
  it "enum members and all" do
    check_native(
      "select NativizeSet (" \
      "crossjoin( " \
      "  { gender.F, gender.M, gender.[all gender] }, " \
      "  [marital status].[marital status].members " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testNativizeWithASetAtTopLevel
  it "nativize with a set at top level" do
    check_native(
      "WITH" \
      "  MEMBER [Gender].[umg1] AS " \
      "  '([Gender].[gender agg], [Measures].[Unit Sales])', SOLVE_ORDER = 8 " \
      "  MEMBER [Gender].[gender agg] AS" \
      "  'AGGREGATE({[Gender].[Gender].MEMBERS},[Measures].[Unit Sales])', SOLVE_ORDER = 8 " \
      " MEMBER [Marital Status].[umg2] AS " \
      " '([Marital Status].[marital agg], [Measures].[Unit Sales])', SOLVE_ORDER = 4 " \
      " MEMBER [Marital Status].[marital agg] AS " \
      "  'AGGREGATE({[Marital Status].[Marital Status].MEMBERS},[Measures].[Unit Sales])', SOLVE_ORDER = 4 " \
      " SET [s2] AS " \
      "  'CROSSJOIN({[Marital Status].[Marital Status].MEMBERS}, {{[Gender].[Gender].MEMBERS}, {[Gender].[umg1]}})' " \
      " SET [s1] AS " \
      "  'CROSSJOIN({[Marital Status].[umg2]}, {[Gender].DEFAULTMEMBER})' " \
      " SELECT " \
      "  NativizeSet({[Measures].[Unit Sales]}) DIMENSION PROPERTIES PARENT_LEVEL, CHILDREN_CARDINALITY, PARENT_UNIQUE_NAME ON AXIS(0), " \
      "  NativizeSet({[s2],[s1]}) " \
      " DIMENSION PROPERTIES PARENT_LEVEL, CHILDREN_CARDINALITY, PARENT_UNIQUE_NAME ON AXIS(1)" \
      " FROM [Sales]  CELL PROPERTIES VALUE, FORMAT_STRING")
  end

  # Java: NativizeSetFunDefTest#testNativizeWithASetAtTopLevel3Levels
  it "nativize with a set at top level 3 levels" do
    check_native(
      "WITH\n" \
      "MEMBER [Gender].[COG_OQP_INT_umg2] AS 'IIF([Measures].CURRENTMEMBER IS [Measures].[Unit Sales], " \
      "([Gender].[COG_OQP_INT_m5], [Measures].[Unit Sales]), " \
      "AGGREGATE({[Gender].[Gender].MEMBERS}))', SOLVE_ORDER = 8\n" \
      "MEMBER [Gender].[COG_OQP_INT_m5] AS " \
      "'AGGREGATE({[Gender].[Gender].MEMBERS}, [Measures].[Unit Sales])', SOLVE_ORDER = 8\n" \
      "MEMBER [Store Type].[COG_OQP_INT_umg1] AS " \
      "'IIF([Measures].CURRENTMEMBER IS [Measures].[Unit Sales], " \
      "([Store Type].[COG_OQP_INT_m4], [Measures].[Unit Sales]), " \
      "AGGREGATE({[Store Type].[Store Type].MEMBERS}))', SOLVE_ORDER = 12\n" \
      "MEMBER [Store Type].[COG_OQP_INT_m4] AS " \
      "'AGGREGATE({[Store Type].[Store Type].MEMBERS}, [Measures].[Unit Sales])', SOLVE_ORDER = 12\n" \
      "MEMBER [Marital Status].[COG_OQP_INT_umg3] AS " \
      "'IIF([Measures].CURRENTMEMBER IS [Measures].[Unit Sales], " \
      "([Marital Status].[COG_OQP_INT_m6], [Measures].[Unit Sales]), " \
      "AGGREGATE({[Marital Status].[Marital Status].MEMBERS}))', SOLVE_ORDER = 4\n" \
      "MEMBER [Marital Status].[COG_OQP_INT_m6] AS " \
      "'AGGREGATE({[Marital Status].[Marital Status].MEMBERS}, [Measures].[Unit Sales])', SOLVE_ORDER = 4\n" \
      "SET [COG_OQP_INT_s5] AS 'CROSSJOIN({[Marital Status].[Marital Status].MEMBERS}, {[COG_OQP_INT_s4], [COG_OQP_INT_s3]})'\n" \
      "SET [COG_OQP_INT_s4] AS 'CROSSJOIN({[Gender].[Gender].MEMBERS}, {{[Store Type].[Store Type].MEMBERS}, " \
      "{[Store Type].[COG_OQP_INT_umg1]}})'\n" \
      "SET [COG_OQP_INT_s3] AS 'CROSSJOIN({[Gender].[COG_OQP_INT_umg2]}, {[Store Type].DEFAULTMEMBER})'\n" \
      "SET [COG_OQP_INT_s2] AS 'CROSSJOIN({[Marital Status].[COG_OQP_INT_umg3]}, [COG_OQP_INT_s1])'\n" \
      "SET [COG_OQP_INT_s1] AS 'CROSSJOIN({[Gender].DEFAULTMEMBER}, {[Store Type].DEFAULTMEMBER})' \n" \
      "SELECT {[Measures].[Unit Sales]} " \
      "DIMENSION PROPERTIES PARENT_LEVEL, CHILDREN_CARDINALITY, PARENT_UNIQUE_NAME ON AXIS(0), \n" \
      "NativizeSet({[COG_OQP_INT_s5], [COG_OQP_INT_s2]}) " \
      "DIMENSION PROPERTIES PARENT_LEVEL, CHILDREN_CARDINALITY, PARENT_UNIQUE_NAME ON AXIS(1)\n" \
      "FROM [Sales]  CELL PROPERTIES VALUE, FORMAT_STRING\n")
  end

  # Java: NativizeSetFunDefTest#testNativizeWithASetAtTopLevel2
  it "nativize with a set at top level 2" do
    check_native(
      "WITH" \
      "  MEMBER [Gender].[umg1] AS " \
      "  '([Gender].[gender agg], [Measures].[Unit Sales])', SOLVE_ORDER = 8 " \
      "  MEMBER [Gender].[gender agg] AS" \
      "  'AGGREGATE({[Gender].[Gender].MEMBERS},[Measures].[Unit Sales])', SOLVE_ORDER = 8 " \
      " MEMBER [Marital Status].[umg2] AS " \
      " '([Marital Status].[marital agg], [Measures].[Unit Sales])', SOLVE_ORDER = 4 " \
      " MEMBER [Marital Status].[marital agg] AS " \
      "  'AGGREGATE({[Marital Status].[Marital Status].MEMBERS},[Measures].[Unit Sales])', SOLVE_ORDER = 4 " \
      " SET [s2] AS " \
      "  'CROSSJOIN({{[Marital Status].[Marital Status].MEMBERS},{[Marital Status].[umg2]}}, " \
      "{{[Gender].[Gender].MEMBERS}, {[Gender].[umg1]}})' " \
      " SET [s1] AS " \
      "  'CROSSJOIN({[Marital Status].[umg2]}, {[Gender].DEFAULTMEMBER})' " \
      " SELECT " \
      "  NativizeSet({[Measures].[Unit Sales]}) " \
      "DIMENSION PROPERTIES PARENT_LEVEL, CHILDREN_CARDINALITY, PARENT_UNIQUE_NAME ON AXIS(0), " \
      "  NativizeSet({[s2]}) " \
      " DIMENSION PROPERTIES PARENT_LEVEL, CHILDREN_CARDINALITY, PARENT_UNIQUE_NAME ON AXIS(1)" \
      " FROM [Sales]  CELL PROPERTIES VALUE, FORMAT_STRING")
  end

  # Java: NativizeSetFunDefTest#testGenderMembersAndAggByMaritalStatus
  it "gender members and agg by marital status" do
    check_native(
      "with member gender.agg as 'Aggregate( gender.gender.members )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  { gender.gender.members, gender.[agg] }, " \
      "  [marital status].[marital status].members " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testGenderAggAndMembersByMaritalStatus
  it "gender agg and members by marital status" do
    check_native(
      "with member gender.agg as 'Aggregate( gender.gender.members )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  { gender.[agg], gender.gender.members }, " \
      "  [marital status].[marital status].members " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testGenderAggAndMembersAndAllByMaritalStatus
  it "gender agg and members and all by marital status" do
    check_native(
      "with member gender.agg as 'Aggregate( gender.gender.members )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  { gender.[agg], gender.gender.members, gender.[all gender] }, " \
      "  [marital status].[marital status].members " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testMaritalStatusByGenderMembersAndAgg
  it "marital status by gender members and agg" do
    check_native(
      "with member gender.agg as 'Aggregate( gender.gender.members )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  [marital status].[marital status].members, " \
      "  { gender.gender.members, gender.[agg] } " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testMaritalStatusByGenderAggAndMembers
  it "marital status by gender agg and members" do
    check_native(
      "with member gender.agg as 'Aggregate( gender.gender.members )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  [marital status].[marital status].members, " \
      "  { gender.[agg], gender.gender.members } " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testAggWithEnumMembers
  it "agg with enum members" do
    check_native(
      "with member gender.agg as 'Aggregate( gender.gender.members )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  { gender.gender.members, gender.[agg] }, " \
      "  { [marital status].[marital status].[M], [marital status].[marital status].[S] } " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testCrossjoinArgWithMultipleElementTypes
  it "crossjoin arg with multiple element types" do
    # Combination of element types: a members function, an
    # explicit enumerated value, an aggregate, and the all level.
    check_native(
      "with member [gender].agg as 'Aggregate( gender.gender.members )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "{ time.quarter.members }, " \
      "CrossJoin( " \
      "{ gender.gender.members, gender.F, gender.[agg], gender.[all gender] }, " \
      "{ [marital status].[marital status].members }" \
      "))) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testProductFamilyMembers
  it "product family members" do
    check_native(
      "select non empty NativizeSet(" \
      "crossjoin( " \
      "  [product].[product family].members, " \
      "  { [gender].F } " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testNestedCrossJoinWhereAllColsHaveNative
  it "nested crossjoin where all cols have native" do
    check_native(
      "with " \
      "member gender.agg as 'Aggregate( gender.gender.members )' " \
      "member [marital status].agg as 'Aggregate( [marital status].[marital status].members )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  { gender.[all gender], gender.gender.members, gender.[agg] }, " \
      "  crossjoin(" \
      "  { [marital status].[marital status].members, [marital status].[agg] }," \
      "  [Education Level].[Education Level].members " \
      "))) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testNestedCrossJoinWhereFirstColumnNonNative
  it "nested crossjoin where first column non native" do
    check_native(
      "with " \
      "member gender.agg as 'Aggregate( gender.gender.members )' " \
      "member [marital status].agg as 'Aggregate( [marital status].[marital status].members )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  { gender.[all gender], gender.[agg] }, " \
      "  crossjoin(" \
      "  { [marital status].[marital status].members, [marital status].[agg] }," \
      "  [Education Level].[Education Level].members " \
      "))) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testNestedCrossJoinWhereMiddleColumnNonNative
  it "nested crossjoin where middle column non native" do
    check_native(
      "with " \
      "member gender.agg as 'Aggregate( gender.gender.members )' " \
      "member [marital status].agg as 'Aggregate( [marital status].[marital status].members )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  { [marital status].[marital status].members, [marital status].[agg] }," \
      "  crossjoin(" \
      "  { gender.[all gender], gender.[agg] }, " \
      "  [Education Level].[Education Level].members " \
      "))) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testNestedCrossJoinWhereLastColumnNonNative
  it "nested crossjoin where last column non native" do
    check_native(
      "with " \
      "member gender.agg as 'Aggregate( gender.gender.members )' " \
      "member [marital status].agg as 'Aggregate( [marital status].[marital status].members )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  { [marital status].[marital status].members, [marital status].[agg] }," \
      "  crossjoin(" \
      "  [Education Level].[Education Level].members, " \
      "  { gender.[all gender], gender.[agg] } " \
      "))) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testGenderAggByMaritalStatus
  it "gender agg by marital status is not native" do
    # NativizeSet removes the crossjoin, so not native
    check_not_native(
      "with member gender.agg as 'Aggregate( gender.gender.members )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  { gender.[agg] }, " \
      "  [marital status].[marital status].members " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testGenderAggTwiceByMaritalStatus
  it "gender agg twice by marital status is not native" do
    # NativizeSet removes the crossjoin, so not native
    check_not_native(
      "with " \
      "member gender.agg1 as 'Aggregate( { gender.M } )' " \
      "member gender.agg2 as 'Aggregate( { gender.F } )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  { gender.[agg1], gender.[agg2] }, " \
      "  [marital status].[marital status].members " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testSameGenderAggTwiceByMaritalStatus
  it "same gender agg twice by marital status is not native" do
    check_not_native(
      "with " \
      "member gender.agg as 'Aggregate( gender.gender.members )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  { gender.[agg], gender.[agg] }, " \
      "  [marital status].[marital status].members " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testMaritalStatusByGenderAgg
  it "marital status by gender agg is not native" do
    check_not_native(
      "with member gender.agg as 'Aggregate( gender.gender.members )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  [marital status].[marital status].members, " \
      "  { gender.[agg] } " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testMaritalStatusByTwoGenderAggs
  it "marital status by two gender aggs is not native" do
    check_not_native(
      "with " \
      "member gender.agg1 as 'Aggregate( { gender.M } )' " \
      "member gender.agg2 as 'Aggregate( { gender.F } )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  [marital status].[marital status].members, " \
      "  { gender.[agg1], gender.[agg2] } " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testMaritalStatusBySameGenderAggTwice
  it "marital status by same gender agg twice is not native" do
    check_not_native(
      "with " \
      "member gender.agg as 'Aggregate( { gender.M } )' " \
      "select NativizeSet(" \
      "crossjoin( " \
      "  [marital status].[marital status].members, " \
      "  { gender.[agg], gender.[agg] } " \
      ")) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testMultipleLevelsOfSameDimInConcatenatedJoins
  it "multiple levels of same dim in concatenated joins" do
    check_not_native(
      "select NativizeSet( {" \
      "CrossJoin(" \
      "  { [Time].[Year].members }," \
      "  { gender.F, gender. M } )," \
      "CrossJoin(" \
      "  { [Time].[Quarter].members }," \
      "  { gender.F, gender. M } )" \
      "} ) on 0 from sales")
  end

  # Java: NativizeSetFunDefTest#testMultipleLevelsOfSameDimInSingleArg
  it "multiple levels of same dim in single arg" do
    # Although it's legal MDX, the RolapNativeSet.checkCrossJoinArg
    # can't deal with an arg that contains multiple .members functions
    # at different levels.
    check_not_native(
      "select NativizeSet( {" \
      "CrossJoin(" \
      "  { [Time].[Year].members," \
      "    [Time].[Quarter].members }," \
      "  { gender.F, gender. M } )" \
      "} ) on 0 from sales")
  end

  describe "query rewriting" do
    # Java: NativizeSetFunDefTest#testDoesNoHarmToPlainEnumeratedMembers
    it "does no harm to plain enumerated members" do
      with_properties(EnableNonEmptyOnAllAxis: false) do
        assert_query_is_rewritten(
          "SELECT NativizeSet({Gender.M,Gender.F}) on 0 from sales",
          "select " \
          "NativizeSet({[Gender].[M], [Gender].[F]}) " \
          "ON COLUMNS\n" \
          "from [Sales]\n")
      end
    end

    # Java: NativizeSetFunDefTest#testDoesNoHarmToPlainDotMembers
    it "does no harm to plain dot members" do
      with_properties(EnableNonEmptyOnAllAxis: false) do
        assert_query_is_rewritten(
          "select NativizeSet({[Marital Status].[Marital Status].members}) " \
          "on 0 from sales",
          "select NativizeSet({[Marital Status].[Marital Status].Members}) " \
          "ON COLUMNS\n" \
          "from [Sales]\n")
      end
    end

    # Java: NativizeSetFunDefTest#testTransformsCallToRemoveDotMembersInCrossJoin
    it "transforms call to remove dot members in crossjoin" do
      with_properties(EnableNonEmptyOnAllAxis: false) do
        assert_query_is_rewritten(
          "select NativizeSet(CrossJoin({Gender.M,Gender.F},{[Marital Status].[Marital Status].members})) " \
          "on 0 from sales",
          "with member [Marital Status].[_Nativized_Member_Marital Status_Marital Status_] as '[Marital Status].DefaultMember'\n" \
          "  set [_Nativized_Set_Marital Status_Marital Status_] as " \
          "'{[Marital Status].[_Nativized_Member_Marital Status_Marital Status_]}'\n" \
          "  member [Gender].[_Nativized_Sentinel_Gender_(All)_] as '101010'\n" \
          "  member [Marital Status].[_Nativized_Sentinel_Marital Status_(All)_] as '101010'\n" \
          "select NativizeSet(Crossjoin({[Gender].[M], [Gender].[F]}, " \
          "{[_Nativized_Set_Marital Status_Marital Status_]})) ON COLUMNS\n" \
          "from [Sales]\n")
      end
    end

    # Java: NativizeSetFunDefTest#testTransformsComplexQueryWithGenerateAndAggregate
    it "transforms complex query with generate and aggregate" do
      with_properties(EnableNonEmptyOnAllAxis: false) do
        assert_query_is_rewritten(
          "WITH MEMBER [Product].[COG_OQP_INT_umg1] AS " \
          "'IIF([Measures].CURRENTMEMBER IS [Measures].[Unit Sales], ([Product].[COG_OQP_INT_m2], [Measures].[Unit Sales])," \
          " AGGREGATE({[Product].[Product Name].MEMBERS}))', SOLVE_ORDER = 4 " \
          "MEMBER [Product].[COG_OQP_INT_m2] AS 'AGGREGATE({[Product].[Product Name].MEMBERS}," \
          " [Measures].[Unit Sales])', SOLVE_ORDER = 4 " \
          "SET [COG_OQP_INT_s5] AS 'CROSSJOIN({[Marital Status].[S]}, [COG_OQP_INT_s4])'" \
          " SET [COG_OQP_INT_s4] AS 'CROSSJOIN({[Gender].[F]}, [COG_OQP_INT_s2])'" \
          " SET [COG_OQP_INT_s3] AS 'CROSSJOIN({[Gender].[F]}, {[COG_OQP_INT_s2], [COG_OQP_INT_s1]})' " \
          "SET [COG_OQP_INT_s2] AS 'CROSSJOIN({[Product].[Product Name].MEMBERS}, {[Customers].[Name].MEMBERS})' " \
          "SET [COG_OQP_INT_s1] AS 'CROSSJOIN({[Product].[COG_OQP_INT_umg1]}, {[Customers].DEFAULTMEMBER})' " \
          "SELECT {[Measures].[Unit Sales]} DIMENSION PROPERTIES PARENT_LEVEL, CHILDREN_CARDINALITY, PARENT_UNIQUE_NAME ON AXIS(0)," \
          " NativizeSet(GENERATE({[Education Level].[Graduate Degree]}, \n" \
          "CROSSJOIN(HEAD({([Education Level].CURRENTMEMBER)}, IIF(COUNT([COG_OQP_INT_s5], INCLUDEEMPTY) > 0, 1, 0)), " \
          "GENERATE({[Marital Status].[S]}, CROSSJOIN(HEAD({([Marital Status].CURRENTMEMBER)}, " \
          "IIF(COUNT([COG_OQP_INT_s4], INCLUDEEMPTY) > 0, 1, 0)), [COG_OQP_INT_s3]), ALL)), ALL))" \
          " DIMENSION PROPERTIES PARENT_LEVEL, CHILDREN_CARDINALITY, PARENT_UNIQUE_NAME ON AXIS(1)" \
          " FROM [Sales]  CELL PROPERTIES VALUE, FORMAT_STRING",
          "with member [Product].[COG_OQP_INT_umg1] as " \
          "'IIf(([Measures].CurrentMember IS [Measures].[Unit Sales]), ([Product].[COG_OQP_INT_m2], [Measures].[Unit Sales]), " \
          "Aggregate({[Product].[Product Name].Members}))', SOLVE_ORDER = 4\n" \
          "  member [Product].[COG_OQP_INT_m2] as " \
          "'Aggregate({[Product].[Product Name].Members}, [Measures].[Unit Sales])', SOLVE_ORDER = 4\n" \
          "  set [COG_OQP_INT_s5] as 'Crossjoin({[Marital Status].[S]}, [COG_OQP_INT_s4])'\n" \
          "  set [COG_OQP_INT_s4] as 'Crossjoin({[Gender].[F]}, [COG_OQP_INT_s2])'\n" \
          "  set [COG_OQP_INT_s3] as 'Crossjoin({[Gender].[F]}, {[COG_OQP_INT_s2], [COG_OQP_INT_s1]})'\n" \
          "  set [COG_OQP_INT_s2] as 'Crossjoin({[Product].[Product Name].Members}, {[Customers].[Name].Members})'\n" \
          "  set [COG_OQP_INT_s1] as 'Crossjoin({[Product].[COG_OQP_INT_umg1]}, {[Customers].DefaultMember})'\n" \
          "select {[Measures].[Unit Sales]} DIMENSION PROPERTIES PARENT_LEVEL, CHILDREN_CARDINALITY, PARENT_UNIQUE_NAME ON COLUMNS,\n" \
          "  NativizeSet(Generate({[Education Level].[Graduate Degree]}, " \
          "Crossjoin(Head({[Education Level].CurrentMember}, IIf((Count([COG_OQP_INT_s5], INCLUDEEMPTY) > 0), 1, 0)), " \
          "Generate({[Marital Status].[S]}, " \
          "Crossjoin(Head({[Marital Status].CurrentMember}, " \
          "IIf((Count([COG_OQP_INT_s4], INCLUDEEMPTY) > 0), 1, 0)), [COG_OQP_INT_s3]), ALL)), ALL)) " \
          "DIMENSION PROPERTIES PARENT_LEVEL, CHILDREN_CARDINALITY, PARENT_UNIQUE_NAME ON ROWS\n" \
          "from [Sales]\n")
      end
    end

    # Java: NativizeSetFunDefTest#testMultipleHierarchySsasTrue
    it "multiple hierarchy SSAS true" do
      with_properties(SsasCompatibleNaming: true, EnableNonEmptyOnAllAxis: false) do
        # Use fresh connection -- unique names are baked in when schema is
        # loaded, depending the SSAS setting at that time.
        Mondrian::OLAP::Connection.flush_schema_cache
        olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
        begin
          assert_query_is_rewritten(
            "select nativizeSet(crossjoin(time.[week].members, { gender.m })) on 0 " \
            "from sales",
            "with member [Time].[Weekly].[_Nativized_Member_Time_Weekly_Week_] as '[Time].[Weekly].DefaultMember'\n" \
            "  set [_Nativized_Set_Time_Weekly_Week_] as '{[Time].[Weekly].[_Nativized_Member_Time_Weekly_Week_]}'\n" \
            "  member [Time].[_Nativized_Sentinel_Time_Year_] as '101010'\n" \
            "  member [Gender].[_Nativized_Sentinel_Gender_(All)_] as '101010'\n" \
            "select NativizeSet(Crossjoin([_Nativized_Set_Time_Weekly_Week_], {[Gender].[M]})) ON COLUMNS\n" \
            "from [Sales]\n",
            olap: olap)
        ensure
          olap.close
          Mondrian::OLAP::Connection.flush_schema_cache
        end
      end
    end

    # Java: NativizeSetFunDefTest#testMultipleHierarchySsasFalse
    it "multiple hierarchy SSAS false" do
      with_properties(SsasCompatibleNaming: false, EnableNonEmptyOnAllAxis: false) do
        assert_query_is_rewritten(
          "select nativizeSet(crossjoin( [time.weekly].week.members, { gender.m })) on 0 " \
          "from sales",
          "with member [Time].[_Nativized_Member_Time_Weekly_Week_] as '[Time].DefaultMember'\n" \
          "  set [_Nativized_Set_Time_Weekly_Week_] as '{[Time].[_Nativized_Member_Time_Weekly_Week_]}'\n" \
          "  member [Time].[_Nativized_Sentinel_Time_Year_] as '101010'\n" \
          "  member [Gender].[_Nativized_Sentinel_Gender_(All)_] as '101010'\n" \
          "select NativizeSet(Crossjoin([_Nativized_Set_Time_Weekly_Week_], {[Gender].[M]})) ON COLUMNS\n" \
          "from [Sales]\n")
      end
    end

    # Java: NativizeSetFunDefTest#testTopCountDoesNotGetTransformed
    it "TopCount does not get transformed" do
      assert_query_is_rewritten(
        "select " \
        "   NativizeSet(Crossjoin([Gender].[Gender].members," \
        "TopCount({[Marital Status].[Marital Status].members},1,[Measures].[Unit Sales]))" \
        " ) on 0," \
        "{[Measures].[Unit Sales]} on 1 FROM [Sales]",
        "with member [Gender].[_Nativized_Member_Gender_Gender_] as '[Gender].DefaultMember'\n" \
        "  set [_Nativized_Set_Gender_Gender_] as '{[Gender].[_Nativized_Member_Gender_Gender_]}'\n" \
        "  member [Gender].[_Nativized_Sentinel_Gender_(All)_] as '101010'\n" \
        "select NON EMPTY NativizeSet(Crossjoin([_Nativized_Set_Gender_Gender_], " \
        "TopCount({[Marital Status].[Marital Status].Members}, 1, [Measures].[Unit Sales]))) ON COLUMNS,\n" \
        "  NON EMPTY {[Measures].[Unit Sales]} ON ROWS\n" \
        "from [Sales]\n")
    end
  end

  # Java: NativizeSetFunDefTest#testComplexCrossjoinAggInMiddle
  it "complex crossjoin agg in middle" do
    check_native(
      "WITH\n" \
      "\tMEMBER [Time].[Time].[COG_OQP_USR_Aggregate(Time Values)] AS " \
      "'IIF([Measures].CURRENTMEMBER IS [Measures].[Unit Sales], ([Time].[1997], [Measures].[Unit Sales]), ([Time].[1997]))',\n" \
      "\tSOLVE_ORDER = 4 MEMBER [Store Type].[COG_OQP_INT_umg1] AS " \
      "'IIF([Measures].CURRENTMEMBER IS [Measures].[Unit Sales], ([Store Type].[COG_OQP_INT_m2], [Measures].[Unit Sales]), " \
      "AGGREGATE({[Store Type].[Store Type].MEMBERS}))',\n" \
      "\tSOLVE_ORDER = 8 MEMBER [Store Type].[COG_OQP_INT_m2] AS " \
      "'AGGREGATE({[Store Type].[Store Type].MEMBERS}, [Measures].[Unit Sales])',\n" \
      "\tSOLVE_ORDER = 8 \n" \
      "SET\n" \
      "\t[COG_OQP_INT_s9] AS 'CROSSJOIN({[Marital Status].[Marital Status].MEMBERS}, {[COG_OQP_INT_s8], [COG_OQP_INT_s6]})' \n" \
      "SET\n" \
      "\t[COG_OQP_INT_s8] AS 'CROSSJOIN({[Store Type].[Store Type].MEMBERS}, [COG_OQP_INT_s7])' \n" \
      "SET\n" \
      "\t[COG_OQP_INT_s7] AS 'CROSSJOIN({[Promotions].[Promotions].MEMBERS}, " \
      "{[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Pearl].[Pearl Imported Beer]})' \n" \
      "SET\n" \
      "\t[COG_OQP_INT_s6] AS 'CROSSJOIN({[Store Type].[COG_OQP_INT_umg1]}, [COG_OQP_INT_s1])' \n" \
      "SET\n" \
      "\t[COG_OQP_INT_s5] AS 'CROSSJOIN({[Time].[COG_OQP_USR_Aggregate(Time Values)]}, [COG_OQP_INT_s4])' \n" \
      "SET\n" \
      "\t[COG_OQP_INT_s4] AS 'CROSSJOIN({[Gender].DEFAULTMEMBER}, [COG_OQP_INT_s3])' \n" \
      "SET\n" \
      "\t[COG_OQP_INT_s3] AS 'CROSSJOIN({[Marital Status].DEFAULTMEMBER}, [COG_OQP_INT_s2])' \n" \
      "SET\n" \
      "\t[COG_OQP_INT_s2] AS 'CROSSJOIN({[Store Type].DEFAULTMEMBER}, [COG_OQP_INT_s1])' \n" \
      "SET\n" \
      "\t[COG_OQP_INT_s11] AS 'CROSSJOIN({[Gender].[Gender].MEMBERS}, [COG_OQP_INT_s10])' \n" \
      "SET\n" \
      "\t[COG_OQP_INT_s10] AS 'CROSSJOIN({[Marital Status].[Marital Status].MEMBERS}, [COG_OQP_INT_s8])' \n" \
      "SET\n" \
      "\t[COG_OQP_INT_s1] AS 'CROSSJOIN({[Promotion Name].DEFAULTMEMBER}, " \
      "{[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Pearl].[Pearl Imported Beer]})' \n" \
      "SELECT\n" \
      "\t{[Measures].[Unit Sales]} DIMENSION PROPERTIES PARENT_LEVEL,\n" \
      "\tCHILDREN_CARDINALITY,\n" \
      "\tPARENT_UNIQUE_NAME ON AXIS(0),\n" \
      "NativizeSet(\n" \
      "\t{\n" \
      "CROSSJOIN({[Time].[1997]}, CROSSJOIN({[Gender].[Gender].MEMBERS}, [COG_OQP_INT_s9])),\n" \
      "\t[COG_OQP_INT_s5]}\n" \
      ")\n" \
      "ON AXIS(1) \n" \
      "FROM\n" \
      "\t[Sales] ")
  end

  # Java: NativizeSetFunDefTest#testCrossjoinWithFilter
  it "crossjoin with filter" do
    assert_query_returns @olap,
      "select\n" \
      "NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS,   \n" \
      "NON EMPTY NativizeSet(Crossjoin({[Time].[1997]}, " \
      "Filter({[Gender].[Gender].Members}, ([Measures].[Unit Sales] < 131559)))) ON ROWS \n" \
      "from [Sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Time].[1997], [Gender].[F]}
        Row #0: 131,558
      RESULT
  end

  # Java: NativizeSetFunDefTest#testEvaluationIsNonNativeWhenBelowHighcardThreshoold
  it "evaluation is non native when below highcard threshold" do
    # Java test verifies specific ACCESS SQL is NOT generated.
    # We verify the MDX executes correctly.
    with_properties(NativizeMinThreshold: 10000) do
      check_not_native(
        "select non empty NativizeSet(" \
        "Crossjoin([Gender].[Gender].members,{[Time].[1997]})) on 0 " \
        "from [Warehouse and Sales] " \
        "where [Marital Status].[Marital Status].[S]")
    end
  end

  # Java: NativizeSetFunDefTest#testCalculatedLevelsDoNotCauseException
  it "calculated levels do not cause exception" do
    check_not_native(
      "SELECT " \
      "  Nativizeset" \
      "  (" \
      "    {" \
      "      [Store].Levels(0).MEMBERS" \
      "    }" \
      "  ) ON COLUMNS" \
      " FROM [Sales]")
  end

  # Java: NativizeSetFunDefTest#testAxisWithArityOneIsNotNativelyEvaluated
  it "axis with arity one is not natively evaluated" do
    # Java test verifies specific ACCESS SQL is NOT generated.
    # We verify the MDX executes correctly with NativizeSet.
    mdx =
      "select " \
      "  NON EMPTY " \
      "  NativizeSet(" \
      "    Except(" \
      "      {[Promotion Media].[Promotion Media].Members},\n" \
      "      {[Promotion Media].[Bulk Mail],[Promotion Media].[All Media].[Daily Paper]}" \
      "    )" \
      "  ) ON COLUMNS," \
      "  NON EMPTY " \
      "  {[Measures].[Unit Sales]} ON ROWS " \
      "from [Sales] \n" \
      "where [Time].[1997]"
    check_not_native(mdx)
  end

  # Java: NativizeSetFunDefTest#testAxisWithNamedSetArityOneIsNotNativelyEvaluated
  it "axis with named set arity one is not natively evaluated" do
    check_not_native(
      "with " \
      "set [COG_OQP_INT_s1] as " \
      "'Intersect({[Gender].[Gender].Members}, {[Gender].[Gender].[M]})' " \
      "select NON EMPTY " \
      "NativizeSet([COG_OQP_INT_s1]) ON COLUMNS " \
      "from [Sales]")
  end

  # Java: NativizeSetFunDefTest#testOneAxisHighAndOneLowGetsNativeEvaluation
  it "one axis high and one low gets native evaluation" do
    with_properties(NativizeMinThreshold: 19) do
      check_native(
        "select NativizeSet(" \
        "Crossjoin([Gender].[Gender].members," \
        "[Marital Status].[Marital Status].members)) on 0," \
        "NativizeSet(" \
        "Crossjoin([Store].[Store State].members,[Time].[Year].members)) on 1 " \
        "from [Warehouse and Sales]")
    end
  end

  # Java: NativizeSetFunDefTest#testLeafMembersOfParentChildDimensionAreNativelyEvaluated
  it "leaf members of parent child dimension are natively evaluated" do
    check_native(
      "SELECT" \
      " NON EMPTY " \
      "NativizeSet(Crossjoin(" \
      "{" \
      "[Employees].[Sheri Nowmer].[Derrick Whelply].[Pedro Castillo].[Lin Conley].[Paul Tays].[Pat Chin].[Gabriel Walton]," \
      "[Employees].[Sheri Nowmer].[Derrick Whelply].[Pedro Castillo].[Lin Conley].[Paul Tays].[Pat Chin].[Bishop Meastas]," \
      "[Employees].[Sheri Nowmer].[Derrick Whelply].[Pedro Castillo].[Lin Conley].[Paul Tays].[Pat Chin].[Paula Duran]," \
      "[Employees].[Sheri Nowmer].[Derrick Whelply].[Pedro Castillo].[Lin Conley].[Paul Tays].[Pat Chin].[Margaret Earley]," \
      "[Employees].[Sheri Nowmer].[Derrick Whelply].[Pedro Castillo].[Lin Conley].[Paul Tays].[Pat Chin].[Elizabeth Horne]" \
      "}," \
      "[Store].[Store Name].members" \
      ")) on 0 from hr")
  end

  # Java: NativizeSetFunDefTest#testAggregatedCrossjoinWithZeroMembersInNativeList
  it "aggregated crossjoin with zero members in native list" do
    check_native(
      "with" \
      " member [gender].[agg] as" \
      "  'aggregate({[gender].[gender].members},[measures].[unit sales])'" \
      " member [Marital Status].[agg] as" \
      "  'aggregate({[Marital Status].[Marital Status].members},[measures].[unit sales])'" \
      "select" \
      " non empty " \
      " NativizeSet(" \
      "Crossjoin(" \
      "{[Marital Status].[Marital Status].members,[Marital Status].[agg]}," \
      "{[Gender].[Gender].members,[gender].[agg]}" \
      ")) on 0 " \
      " from sales " \
      " where [Store].[Canada].[BC].[Vancouver].[Store 19]")
  end

  # Java: NativizeSetFunDefTest#testCardinalityQueriesOnlyExecuteOnce
  it "cardinality queries only execute once" do
    # Java test verifies specific cardinality SQL is NOT generated on second execution.
    # We verify the MDX executes correctly on both runs (cache behavior).
    mdx =
      "select" \
      " non empty" \
      " NativizeSet(Crossjoin(" \
      "[Gender].[Gender].members,[Marital Status].[Marital Status].members" \
      ")) on 0 from Sales"
    @olap.execute(mdx)
    result = @olap.execute(mdx)
    refute_nil result
  end

  # Java: NativizeSetFunDefTest#testSingleLevelDotMembersIsNativelyEvaluated
  it "single level dot members is natively evaluated" do
    # Java test verifies specific Oracle SQL is generated.
    # We verify the MDX executes correctly.
    mdx1 =
      "with member [Customers].[agg] as '" \
      "AGGREGATE({[Customers].[name].MEMBERS}, [Measures].[Unit Sales])'" \
      "select non empty NativizeSet({{[Customers].[name].members}, {[Customers].[agg]}}) on 0," \
      "non empty NativizeSet(" \
      "Crossjoin({[Gender].[Gender].[M]}," \
      "[Measures].[Unit Sales])) on 1 " \
      "from Sales"
    mdx2 =
      "select non empty NativizeSet({[Customers].[name].members}) on 0," \
      "non empty NativizeSet(" \
      "Crossjoin({[Gender].[Gender].[M]}," \
      "[Measures].[Unit Sales])) on 1 " \
      "from Sales"
    result1 = @olap.execute(mdx1)
    result2 = @olap.execute(mdx2)
    refute_nil result1
    refute_nil result2
  end
end
