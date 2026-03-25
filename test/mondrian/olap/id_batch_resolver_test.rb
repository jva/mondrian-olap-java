# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2006-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"
require "set"

# Recording InvocationHandler that tracks lookupMemberChildrenByNames calls
# on a SchemaReader proxy, delegating all other calls to the original reader.
class IdBatchRecordingHandler
  include java.lang.reflect.InvocationHandler

  def initialize(delegate, lookup_calls)
    @delegate = delegate
    @lookup_calls = lookup_calls
  end

  def invoke(_proxy, method, args)
    if method.getName == "lookupMemberChildrenByNames"
      args_array = args.to_a
      @lookup_calls << {
        parent: args_array[0],
        children: java.util.ArrayList.new(args_array[1]),
        match_type: args_array[2]
      }
    end

    if args
      method.invoke(@delegate, *args.to_a)
    else
      method.invoke(@delegate)
    end
  rescue java.lang.reflect.InvocationTargetException => e
    raise e.cause
  end
end

# Query subclass that defers full resolution (only creates formula elements)
# and wraps its SchemaReader with a recording proxy to track batch lookups.
class IdBatchQueryTestWrapper < Java::MondrianOlap::Query
  attr_reader :lookup_calls

  def initialize(statement, formulas, axes, cube_name, slicer_axis, cell_props, strict_validation)
    @lookup_calls = []
    cube = Java::MondrianOlap::Util.lookupCube(statement.getSchemaReader, cube_name, true)
    super(statement, cube, formulas, axes, slicer_axis, cell_props,
          [].to_java(Java::MondrianOlap::Parameter), strict_validation)
  end

  # Deferred resolution: only create formula elements, skip full resolve.
  # This allows IdBatchResolver to perform the batch resolution instead.
  def resolve
    formulas = getFormulas
    return unless formulas
    formulas.each { |formula| formula.createElement(self) }
  end

  def getSchemaReader(access_controlled)
    unless @recording_reader
      original = super
      handler = IdBatchRecordingHandler.new(original, @lookup_calls)
      @recording_reader = java.lang.reflect.Proxy.newProxyInstance(
        original.getClass.getClassLoader,
        IdBatchQueryTestWrapper.collect_all_interfaces(original),
        handler
      )
    end
    @recording_reader
  end

  # Collect all interfaces from the entire class hierarchy so the proxy
  # can be coerced to any interface the original object implements.
  def self.collect_all_interfaces(java_object)
    interfaces = java.util.LinkedHashSet.new
    cls = java_object.getClass
    while cls
      cls.getInterfaces.each { |iface| add_interface_tree(iface, interfaces) }
      cls = cls.getSuperclass
    end
    interfaces.toArray(java.lang.Class[interfaces.size].new)
  end

  def self.add_interface_tree(iface, set)
    return unless set.add(iface)
    iface.getInterfaces.each { |parent| add_interface_tree(parent, set) }
  end
end

# Parser factory that creates IdBatchQueryTestWrapper instead of regular Query.
class IdBatchFactoryImplTestWrapper < Java::MondrianOlap::Parser::FactoryImpl
  def makeQuery(statement, formulae, axes, cube, slicer, cell_props, strict_validation)
    slicer_axis = if slicer
      Java::MondrianOlap::QueryAxis.new(
        false, slicer,
        Java::MondrianOlap::AxisOrdinal::StandardAxisOrdinal::SLICER,
        Java::MondrianOlap::QueryAxis::SubtotalVisibility::Undefined,
        [].to_java(Java::MondrianOlap::Id)
      )
    end
    IdBatchQueryTestWrapper.new(
      statement, formulae, axes, cube, slicer_axis, cell_props, strict_validation
    )
  end
end

