# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2006-2020 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# InvocationHandler for the package-private RolapNative.Listener interface.
class FilterTestListenerHandler
  include java.lang.reflect.InvocationHandler

  attr_reader :evaluator_found, :execute_sql
  attr_writer :execute_sql

  def initialize
    @evaluator_found = false
    @execute_sql = false
  end

  def invoke(_proxy, method, _args)
    case method.getName
    when "foundEvaluator"
      @evaluator_found = true
    when "executingSql"
      @execute_sql = true
    end
    nil
  end
end

# Java: mondrian/rolap/FilterTest.java
describe "Filter" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # -- Reflection helpers for package-private RolapNativeRegistry API --

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
    handler = FilterTestListenerHandler.new
    proxy = java.lang.reflect.Proxy.newProxyInstance(
      class_loader,
      [listener_interface].to_java(java.lang.Class),
      handler
    )
    [proxy, handler]
  end

  # Matches Java BatchTestCase.checkNative.
  # Creates a fresh connection, runs with native enabled then disabled,
  # compares results, and verifies native evaluator was used.
  def check_native(olap, mdx, expected_result: nil)
    Mondrian::OLAP::Connection.flush_schema_cache
    connection = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
    begin
      registry = get_native_registry(connection)

      # Run with native enabled
      set_native_hard_cache(registry, true)
      proxy, handler = create_native_listener(registry)
      set_native_listener(registry, proxy)
      set_native_enabled(registry, true)
      native_result = format_result(connection.execute(mdx))
      assert_equal true, handler.evaluator_found, "expected native execution of #{mdx}"

      connection.close
      Mondrian::OLAP::Connection.flush_schema_cache

      # Run with native disabled (interpreter)
      connection = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      registry = get_native_registry(connection)
      set_native_enabled(registry, false)
      begin
        interpreted_result = format_result(connection.execute(mdx))
      ensure
        set_native_enabled(registry, true)
        set_native_hard_cache(registry, false)
        set_native_listener(registry, nil)
      end

      if expected_result
        assert_like expected_result, native_result, "Native result mismatch"
        assert_like expected_result, interpreted_result, "Interpreted result mismatch"
      end
      assert_equal interpreted_result, native_result,
        "Native implementation returned different result than interpreter; MDX=#{mdx}"
    ensure
      connection&.close
    end
  end

  # Matches Java BatchTestCase.checkNotNative.
  # Creates a fresh connection, sets a listener that tracks native evaluation,
  # runs the query, and verifies native evaluator was NOT used.
  def check_not_native(olap, mdx, expected_result: nil)
    Mondrian::OLAP::Connection.flush_schema_cache
    connection = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
    begin
      registry = get_native_registry(connection)
      proxy, handler = create_native_listener(registry)
      set_native_listener(registry, proxy)

      result = format_result(connection.execute(mdx))
      assert_equal false, handler.evaluator_found, "should not be executed native"

      if expected_result
        assert_like expected_result, result, "Non-native result mismatch"
      end
    ensure
      set_native_listener(registry, nil) if registry
      connection&.close
    end
  end

  # Matches Java BatchTestCase.assertQuerySql.
  # Executes MDX while capturing SQL, then asserts that at least one
  # captured SQL statement contains the expected SQL substring.
  # Uses an olap connection (or creates a fresh one).
  def assert_query_sql(olap, mdx, expected_sql)
    Mondrian::OLAP::Connection.flush_schema_cache
    connection = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
    begin
      queries = capture_sql { connection.execute(mdx) }
      normalized_expected = expected_sql.gsub("\r\n", "\n").strip
      match = queries.any? { |q| q.gsub("\r\n", "\n").include?(normalized_expected) }
      assert match, "Expected SQL not found in captured queries.\nExpected substring:\n#{normalized_expected}\nCaptured queries:\n#{queries.to_a.join("\n---\n")}"
    ensure
      connection&.close
    end
  end

  # Java: FilterTest#testInFilterSimple
  it "In filter simple" do
    with_properties(EnableNativeCrossJoin: true, ExpandNonNative: false, EnableNativeFilter: true) do
      mdx = <<~MDX
        With
        Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Customers],[*BASE_MEMBERS_Product])'
        Set [*BASE_MEMBERS_Customers] as 'Filter([Customers].[City].Members,Ancestor([Customers].CurrentMember, [Customers].[State Province]) In {[Customers].[All Customers].[USA].[CA]})'
        Set [*BASE_MEMBERS_Product] as 'Filter([Product].[Product Family].Members,[Product].CurrentMember In {[Product].[All Products].[Drink]})'
        Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember,[Product].currentMember)})'
        Select
        {[Measures].[Customer Count]} on columns,
        Non Empty [*CJ_ROW_AXIS] on rows
        From [Sales]
      MDX
      check_native @olap, mdx
    end
  end

  # Java: FilterTest#testNotInFilterSimple
  it "Not In filter simple" do
    with_properties(EnableNativeCrossJoin: true, ExpandNonNative: false, EnableNativeFilter: true) do
      mdx = <<~MDX
        With
        Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Customers],[*BASE_MEMBERS_Product])'
        Set [*BASE_MEMBERS_Customers] as 'Filter([Customers].[City].Members,Ancestor([Customers].CurrentMember, [Customers].[State Province]) Not In {[Customers].[All Customers].[USA].[CA]})'
        Set [*BASE_MEMBERS_Product] as 'Filter([Product].[Product Family].Members,[Product].CurrentMember Not In {[Product].[All Products].[Drink]})'
        Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember,[Product].currentMember)})'
        Select
        {[Measures].[Customer Count]} on columns,
        Non Empty [*CJ_ROW_AXIS] on rows
        From [Sales]
      MDX
      check_native @olap, mdx
    end
  end

  # Java: FilterTest#testInFilterAND
  it "In filter with AND" do
    with_properties(EnableNativeCrossJoin: true, ExpandNonNative: false, EnableNativeFilter: true) do
      mdx = <<~MDX
        With
        Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Customers],[*BASE_MEMBERS_Product])'
        Set [*BASE_MEMBERS_Customers] as 'Filter([Customers].[City].Members,((Ancestor([Customers].CurrentMember, [Customers].[State Province]) In {[Customers].[All Customers].[USA].[CA]}) AND ([Customers].CurrentMember Not In {[Customers].[All Customers].[USA].[CA].[Altadena]})))'
        Set [*BASE_MEMBERS_Product] as 'Filter([Product].[Product Family].Members,[Product].CurrentMember Not In {[Product].[All Products].[Drink]})'
        Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember,[Product].currentMember)})'
        Select
        {[Measures].[Customer Count]} on columns,
        Non Empty [*CJ_ROW_AXIS] on rows
        From [Sales]
      MDX
      check_native @olap, mdx
    end
  end

  # Java: FilterTest#testIsFilterSimple
  it "Is filter simple" do
    with_properties(EnableNativeCrossJoin: true, ExpandNonNative: false, EnableNativeFilter: true) do
      mdx = <<~MDX
        With
        Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Customers],[*BASE_MEMBERS_Product])'
        Set [*BASE_MEMBERS_Customers] as 'Filter([Customers].[City].Members,Ancestor([Customers].CurrentMember, [Customers].[State Province]) Is [Customers].[All Customers].[USA].[CA])'
        Set [*BASE_MEMBERS_Product] as 'Filter([Product].[Product Family].Members,[Product].CurrentMember Is [Product].[All Products].[Drink])'
        Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember,[Product].currentMember)})'
        Select
        {[Measures].[Customer Count]} on columns,
        Non Empty [*CJ_ROW_AXIS] on rows
        From [Sales]
      MDX
      check_native @olap, mdx
    end
  end

  # Java: FilterTest#testNotIsFilterSimple
  it "Not Is filter simple" do
    with_properties(EnableNativeCrossJoin: true, ExpandNonNative: false, EnableNativeFilter: true) do
      mdx = <<~MDX
        With
        Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Customers],[*BASE_MEMBERS_Product])'
        Set [*BASE_MEMBERS_Customers] as 'Filter([Customers].[City].Members, not (Ancestor([Customers].CurrentMember, [Customers].[State Province]) Is [Customers].[All Customers].[USA].[CA]))'
        Set [*BASE_MEMBERS_Product] as 'Filter([Product].[Product Family].Members,not ([Product].CurrentMember Is [Product].[All Products].[Drink]))'
        Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember,[Product].currentMember)})'
        Select
        {[Measures].[Customer Count]} on columns,
        Non Empty [*CJ_ROW_AXIS] on rows
        From [Sales]
      MDX
      check_native @olap, mdx
    end
  end

  # Java: FilterTest#testMixedInIsFilters
  it "mixed In and Is filters" do
    with_properties(EnableNativeCrossJoin: true, ExpandNonNative: false, EnableNativeFilter: true) do
      mdx = <<~MDX
        With
        Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Customers],[*BASE_MEMBERS_Product])'
        Set [*BASE_MEMBERS_Customers] as 'Filter([Customers].[City].Members,((Ancestor([Customers].CurrentMember, [Customers].[State Province]) Is [Customers].[All Customers].[USA].[CA]) AND ([Customers].CurrentMember Not In {[Customers].[All Customers].[USA].[CA].[Altadena]})))'
        Set [*BASE_MEMBERS_Product] as 'Filter([Product].[Product Family].Members, not ([Product].CurrentMember Is [Product].[All Products].[Drink]))'
        Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember,[Product].currentMember)})'
        Select
        {[Measures].[Customer Count]} on columns,
        Non Empty [*CJ_ROW_AXIS] on rows
        From [Sales]
      MDX
      check_native @olap, mdx
    end
  end

  # Java: FilterTest#testInFilterNonNative
  # Filter above NECJ is not natively evaluated.
  it "In filter non-native" do
    with_properties(EnableNativeCrossJoin: true, ExpandNonNative: false, EnableNativeFilter: true) do
      mdx = <<~MDX
        With
        Set [*BASE_CJ_SET] as 'CrossJoin([Customers].[City].Members,[Product].[Product Family].Members)'
        Set [*NATIVE_CJ_SET] as 'Filter([*BASE_CJ_SET], (Ancestor([Customers].CurrentMember,[Customers].[State Province]) In {[Customers].[All Customers].[USA].[CA]}) AND ([Product].CurrentMember In {[Product].[All Products].[Drink]}))'
        Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember,[Product].currentMember)})'
        Select
        {[Measures].[Customer Count]} on columns,
        Non Empty [*CJ_ROW_AXIS] on rows
        From [Sales]
      MDX
      check_not_native @olap, mdx
    end
  end

  # Java: FilterTest#testTopCountOverInFilter
  it "TopCount over In filter" do
    with_properties(EnableNativeCrossJoin: true, ExpandNonNative: false, EnableNativeFilter: true,
                    EnableNativeTopCount: true) do
      mdx = <<~MDX
        With
        Set [*NATIVE_TOP_SET] as 'TopCount([*BASE_MEMBERS_Customers], 3, [Measures].[Customer Count])'
        Set [*BASE_MEMBERS_Customers] as 'Filter([Customers].[City].Members,Ancestor([Customers].CurrentMember, [Customers].[State Province]) In {[Customers].[All Customers].[USA].[CA]})'
        Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_TOP_SET], {([Customers].currentMember,[Product].currentMember)})'
        Select
        {[Measures].[Customer Count]} on columns,
        Non Empty [*CJ_ROW_AXIS] on rows
        From [Sales]
      MDX
      check_native @olap, mdx
    end
  end

  # Java: FilterTest#testNotInFilterKeepNullMember
  # Null member should not be filtered out when not explicitly excluded.
  it "Not In filter keeps null member" do
    with_properties(EnableNativeCrossJoin: true, ExpandNonNative: false, EnableNativeFilter: true) do
      mdx = <<~MDX
        With
        Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Customers],[*BASE_MEMBERS_SQFT])'
        Set [*BASE_MEMBERS_Customers] as 'Filter([Customers].[Country].Members, [Customers].CurrentMember In {[Customers].[All Customers].[USA]})'
        Set [*BASE_MEMBERS_SQFT] as 'Filter([Store Size in SQFT].[Store Sqft].Members, [Store Size in SQFT].currentMember not in {[Store Size in SQFT].[All Store Size in SQFTs].[39696]})'
        Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember,[Store Size in SQFT].currentMember)})'
        Set [*ORDERED_CJ_ROW_AXIS] as 'Order([*CJ_ROW_AXIS], [Store Size in SQFT].currentmember.OrderKey, BASC)'
        Select
        {[Measures].[Customer Count]} on columns,
        Non Empty [*ORDERED_CJ_ROW_AXIS] on rows
        From [Sales]
      MDX
      expected = <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Customer Count]}
        Axis #2:
        {[Customers].[USA], [Store Size in SQFT].[#null]}
        {[Customers].[USA], [Store Size in SQFT].[20319]}
        {[Customers].[USA], [Store Size in SQFT].[21215]}
        {[Customers].[USA], [Store Size in SQFT].[22478]}
        {[Customers].[USA], [Store Size in SQFT].[23598]}
        {[Customers].[USA], [Store Size in SQFT].[23688]}
        {[Customers].[USA], [Store Size in SQFT].[27694]}
        {[Customers].[USA], [Store Size in SQFT].[28206]}
        {[Customers].[USA], [Store Size in SQFT].[30268]}
        {[Customers].[USA], [Store Size in SQFT].[33858]}
        Row #0: 1,153
        Row #1: 563
        Row #2: 906
        Row #3: 296
        Row #4: 1,147
        Row #5: 1,059
        Row #6: 474
        Row #7: 190
        Row #8: 84
        Row #9: 278
      RESULT
      check_native @olap, mdx, expected_result: expected
    end
  end

  # Java: FilterTest#testNotInFilterExcludeNullMember
  # Null member should be filtered out when explicitly excluded.
  it "Not In filter excludes null member" do
    with_properties(EnableNativeCrossJoin: true, ExpandNonNative: false, EnableNativeFilter: true) do
      mdx = <<~MDX
        With
        Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Customers],[*BASE_MEMBERS_SQFT])'
        Set [*BASE_MEMBERS_Customers] as 'Filter([Customers].[Country].Members, [Customers].CurrentMember In {[Customers].[All Customers].[USA]})'
        Set [*BASE_MEMBERS_SQFT] as 'Filter([Store Size in SQFT].[Store Sqft].Members, [Store Size in SQFT].currentMember not in {[Store Size in SQFT].[All Store Size in SQFTs].[#null], [Store Size in SQFT].[All Store Size in SQFTs].[39696]})'
        Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember,[Store Size in SQFT].currentMember)})'
        Set [*ORDERED_CJ_ROW_AXIS] as 'Order([*CJ_ROW_AXIS], [Store Size in SQFT].currentmember.OrderKey, BASC)'
        Select
        {[Measures].[Customer Count]} on columns,
        Non Empty [*ORDERED_CJ_ROW_AXIS] on rows
        From [Sales]
      MDX
      expected = <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Customer Count]}
        Axis #2:
        {[Customers].[USA], [Store Size in SQFT].[20319]}
        {[Customers].[USA], [Store Size in SQFT].[21215]}
        {[Customers].[USA], [Store Size in SQFT].[22478]}
        {[Customers].[USA], [Store Size in SQFT].[23598]}
        {[Customers].[USA], [Store Size in SQFT].[23688]}
        {[Customers].[USA], [Store Size in SQFT].[27694]}
        {[Customers].[USA], [Store Size in SQFT].[28206]}
        {[Customers].[USA], [Store Size in SQFT].[30268]}
        {[Customers].[USA], [Store Size in SQFT].[33858]}
        Row #0: 563
        Row #1: 906
        Row #2: 296
        Row #3: 1,147
        Row #4: 1,059
        Row #5: 474
        Row #6: 190
        Row #7: 84
        Row #8: 278
      RESULT
      check_native @olap, mdx, expected_result: expected
    end
  end

  # Java: FilterTest#testNotInMultiLevelMemberConstraintNonNullParent
  # SQL pattern test verifying null members are included when filter excludes
  # members with multiple levels, none being null.
  # Known Java failure on MySQL.
  # TODO: Investigate why this fails in Java — the expected SQL may be outdated.
  # Consider adding a PostgreSQL SQL pattern or converting to a result-based assertion.
  it "Not In multi level member constraint non-null parent" do
    skip "SQL pattern test for MySQL only" unless MONDRIAN_DRIVER == "mysql"
    skip "Skipped when ReadAggregates is enabled" if mondrian_property(:ReadAggregates).get
    mdx = <<~MDX
      With
      Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Customers],[*BASE_MEMBERS_Quarters])'
      Set [*BASE_MEMBERS_Customers] as 'Filter([Customers].[Country].Members, [Customers].CurrentMember In {[Customers].[All Customers].[USA]})'
      Set [*BASE_MEMBERS_Quarters] as 'Filter([Time].[Quarter].Members, [Time].currentMember not in {[Time].[1997].[Q1], [Time].[1998].[Q3]})'
      Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember,[Time].currentMember)})'
      Set [*ORDERED_CJ_ROW_AXIS] as 'Order([*CJ_ROW_AXIS], [Time].currentmember.OrderKey, BASC)'
      Select
      {[Measures].[Customer Count]} on columns,
      Non Empty [*ORDERED_CJ_ROW_AXIS] on rows
      From [Sales]
    MDX
    expected_sql =
      "select `customer`.`country` as `c0`, `time_by_day`.`the_year` as `c1`, " \
      "`time_by_day`.`quarter` as `c2` from `customer` as `customer`, " \
      "`sales_fact_1997` as `sales_fact_1997`, `time_by_day` as `time_by_day` " \
      "where `sales_fact_1997`.`customer_id` = `customer`.`customer_id` " \
      "and `sales_fact_1997`.`time_id` = `time_by_day`.`time_id` and " \
      "(`customer`.`country` = 'USA') and " \
      "(not ((`time_by_day`.`quarter`, `time_by_day`.`the_year`) in " \
      "(('Q1', 1997), ('Q3', 1998))) or (`time_by_day`.`quarter` is null or " \
      "`time_by_day`.`the_year` is null)) " \
      "group by `customer`.`country`, `time_by_day`.`the_year`, `time_by_day`.`quarter`"
    with_properties(EnableNativeCrossJoin: true) do
      assert_query_sql @olap, mdx, expected_sql
    end
  end

  # Java: FilterTest#testNotInMultiLevelMemberConstraintNonNullSameParent
  # Members have the same parent.
  # Known Java failure on MySQL.
  # TODO: Investigate why this fails in Java — the expected SQL may be outdated.
  # Consider adding a PostgreSQL SQL pattern or converting to a result-based assertion.
  it "Not In multi level member constraint non-null same parent" do
    skip "SQL pattern test for MySQL only" unless MONDRIAN_DRIVER == "mysql"
    skip "Skipped when ReadAggregates is enabled" if mondrian_property(:ReadAggregates).get
    mdx = <<~MDX
      With
      Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Customers],[*BASE_MEMBERS_Quarters])'
      Set [*BASE_MEMBERS_Customers] as 'Filter([Customers].[Country].Members, [Customers].CurrentMember In {[Customers].[All Customers].[USA]})'
      Set [*BASE_MEMBERS_Quarters] as 'Filter([Time].[Quarter].Members, [Time].currentMember not in {[Time].[1997].[Q1], [Time].[1997].[Q3]})'
      Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember,[Time].currentMember)})'
      Set [*ORDERED_CJ_ROW_AXIS] as 'Order([*CJ_ROW_AXIS], [Time].currentmember.OrderKey, BASC)'
      Select
      {[Measures].[Customer Count]} on columns,
      Non Empty [*ORDERED_CJ_ROW_AXIS] on rows
      From [Sales]
    MDX
    expected_sql =
      "select `customer`.`country` as `c0`, `time_by_day`.`the_year` as " \
      "`c1`, `time_by_day`.`quarter` as `c2` from `customer` as " \
      "`customer`, `sales_fact_1997` as `sales_fact_1997`, `time_by_day` " \
      "as `time_by_day` where `sales_fact_1997`.`customer_id` = " \
      "`customer`.`customer_id` and `sales_fact_1997`.`time_id` = " \
      "`time_by_day`.`time_id` and (`customer`.`country` = 'USA') and " \
      "((not (`time_by_day`.`quarter` in ('Q1', 'Q3')) or " \
      "(`time_by_day`.`quarter` is null)) or (not " \
      "(`time_by_day`.`the_year` = 1997) or (`time_by_day`.`the_year` " \
      "is null))) group by `customer`.`country`, `time_by_day`.`the_year`, `time_by_day`.`quarter`"
    with_properties(EnableNativeCrossJoin: true) do
      assert_query_sql @olap, mdx, expected_sql
    end
  end

  # Java: FilterTest#testNotInMultiLevelMemberConstraintMixedNullNonNullParent
  # Filter explicitly excludes certain members that contain nulls.
  # Members span multiple levels.
  # TODO: Only tested on MySQL. Add PostgreSQL SQL pattern or convert to result-based assertion.
  it "Not In multi level member constraint mixed null non-null parent" do
    skip "SQL pattern test for MySQL only" unless MONDRIAN_DRIVER == "mysql"
    skip "Skipped when FilterChildlessSnowflakeMembers is enabled" if mondrian_property(:FilterChildlessSnowflakeMembers).get
    dimension_xml = <<~XML
      <Dimension name="Warehouse2">
        <Hierarchy hasAll="true" primaryKey="warehouse_id">
          <Table name="warehouse"/>
          <Level name="fax" column="warehouse_fax" uniqueMembers="true"/>
          <Level name="address1" column="wa_address1" uniqueMembers="false"/>
          <Level name="name" column="warehouse_name" uniqueMembers="false"/>
        </Hierarchy>
      </Dimension>
    XML
    cube_xml = <<~XML
      <Cube name="Warehouse2">
        <Table name="inventory_fact_1997"/>
        <DimensionUsage name="Product" source="Product" foreignKey="product_id"/>
        <DimensionUsage name="Warehouse2" source="Warehouse2" foreignKey="warehouse_id"/>
        <Measure name="Warehouse Cost" column="warehouse_cost" aggregator="sum"/>
        <Measure name="Warehouse Sales" column="warehouse_sales" aggregator="sum"/>
      </Cube>
    XML
    schema = SchemaHelper::FOODMART_SCHEMA
      .sub("<Cube name=\"Sales\"", "#{dimension_xml}<Cube name=\"Sales\"")
      .sub("<VirtualCube", "#{cube_xml}<VirtualCube")
    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    connection = Mondrian::OLAP::Connection.create(params)
    begin
      mdx = <<~MDX
        with
        set [Filtered Warehouse Set] as 'Filter([Warehouse2].[name].Members, [Warehouse2].CurrentMember Not In{[Warehouse2].[#null].[234 West Covina Pkwy].[Freeman And Co], [Warehouse2].[971-555-6213].[3377 Coachman Place].[Jones International]})'
        set [NECJ] as NonEmptyCrossJoin([Filtered Warehouse Set], {[Product].[Product Family].Food})
        select [NECJ] on 0 from [Warehouse2]
      MDX
      expected_sql =
        "select `warehouse`.`warehouse_fax` as `c0`, `warehouse`.`wa_address1` as `c1`, " \
        "`warehouse`.`warehouse_name` as `c2`, `product_class`.`product_family` as `c3` " \
        "from `warehouse` as `warehouse`, `inventory_fact_1997` as `inventory_fact_1997`, " \
        "`product` as `product`, `product_class` as `product_class` where " \
        "`inventory_fact_1997`.`warehouse_id` = `warehouse`.`warehouse_id` " \
        "and `product`.`product_class_id` = `product_class`.`product_class_id` " \
        "and `inventory_fact_1997`.`product_id` = `product`.`product_id` " \
        "and (`product_class`.`product_family` = 'Food') and " \
        "(not ((`warehouse`.`warehouse_name`, `warehouse`.`wa_address1`, `warehouse`.`warehouse_fax`) " \
        "in (('Jones International', '3377 Coachman Place', '971-555-6213')) " \
        "or (`warehouse`.`warehouse_fax` is null and (`warehouse`.`warehouse_name`, `warehouse`.`wa_address1`) " \
        "in (('Freeman And Co', '234 West Covina Pkwy')))) or " \
        "((`warehouse`.`warehouse_name` is null or `warehouse`.`wa_address1` is null " \
        "or `warehouse`.`warehouse_fax` is null) and not((`warehouse`.`warehouse_fax` is null " \
        "and (`warehouse`.`warehouse_name`, `warehouse`.`wa_address1`) in " \
        "(('Freeman And Co', '234 West Covina Pkwy'))))))"
      queries = capture_sql { connection.execute(mdx) }
      normalized_expected = expected_sql.gsub("\r\n", "\n").strip
      match = queries.any? { |q| q.gsub("\r\n", "\n").include?(normalized_expected) }
      assert match, "Expected SQL not found.\nExpected substring:\n#{normalized_expected}\nCaptured:\n#{queries.to_a.join("\n---\n")}"
    ensure
      connection.close
    end
  end

  # Java: FilterTest#testNotInMultiLevelMemberConstraintSingleNullParent
  # Filter explicitly excludes a single member that has a null.
  # TODO: Only tested on MySQL. Add PostgreSQL SQL pattern or convert to result-based assertion.
  it "Not In multi level member constraint single null parent" do
    skip "SQL pattern test for MySQL only" unless MONDRIAN_DRIVER == "mysql"
    skip "Skipped when FilterChildlessSnowflakeMembers is enabled" if mondrian_property(:FilterChildlessSnowflakeMembers).get
    dimension_xml = <<~XML
      <Dimension name="Warehouse2">
        <Hierarchy hasAll="true" primaryKey="warehouse_id">
          <Table name="warehouse"/>
          <Level name="fax" column="warehouse_fax" uniqueMembers="true"/>
          <Level name="address1" column="wa_address1" uniqueMembers="false"/>
          <Level name="name" column="warehouse_name" uniqueMembers="false"/>
        </Hierarchy>
      </Dimension>
    XML
    cube_xml = <<~XML
      <Cube name="Warehouse2">
        <Table name="inventory_fact_1997"/>
        <DimensionUsage name="Product" source="Product" foreignKey="product_id"/>
        <DimensionUsage name="Warehouse2" source="Warehouse2" foreignKey="warehouse_id"/>
        <Measure name="Warehouse Cost" column="warehouse_cost" aggregator="sum"/>
        <Measure name="Warehouse Sales" column="warehouse_sales" aggregator="sum"/>
      </Cube>
    XML
    schema = SchemaHelper::FOODMART_SCHEMA
      .sub("<Cube name=\"Sales\"", "#{dimension_xml}<Cube name=\"Sales\"")
      .sub("<VirtualCube", "#{cube_xml}<VirtualCube")
    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    connection = Mondrian::OLAP::Connection.create(params)
    begin
      mdx = <<~MDX
        with
        set [Filtered Warehouse Set] as 'Filter([Warehouse2].[name].Members, [Warehouse2].CurrentMember Not In{[Warehouse2].[#null].[234 West Covina Pkwy].[Freeman And Co]})'
        set [NECJ] as NonEmptyCrossJoin([Filtered Warehouse Set], {[Product].[Product Family].Food})
        select [NECJ] on 0 from [Warehouse2]
      MDX
      expected_sql =
        "select `warehouse`.`warehouse_fax` as `c0`, " \
        "`warehouse`.`wa_address1` as `c1`, `warehouse`.`warehouse_name` " \
        "as `c2`, `product_class`.`product_family` as `c3` from " \
        "`warehouse` as `warehouse`, `inventory_fact_1997` as " \
        "`inventory_fact_1997`, `product` as `product`, `product_class` " \
        "as `product_class` where `inventory_fact_1997`.`warehouse_id` = " \
        "`warehouse`.`warehouse_id` and `product`.`product_class_id` = " \
        "`product_class`.`product_class_id` and " \
        "`inventory_fact_1997`.`product_id` = `product`.`product_id` and " \
        "(`product_class`.`product_family` = 'Food') and " \
        "((not (`warehouse`.`warehouse_name` = 'Freeman And Co') or " \
        "(`warehouse`.`warehouse_name` is null)) or (not " \
        "(`warehouse`.`wa_address1` = '234 West Covina Pkwy') or " \
        "(`warehouse`.`wa_address1` is null)) or not " \
        "(`warehouse`.`warehouse_fax` is null))"
      queries = capture_sql { connection.execute(mdx) }
      normalized_expected = expected_sql.gsub("\r\n", "\n").strip
      match = queries.any? { |q| q.gsub("\r\n", "\n").include?(normalized_expected) }
      assert match, "Expected SQL not found.\nExpected substring:\n#{normalized_expected}\nCaptured:\n#{queries.to_a.join("\n---\n")}"
    ensure
      connection.close
    end
  end

  # Java: FilterTest#testCachedNativeSetUsingFilters
  it "cached native set using filters" do
    with_properties(EnableNativeCrossJoin: true, ExpandNonNative: false, EnableNativeFilter: true) do
      mdx1 = <<~MDX
        With
        Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Customers],[*BASE_MEMBERS_Product])'
        Set [*BASE_MEMBERS_Customers] as 'Filter([Customers].[City].Members,Ancestor([Customers].CurrentMember, [Customers].[State Province]) In {[Customers].[All Customers].[USA].[CA]})'
        Set [*BASE_MEMBERS_Product] as 'Filter([Product].[Product Family].Members,[Product].CurrentMember In {[Product].[All Products].[Drink]})'
        Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember,[Product].currentMember)})'
        Select
        {[Measures].[Customer Count]} on columns,
        Non Empty [*CJ_ROW_AXIS] on rows
        From [Sales]
      MDX
      check_native @olap, mdx1

      # query2 has different filters; it should not reuse the result from query1.
      mdx2 = <<~MDX
        With
        Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Customers],[*BASE_MEMBERS_Product])'
        Set [*BASE_MEMBERS_Customers] as 'Filter([Customers].[City].Members,Ancestor([Customers].CurrentMember, [Customers].[State Province]) In {[Customers].[All Customers].[USA].[OR]})'
        Set [*BASE_MEMBERS_Product] as 'Filter([Product].[Product Family].Members,[Product].CurrentMember In {[Product].[All Products].[Drink]})'
        Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember,[Product].currentMember)})'
        Select
        {[Measures].[Customer Count]} on columns,
        Non Empty [*CJ_ROW_AXIS] on rows
        From [Sales]
      MDX
      check_native @olap, mdx2
    end
  end

  # Java: FilterTest#testNativeFilter
  it "native filter" do
    with_properties(EnableNativeCrossJoin: true, ExpandNonNative: false, EnableNativeFilter: true) do
      mdx = <<~MDX
        select {[Measures].[Store Sales]} ON COLUMNS,
        Order(Filter(Descendants([Customers].[All Customers].[USA].[CA], [Customers].[Name]), ([Measures].[Store Sales] > 200.0)), [Measures].[Store Sales], DESC) ON ROWS
        from [Sales]
        where ([Time].[1997])
      MDX
      check_native @olap, mdx
    end
  end

  # Java: FilterTest#testCmNativeFilter
  # Filter() whose condition contains a calculated member.
  it "calculated member native filter" do
    with_properties(EnableNativeCrossJoin: true, ExpandNonNative: false, EnableNativeFilter: true) do
      mdx = <<~MDX
        with member [Measures].[Rendite] as '([Measures].[Store Sales] - [Measures].[Store Cost]) / [Measures].[Store Cost]'
        select NON EMPTY {[Measures].[Unit Sales], [Measures].[Store Cost], [Measures].[Rendite], [Measures].[Store Sales]} ON COLUMNS,
        NON EMPTY Order(Filter([Product].[Product Name].Members, ([Measures].[Rendite] > 1.8)), [Measures].[Rendite], BDESC) ON ROWS
        from [Sales]
        where ([Store].[All Stores].[USA].[CA], [Time].[1997])
      MDX
      expected = <<~RESULT
        Axis #0:
        {[Store].[USA].[CA], [Time].[1997]}
        Axis #1:
        {[Measures].[Unit Sales]}
        {[Measures].[Store Cost]}
        {[Measures].[Rendite]}
        {[Measures].[Store Sales]}
        Axis #2:
        {[Product].[Food].[Baking Goods].[Jams and Jellies].[Peanut Butter].[Plato].[Plato Extra Chunky Peanut Butter]}
        {[Product].[Food].[Snack Foods].[Snack Foods].[Popcorn].[Horatio].[Horatio Buttered Popcorn]}
        {[Product].[Food].[Canned Foods].[Canned Tuna].[Tuna].[Better].[Better Canned Tuna in Oil]}
        {[Product].[Food].[Produce].[Fruit].[Fresh Fruit].[High Top].[High Top Cantelope]}
        {[Product].[Non-Consumable].[Household].[Electrical].[Lightbulbs].[Denny].[Denny 75 Watt Lightbulb]}
        {[Product].[Food].[Breakfast Foods].[Breakfast Foods].[Cereal].[Johnson].[Johnson Oatmeal]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Wine].[Portsmouth].[Portsmouth Light Wine]}
        {[Product].[Food].[Produce].[Vegetables].[Fresh Vegetables].[Ebony].[Ebony Squash]}
        Row #0: 42
        Row #0: 24.06
        Row #0: 1.93
        Row #0: 70.56
        Row #1: 36
        Row #1: 29.02
        Row #1: 1.91
        Row #1: 84.60
        Row #2: 39
        Row #2: 20.55
        Row #2: 1.85
        Row #2: 58.50
        Row #3: 25
        Row #3: 21.76
        Row #3: 1.84
        Row #3: 61.75
        Row #4: 43
        Row #4: 59.62
        Row #4: 1.83
        Row #4: 168.99
        Row #5: 34
        Row #5: 7.20
        Row #5: 1.83
        Row #5: 20.40
        Row #6: 36
        Row #6: 33.10
        Row #6: 1.83
        Row #6: 93.60
        Row #7: 46
        Row #7: 28.34
        Row #7: 1.81
        Row #7: 79.58
      RESULT
      check_native @olap, mdx, expected_result: expected
    end
  end

  # Java: FilterTest#testNonNativeFilterWithNullMeasure
  it "non-native filter with null measure" do
    with_properties(EnableNativeCrossJoin: true, ExpandNonNative: false, EnableNativeFilter: false) do
      mdx = <<~MDX
        select Filter([Store].[Store Name].members,
                      Not ([Measures].[Store Sqft] - [Measures].[Grocery Sqft] < 10000)) on rows,
        {[Measures].[Store Sqft], [Measures].[Grocery Sqft]} on columns
        from [Store]
      MDX
      expected = <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Store Sqft]}
        {[Measures].[Grocery Sqft]}
        Axis #2:
        {[Store].[Mexico].[DF].[Mexico City].[Store 9]}
        {[Store].[Mexico].[DF].[San Andres].[Store 21]}
        {[Store].[Mexico].[Yucatan].[Merida].[Store 8]}
        {[Store].[USA].[CA].[Alameda].[HQ]}
        {[Store].[USA].[CA].[San Diego].[Store 24]}
        {[Store].[USA].[WA].[Bremerton].[Store 3]}
        {[Store].[USA].[WA].[Tacoma].[Store 17]}
        {[Store].[USA].[WA].[Walla Walla].[Store 22]}
        {[Store].[USA].[WA].[Yakima].[Store 23]}
        Row #0: 36,509
        Row #0: 22,450
        Row #1:
        Row #1:
        Row #2: 30,797
        Row #2: 20,141
        Row #3:
        Row #3:
        Row #4:
        Row #4:
        Row #5: 39,696
        Row #5: 24,390
        Row #6: 33,858
        Row #6: 22,123
        Row #7:
        Row #7:
        Row #8:
        Row #8:
      RESULT
      check_not_native @olap, mdx, expected_result: expected
    end
  end

  # Java: FilterTest#testNativeFilterWithNullMeasure
  # Native filter behaves differently from non-native for null measures.
  it "native filter with null measure" do
    with_properties(EnableNativeCrossJoin: true, EnableNativeFilter: true, ExpandNonNative: false) do
      Mondrian::OLAP::Connection.flush_schema_cache
      connection = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        assert_query_returns connection,
          "select Filter([Store].[Store Name].members, " \
          "              Not ([Measures].[Store Sqft] - [Measures].[Grocery Sqft] < 10000)) on rows, " \
          "{[Measures].[Store Sqft], [Measures].[Grocery Sqft]} on columns " \
          "from [Store]",
          <<~RESULT
            Axis #0:
            {}
            Axis #1:
            {[Measures].[Store Sqft]}
            {[Measures].[Grocery Sqft]}
            Axis #2:
            {[Store].[Mexico].[DF].[Mexico City].[Store 9]}
            {[Store].[Mexico].[Yucatan].[Merida].[Store 8]}
            {[Store].[USA].[WA].[Bremerton].[Store 3]}
            {[Store].[USA].[WA].[Tacoma].[Store 17]}
            Row #0: 36,509
            Row #0: 22,450
            Row #1: 30,797
            Row #1: 20,141
            Row #2: 39,696
            Row #2: 24,390
            Row #3: 33,858
            Row #3: 22,123
          RESULT
      ensure
        connection.close
      end
    end
  end

  # Java: FilterTest#testNonNativeFilterWithCalcMember
  it "non-native filter with calc member" do
    with_properties(EnableNativeCrossJoin: true, EnableNativeFilter: false, ExpandNonNative: false) do
      mdx = <<~MDX
        with
        member [Time].[Time].[Date Range] as 'Aggregate({[Time].[1997].[Q1]:[Time].[1997].[Q4]})'
        select
        {[Measures].[Unit Sales]} ON columns,
        Filter ([Store].[Store State].members, [Measures].[Store Cost] > 100) ON rows
        from [Sales]
        where [Time].[Date Range]
      MDX
      expected = <<~RESULT
        Axis #0:
        {[Time].[Date Range]}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Store].[USA].[CA]}
        {[Store].[USA].[OR]}
        {[Store].[USA].[WA]}
        Row #0: 74,748
        Row #1: 67,659
        Row #2: 124,366
      RESULT
      check_not_native @olap, mdx, expected_result: expected
    end
  end

  # Java: FilterTest#testNativeFilterNonEmpty
  # Verify that filter with Not IsEmpty(storedMeasure) can be natively evaluated.
  it "native filter non-empty" do
    with_properties(EnableNativeCrossJoin: true, ExpandNonNative: false, EnableNativeFilter: true) do
      mdx = <<~MDX
        select Filter(CrossJoin([Store].[Store Name].members,
                                [Store Type].[Store Type].members),
                                Not IsEmpty([Measures].[Store Sqft])) on rows,
        {[Measures].[Store Sqft]} on columns
        from [Store]
      MDX
      check_native @olap, mdx
    end
  end

  # Java: FilterTest#testBugMondrian706
  # Bug MONDRIAN-706: SQL using hierarchy attribute 'Column Name' instead of 'Column' in the filter.
  it "bug Mondrian-706" do
    with_properties(UseAggregates: false, ReadAggregates: false, DisableCaching: false,
                    EnableNativeNonEmpty: true, CompareSiblingsByOrderKey: true,
                    NullDenominatorProducesNull: true, ExpandNonNative: true,
                    EnableNativeCrossJoin: true, EnableNativeFilter: true) do
      olap = connection_with_modified_cube("Store",
        dimensions: <<~XML
          <Dimension name='Store Type'>
              <Hierarchy name='Store Types Hierarchy' allMemberName='All Store Types Member Name' hasAll='true'>
                <Level name='Store Type' column='store_type' uniqueMembers='true'/>
              </Hierarchy>
            </Dimension>
            <Dimension name='Store'>
              <Hierarchy hasAll='true' primaryKey='store_id'>
                <Table name='store'/>
                <Level name='Store Country' column='store_country' uniqueMembers='true'/>
                <Level name='Store State' column='store_state' uniqueMembers='true'/>
                <Level name='Store City' column='store_city' uniqueMembers='false'/>
                <Level name='Store Name' column='store_id' type='Numeric' nameColumn='store_name' uniqueMembers='false'/>
              </Hierarchy>
            </Dimension>
        XML
      )
      begin
        mdx = <<~MDX
          With
          Set [*NATIVE_CJ_SET] as 'Filter([*BASE_MEMBERS_Store], Not IsEmpty ([Measures].[Store Sqft]))'
          Set [*SORTED_ROW_AXIS] as 'Order([*CJ_ROW_AXIS],Ancestor([Store].CurrentMember, [Store].[Store Country]).OrderKey,BASC,Ancestor([Store].CurrentMember, [Store].[Store State]).OrderKey,BASC,Ancestor([Store].CurrentMember,
          [Store].[Store City]).OrderKey,BASC,[Store].CurrentMember.OrderKey,BASC)'
          Set [*NATIVE_MEMBERS_Store] as 'Generate([*NATIVE_CJ_SET], {[Store].CurrentMember})'
          Set [*BASE_MEMBERS_Measures] as '{[Measures].[*FORMATTED_MEASURE_0]}'
          Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Store].currentMember)})'
          Set [*BASE_MEMBERS_Store] as 'Filter([Store].[Store Name].Members,(Ancestor([Store].CurrentMember, [Store].[Store State]) In {[Store].[All Stores].[USA].[CA],[Store].[All Stores].[USA].[OR]}) AND ([Store].CurrentMember In
          {[Store].[All Stores].[USA].[OR].[Portland].[Store 11],[Store].[All Stores].[USA].[CA].[San Francisco].[Store 14]}))'
          Set [*CJ_COL_AXIS] as '[*NATIVE_CJ_SET]'
          Member [Measures].[*FORMATTED_MEASURE_0] as '[Measures].[Store Sqft]', FORMAT_STRING = '#,###', SOLVE_ORDER=400
          Select
          [*BASE_MEMBERS_Measures] on columns,
          [*SORTED_ROW_AXIS] on rows
          From [Store]
        MDX
        assert_query_returns olap, mdx, <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[*FORMATTED_MEASURE_0]}
          Axis #2:
          {[Store].[USA].[CA].[San Francisco].[Store 14]}
          {[Store].[USA].[OR].[Portland].[Store 11]}
          Row #0: 22,478
          Row #1: 20,319
        RESULT
      ensure
        olap.close
      end
    end
  end

  # Java: FilterTest#testBug779
  # MONDRIAN-779: MemberListCrossJoinArg was not considering the 'exclude'
  # attribute in its hash code.
  it "bug 779" do
    with_properties(EnableNativeCrossJoin: true) do
      mdx1 = <<~MDX
        With Set [*NATIVE_CJ_SET] as 'Filter([*BASE_MEMBERS_Product], Not IsEmpty ([Measures].[Unit Sales]))' Set [*BASE_MEMBERS_Product] as 'Filter([Product].[Product Department].Members,(Ancestor([Product].CurrentMember, [Product].[Product Family]) In {[Product].[Drink],[Product].[Food]}) AND ([Product].CurrentMember In {[Product].[Drink].[Dairy]}))' Select [Measures].[Unit Sales] on columns, [*NATIVE_CJ_SET] on rows From [Sales]
      MDX
      expected1 = <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Product].[Drink].[Dairy]}
        Row #0: 4,186
      RESULT

      mdx2 = <<~MDX
        With Set [*NATIVE_CJ_SET] as 'Filter([*BASE_MEMBERS_Product], Not IsEmpty ([Measures].[Unit Sales]))' Set [*BASE_MEMBERS_Product] as 'Filter([Product].[Product Department].Members,(Ancestor([Product].CurrentMember, [Product].[Product Family]) In {[Product].[Drink],[Product].[Food]}) AND ([Product].CurrentMember Not In {[Product].[Drink].[Dairy]}))' Select [Measures].[Unit Sales] on columns, [*NATIVE_CJ_SET] on rows From [Sales]
      MDX
      expected2 = <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Product].[Drink].[Alcoholic Beverages]}
        {[Product].[Drink].[Beverages]}
        {[Product].[Food].[Baked Goods]}
        {[Product].[Food].[Baking Goods]}
        {[Product].[Food].[Breakfast Foods]}
        {[Product].[Food].[Canned Foods]}
        {[Product].[Food].[Canned Products]}
        {[Product].[Food].[Dairy]}
        {[Product].[Food].[Deli]}
        {[Product].[Food].[Eggs]}
        {[Product].[Food].[Frozen Foods]}
        {[Product].[Food].[Meat]}
        {[Product].[Food].[Produce]}
        {[Product].[Food].[Seafood]}
        {[Product].[Food].[Snack Foods]}
        {[Product].[Food].[Snacks]}
        {[Product].[Food].[Starchy Foods]}
        Row #0: 6,838
        Row #1: 13,573
        Row #2: 7,870
        Row #3: 20,245
        Row #4: 3,317
        Row #5: 19,026
        Row #6: 1,812
        Row #7: 12,885
        Row #8: 12,037
        Row #9: 4,132
        Row #10: 26,655
        Row #11: 1,714
        Row #12: 37,792
        Row #13: 1,764
        Row #14: 30,545
        Row #15: 6,884
        Row #16: 5,262
      RESULT

      assert_query_returns @olap, mdx1, expected1
      assert_query_returns @olap, mdx2, expected2
    end
  end

  # Java: FilterTest#testMultiValueInWithNullVals
  # MONDRIAN-1458: Native exclusion predicate must use agg table when checking for nulls.
  # TODO: Only tested on MySQL. Add PostgreSQL SQL pattern or convert to result-based assertion.
  # Also verify that aggregate tables are actually used (query hits agg_g_ms_pcat_sales_fact_1997).
  it "multi value In with null values" do
    skip "SQL pattern test for MySQL only" unless MONDRIAN_DRIVER == "mysql"
    with_properties(EnableNativeCrossJoin: true, ReadAggregates: true, UseAggregates: true) do
      mdx = <<~MDX
        select NonEmptyCrossjoin(
           filter ( product.[product department].members,
              NOT ([Product].CurrentMember IN
          { [Product].[Food].[Baked Goods], Product.Drink.Dairy})),
           gender.gender.members
        )
        on 0 from sales
      MDX
      expected_sql =
        "select `agg_g_ms_pcat_sales_fact_1997`.`product_family` as `c0`, " \
        "`agg_g_ms_pcat_sales_fact_1997`.`product_department` as `c1`, " \
        "`agg_g_ms_pcat_sales_fact_1997`.`gender` as `c2` " \
        "from `agg_g_ms_pcat_sales_fact_1997` as `agg_g_ms_pcat_sales_fact_1997` " \
        "where (not ((`agg_g_ms_pcat_sales_fact_1997`.`product_department`," \
        " `agg_g_ms_pcat_sales_fact_1997`.`product_family`) in " \
        "(('Baked Goods'," \
        " 'Food')," \
        " ('Dairy'," \
        " 'Drink'))) or (`agg_g_ms_pcat_sales_fact_1997`.`product_department` " \
        "is null or `agg_g_ms_pcat_sales_fact_1997`.`product_family` " \
        "is null))"
      Mondrian::OLAP::Connection.flush_schema_cache
      connection = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        queries = capture_sql { connection.execute(mdx) }
        normalized_expected = expected_sql.gsub("\r\n", "\n").strip
        match = queries.any? { |q| q.gsub("\r\n", "\n").include?(normalized_expected) }
        assert match, "Expected SQL not found.\nExpected substring:\n#{normalized_expected}\nCaptured:\n#{queries.to_a.join("\n---\n")}"
      ensure
        connection.close
        Mondrian::OLAP::Connection.flush_schema_cache
      end
    end
  end
end