# Java: mondrian/olap/IdBatchResolverTest.java
describe "IdBatchResolver" do
  before(:all) do
    create_olap_connection
  end

  def batch_resolve(mdx, olap: @olap)
    connection = olap.raw_mondrian_connection
    statement = connection.getInternalStatement

    factory = IdBatchFactoryImplTestWrapper.new
    parser = Java::MondrianParser::JavaccParserValidatorImpl.new(factory)
    fun_table = Java::MondrianOlapFun::BuiltinFunTable.instance
    query = parser.parseInternal(statement, mdx, false, fun_table, false)
    @last_query = query

    execution = Java::MondrianServer::Execution.new(
      query.getStatement, java.lang.Integer::MAX_VALUE
    )
    locus = Java::MondrianServer::Locus.new(
      execution, "batchResolveTest", "batchResolveTest"
    )
    Java::MondrianServer::Locus.push(locus)

    begin
      resolver = Java::MondrianOlap::IdBatchResolver.new(query)
      resolve_map = resolver.resolve
    ensure
      Java::MondrianServer::Locus.pop(locus)
    end

    resolve_map.keySet.map(&:to_s).to_set
  ensure
    statement&.close
  end

  def lookup_calls
    @last_query.lookup_calls
  end

  def sorted_names(name_segments)
    sorted = name_segments.to_a.sort_by { |segment| segment.getName }
    "[#{sorted.map(&:to_s).join(', ')}]"
  end

  # Java: IdBatchResolverTest#testSimpleEnum
  it "resolves simple enum set members" do
    resolved = batch_resolve(
      "SELECT " \
      "{[Product].[Food].[Dairy]," \
      "[Product].[Food].[Deli]," \
      "[Product].[Food].[Eggs]," \
      "[Product].[Food].[Produce]," \
      "[Product].[Food].[Starchy Foods]}" \
      "on 0 FROM SALES"
    )

    [
      "[Product].[Food].[Dairy]",
      "[Product].[Food].[Deli]",
      "[Product].[Food].[Eggs]",
      "[Product].[Food].[Produce]",
      "[Product].[Food].[Starchy Foods]"
    ].each { |member| assert_includes resolved, member, "Resolved map omitted #{member}" }

    # Verify lookupMemberChildrenByNames was called with batched children
    calls = lookup_calls
    assert_equal 2, calls.size

    assert_equal "[Product].[All Products]", calls[0][:parent].getUniqueName
    assert_equal 1, calls[0][:children].size
    assert_equal "Food", calls[0][:children][0].getName

    assert_equal "[Product].[Food]", calls[1][:parent].getUniqueName
    assert_equal 5, calls[1][:children].size
    assert_equal "[[Dairy], [Deli], [Eggs], [Produce], [Starchy Foods]]",
      sorted_names(calls[1][:children])
  end

  # Java: IdBatchResolverTest#testCalcMemsNotResolved
  it "does not resolve calculated members" do
    resolved = batch_resolve(
      "with member time.foo as '1' member time.bar as '2' " \
      " select " \
      " {[Time].[foo], [Time].[bar], " \
      "  [Time].[1997]," \
      "  [Time].[1997].[Q1], [Time].[1997].[Q2]} " \
      " on 0 from sales "
    )

    refute_includes resolved, "[Time].[foo]", "Resolved map should not contain calc member [Time].[foo]"
    refute_includes resolved, "[Time].[bar]", "Resolved map should not contain calc member [Time].[bar]"
  end

  # Java: IdBatchResolverTest#testLevelReferenceHandled
  it "handles level references without batching them as children" do
    # Make sure ["Week", 1997] don't get batched as children of [Time.Weekly].[All]
    batch_resolve(
      "with member Gender.levelRef as " \
      "'Sum(Descendants([Time.Weekly].CurrentMember, [Time.Weekly].Week))' " \
      "select Gender.levelRef on 0 from sales where [Time.Weekly].[1997]"
    )

    calls = lookup_calls
    assert_equal 1, calls.size

    assert_equal "[Time.Weekly].[All Time.Weeklys]", calls[0][:parent].getUniqueName
    assert_equal "[[1997]]", sorted_names(calls[0][:children])
  end

  # Java: IdBatchResolverTest#testPhysMemsResolvedWhenCalcsMixedIn
  it "resolves physical members when mixed with calculated members" do
    resolved = batch_resolve(
      "with member time.foo as '1' member time.bar as '2' " \
      " select " \
      " {[Time].[foo], [Time].[bar], " \
      "  [Time].[1997]," \
      "  [Time].[1997].[Q1], [Time].[1997].[Q2]} " \
      " on 0 from sales "
    )

    [
      "[Time].[1997]",
      "[Time].[1997].[Q1]",
      "[Time].[1997].[Q2]"
    ].each { |member| assert_includes resolved, member, "Resolved map omitted #{member}" }

    calls = lookup_calls
    assert_equal 1, calls.size

    assert_equal "[Time].[1997]", calls[0][:parent].getUniqueName
    assert_equal 2, calls[0][:children].size
    assert_equal "[[Q1], [Q2]]", sorted_names(calls[0][:children])
  end

  # Java: IdBatchResolverTest#testAnalyzerFilterMdx
  it "resolves members in analyzer-style filter MDX" do
    resolved = batch_resolve(
      "WITH\n" \
      "SET [*NATIVE_CJ_SET] AS 'NONEMPTYCROSSJOIN([*BASE_MEMBERS__Promotions_],[*BASE_MEMBERS__Store_])'\n" \
      "SET [*BASE_MEMBERS__Store_] AS '{[Store].[USA].[WA].[Bellingham],[Store].[USA].[CA].[Beverly Hills]," \
        "[Store].[USA].[WA].[Bremerton],[Store].[USA].[CA].[Los Angeles]}'\n" \
      "SET [*SORTED_COL_AXIS] AS 'ORDER([*CJ_COL_AXIS],[Promotions].CURRENTMEMBER.ORDERKEY,BASC)'\n" \
      "SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'\n" \
      "SET [*CJ_ROW_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Store].CURRENTMEMBER)})'\n" \
      "SET [*BASE_MEMBERS__Promotions_] AS '{[Promotions].[Bag Stuffers],[Promotions].[Best Savings]," \
        "[Promotions].[Big Promo],[Promotions].[Big Time Discounts],[Promotions].[Big Time Savings]," \
        "[Promotions].[Bye Bye Baby]}'\n" \
      "SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],[Store].CURRENTMEMBER.ORDERKEY,BASC," \
        "ANCESTOR([Store].CURRENTMEMBER,[Store].[Store State]).ORDERKEY,BASC)'\n" \
      "SET [*CJ_COL_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Promotions].CURRENTMEMBER)})'\n" \
      "MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', " \
        "SOLVE_ORDER=500\n" \
      "SELECT\n" \
      "CROSSJOIN([*SORTED_COL_AXIS],[*BASE_MEMBERS__Measures_]) ON COLUMNS\n" \
      ",NON EMPTY\n" \
      "[*SORTED_ROW_AXIS] ON ROWS\n" \
      "FROM [Sales]"
    )

    [
      "[Store].[USA].[WA].[Bellingham]",
      "[Store].[USA].[CA].[Beverly Hills]",
      "[Store].[USA].[WA].[Bremerton]",
      "[Store].[USA].[CA].[Los Angeles]",
      "[Promotions].[Bag Stuffers]",
      "[Promotions].[Best Savings]",
      "[Promotions].[Big Promo]",
      "[Promotions].[Big Time Discounts]",
      "[Promotions].[Big Time Savings]",
      "[Promotions].[Bye Bye Baby]"
    ].each { |member| assert_includes resolved, member, "Resolved map omitted #{member}" }

    calls = lookup_calls
    assert_equal 5, calls.size

    assert_equal "[Promotions].[All Promotions]", calls[0][:parent].getUniqueName
    assert_equal 6, calls[0][:children].size
    assert_equal "[[Bag Stuffers], [Best Savings], [Big Promo], " \
      "[Big Time Discounts], [Big Time Savings], [Bye Bye Baby]]",
      sorted_names(calls[0][:children])

    assert_equal "[Store].[USA].[CA]", calls[3][:parent].getUniqueName
    assert_equal 2, calls[3][:children].size
    assert_equal "[[Beverly Hills], [Los Angeles]]",
      sorted_names(calls[3][:children])
  end

  # Java: IdBatchResolverTest#testSetWithNullMember
  it "resolves set containing null member" do
    resolved = batch_resolve(
      "WITH\n" \
      "SET [*NATIVE_CJ_SET] AS 'FILTER([*BASE_MEMBERS__Store Size in SQFT_], " \
        "NOT ISEMPTY ([Measures].[Unit Sales]))'\n" \
      "SET [*BASE_MEMBERS__Store Size in SQFT_] AS '{[Store Size in SQFT].[#null]," \
        "[Store Size in SQFT].[20319],[Store Size in SQFT].[21215]," \
        "[Store Size in SQFT].[22478],[Store Size in SQFT].[23598]}'\n" \
      "SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'\n" \
      "SET [*CJ_SLICER_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], " \
        "{([Store Size in SQFT].CURRENTMEMBER)})'\n" \
      "MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Unit Sales]', " \
        "FORMAT_STRING = 'Standard', SOLVE_ORDER=500\n" \
      "SELECT\n" \
      "[*BASE_MEMBERS__Measures_] ON COLUMNS\n" \
      "FROM [Sales]\n" \
      "WHERE ([*CJ_SLICER_AXIS])"
    )

    [
      "[Store Size in SQFT].[#null]",
      "[Store Size in SQFT].[20319]",
      "[Store Size in SQFT].[21215]",
      "[Store Size in SQFT].[22478]",
      "[Store Size in SQFT].[23598]"
    ].each { |member| assert_includes resolved, member, "Resolved map omitted #{member}" }

    calls = lookup_calls
    assert_equal 1, calls.size

    assert_equal "[Store Size in SQFT].[All Store Size in SQFTs]", calls[0][:parent].getUniqueName
    assert_equal 5, calls[0][:children].size
    assert_equal "[[#null], [20319], [21215], [22478], [23598]]",
      sorted_names(calls[0][:children])
  end

  # Java: IdBatchResolverTest#testMultiHierarchyNonSSAS
  it "resolves multi-hierarchy with non-SSAS naming" do
    with_properties(SsasCompatibleNaming: false) do
      resolved = batch_resolve(
        "WITH\n" \
        "SET [*NATIVE_CJ_SET] AS 'FILTER([*BASE_MEMBERS__Time.Weekly_], " \
          "NOT ISEMPTY ([Measures].[Unit Sales]))'\n" \
        "SET [*BASE_MEMBERS__Time.Weekly_] AS '{[Time.Weekly].[1997].[4]," \
          "[Time.Weekly].[1997].[5],[Time.Weekly].[1997].[6]}'\n" \
        "SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'\n" \
        "SET [*CJ_SLICER_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Time.Weekly].CURRENTMEMBER)})'\n" \
        "MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Unit Sales]', " \
          "FORMAT_STRING = 'Standard', SOLVE_ORDER=500\n" \
        "SELECT\n" \
        "[*BASE_MEMBERS__Measures_] ON COLUMNS\n" \
        "FROM [Sales]\n" \
        "WHERE ([*CJ_SLICER_AXIS])"
      )

      [
        "[Time.Weekly].[1997].[4]",
        "[Time.Weekly].[1997].[5]",
        "[Time.Weekly].[1997].[6]"
      ].each { |member| assert_includes resolved, member, "Resolved map omitted #{member}" }

      calls = lookup_calls
      assert_equal 2, calls.size

      assert_equal "[Time.Weekly].[All Time.Weeklys]", calls[0][:parent].getUniqueName
      assert_equal 1, calls[0][:children].size
      assert_equal "1997", calls[0][:children][0].getName

      assert_equal "[[4], [5], [6]]", sorted_names(calls[1][:children])
    end
  end

  # Java: IdBatchResolverTest#testMultiHierarchySSAS
  it "resolves multi-hierarchy with SSAS naming" do
    with_properties(SsasCompatibleNaming: true) do
      # Fresh connection with modified schema content to force a new schema pool
      # entry, ensuring the schema loads with SSAS naming enabled.
      schema = SchemaHelper::FOODMART_SCHEMA.sub("<!--", "<!-- SSAS test ")
      params = CONNECTION_PARAMS.merge(catalog_content: schema)
      params.delete(:catalog)
      ssas_olap = Mondrian::OLAP::Connection.create(params)
      begin
        resolved = batch_resolve(
          "WITH\n" \
          "SET [*NATIVE_CJ_SET] AS 'FILTER([*BASE_MEMBERS__Time.Weekly_], " \
            "NOT ISEMPTY ([Measures].[Unit Sales]))'\n" \
          "SET [*BASE_MEMBERS__Time.Weekly_] AS '{[Time].[Weekly].[1997].[4]," \
            "[Time].[Weekly].[1997].[5],[Time].[Weekly].[1997].[6]}'\n" \
          "SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'\n" \
          "SET [*CJ_SLICER_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], " \
            "{([Time].[Weekly].CURRENTMEMBER)})'\n" \
          "MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Unit Sales]', " \
            "FORMAT_STRING = 'Standard', SOLVE_ORDER=500\n" \
          "SELECT\n" \
          "[*BASE_MEMBERS__Measures_] ON COLUMNS\n" \
          "FROM [Sales]\n" \
          "WHERE ([*CJ_SLICER_AXIS])",
          olap: ssas_olap
        )

        [
          "[Time].[Weekly].[1997].[4]",
          "[Time].[Weekly].[1997].[5]",
          "[Time].[Weekly].[1997].[6]"
        ].each { |member| assert_includes resolved, member, "Resolved map omitted #{member}" }

        calls = lookup_calls
        assert_equal 2, calls.size

        assert_equal "[Time].[Weekly].[All Weeklys]", calls[0][:parent].getUniqueName
        assert_equal 1, calls[0][:children].size
        assert_equal "1997", calls[0][:children][0].getName

        assert_equal "[[4], [5], [6]]", sorted_names(calls[1][:children])
      ensure
        ssas_olap.close
      end
    end
  end

  # Java: IdBatchResolverTest#testParentChild
  it "resolves parent-child hierarchy members" do
    # P-C resolution will not result in consolidated SQL, but it should
    # still correctly identify children and attempt to resolve them together.
    resolved = batch_resolve(
      "WITH\n" \
      "SET [*NATIVE_CJ_SET] AS 'FILTER([*BASE_MEMBERS__Employees_], " \
        "NOT ISEMPTY ([Measures].[Number of Employees]))'\n" \
      "SET [*BASE_MEMBERS__Employees_] AS '{[Employees].[Sheri Nowmer].[Derrick Whelply]," \
        "[Employees].[Sheri Nowmer].[Michael Spence]}'\n" \
      "SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'\n" \
      "SET [*CJ_SLICER_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Employees].CURRENTMEMBER)})'\n" \
      "MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Number of Employees]', " \
        "FORMAT_STRING = '#,#', SOLVE_ORDER=500\n" \
      "SELECT\n" \
      "[*BASE_MEMBERS__Measures_] ON COLUMNS\n" \
      "FROM [HR]\n" \
      "WHERE ([*CJ_SLICER_AXIS])"
    )

    [
      "[Employees].[Sheri Nowmer].[Derrick Whelply]",
      "[Employees].[Sheri Nowmer].[Michael Spence]"
    ].each { |member| assert_includes resolved, member, "Resolved map omitted #{member}" }

    calls = lookup_calls
    assert_equal 2, calls.size

    assert_equal "[Employees].[Sheri Nowmer]", calls[1][:parent].getUniqueName
    assert_equal 2, calls[1][:children].size
  end
end
