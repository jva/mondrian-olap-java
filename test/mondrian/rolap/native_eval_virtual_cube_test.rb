# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2009-2021 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/NativeEvalVirtualCubeTest.java
describe "NativeEvalVirtualCubeTest" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Checks whether query produces the same results with the native.* props
  # enabled as it does with the props disabled.
  # Matches Java BatchTestCase.verifySameNativeAndNot.
  def verify_same_native_and_not(mdx)
    with_properties(
      EnableNativeCrossJoin: true,
      EnableNativeFilter: true,
      EnableNativeNonEmpty: true,
      EnableNativeTopCount: true
    ) do
      result_native = format_result(@olap.execute(mdx))

      with_properties(
        EnableNativeCrossJoin: false,
        EnableNativeFilter: false,
        EnableNativeNonEmpty: false,
        EnableNativeTopCount: false
      ) do
        result_non_native = format_result(@olap.execute(mdx))
        assert_equal result_native, result_non_native
      end
    end
  end

  # Both dims fully join to the applicable base cube.
  # Java: NativeEvalVirtualCubeTest#testSimpleFullyJoiningCJ
  it "simple fully joining crossjoin" do
    mdx = <<~MDX
      select {measures.[unit sales], measures.[warehouse sales]} on 0,
       nonemptycrossjoin( Gender.Gender.members, product.[product category].members) on 1
      from [warehouse and sales]
    MDX
    verify_same_native_and_not(mdx)
  end

  # Java: NativeEvalVirtualCubeTest#testPartiallyJoiningCJ
  it "partially joining crossjoin" do
    mdx = <<~MDX
      select measures.[warehouse sales] on 0,
       NON EMPTY Crossjoin ( Gender.gender.members, product.[product category].members) on 1
       from [warehouse and sales]
    MDX
    verify_same_native_and_not(mdx)
    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Warehouse Sales]}
      Axis #2:
    RESULT
  end

  # Both dims fully join to one of the applicable base cubes.
  # Java: NativeEvalVirtualCubeTest#testOneFullyJoiningCube
  it "one fully joining cube" do
    mdx = <<~MDX
      select {measures.[unit sales], measures.[warehouse sales]} on 0,
       nonemptycrossjoin( Gender.Gender.members, product.[product category].members) on 1
      from [warehouse and sales]
    MDX
    verify_same_native_and_not(mdx)
  end

  # Java: NativeEvalVirtualCubeTest#testNoApplicableCube
  it "no applicable cube" do
    mdx = <<~MDX
      select {measures.[unit sales]} on 0,
       nonemptycrossjoin( Gender.Gender.members, [Warehouse].[All Warehouses].children) on 1
      from [warehouse and sales]
    MDX
    verify_same_native_and_not(mdx)
  end

  # [All Gender] should not impact the nonempty tuple list,
  # even though Gender does not apply to [Warehouse Sales]
  # Java: NativeEvalVirtualCubeTest#testShouldBeFullyJoiningCJ
  it "should be fully joining crossjoin" do
    mdx = <<~MDX
      select measures.[warehouse Sales] on 0,
       nonemptycrossjoin( Gender.[All Gender],
      product.[product category].members) on 1
       from [warehouse and sales]
    MDX
    verify_same_native_and_not(mdx)
  end

  # Java: NativeEvalVirtualCubeTest#testMeasureChangesContextOfInapplicableDimension
  it "measure changes context of inapplicable dimension" do
    mdx = <<~MDX
      with member [Measures].[allW] as
      '([Measures].[Unit Sales], [Warehouse].[All Warehouses])'
      select NON EMPTY Crossjoin(
      [Warehouse].[State Province].[CA], [Product].[All Products].children)
      ON COLUMNS,
      { [Measures].[allW]}
      ON ROWS
      from [Warehouse and Sales]
    MDX
    verify_same_native_and_not(mdx)
  end

  # Java: NativeEvalVirtualCubeTest#testMeasureChangesContextOfApplicableDimension
  it "measure changes context of applicable dimension" do
    mdx = <<~MDX
      with member [Measures].[allW] as
      '([Measures].[Warehouse Sales], [Warehouse].[All Warehouses])'
      select NON EMPTY Crossjoin(
      [Warehouse].[All Warehouses].[USA].Children, [Product].[All Products].children)
      ON COLUMNS,
      { [Measures].[allW]}
      ON ROWS
      from [Warehouse and Sales]
    MDX
    verify_same_native_and_not(mdx)
    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Warehouse].[USA].[CA], [Product].[Drink]}
      {[Warehouse].[USA].[CA], [Product].[Food]}
      {[Warehouse].[USA].[CA], [Product].[Non-Consumable]}
      {[Warehouse].[USA].[OR], [Product].[Drink]}
      {[Warehouse].[USA].[OR], [Product].[Food]}
      {[Warehouse].[USA].[OR], [Product].[Non-Consumable]}
      {[Warehouse].[USA].[WA], [Product].[Drink]}
      {[Warehouse].[USA].[WA], [Product].[Food]}
      {[Warehouse].[USA].[WA], [Product].[Non-Consumable]}
      Axis #2:
      {[Measures].[allW]}
      Row #0: 18,010.602
      Row #0: 141,147.92
      Row #0: 37,612.366
      Row #0: 18,010.602
      Row #0: 141,147.92
      Row #0: 37,612.366
      Row #0: 18,010.602
      Row #0: 141,147.92
      Row #0: 37,612.366
    RESULT
  end

  # Java: NativeEvalVirtualCubeTest#testNECJWithValidMeasureAndInapplicableDimension
  it "NECJ with valid measure and inapplicable dimension" do
    mdx = <<~MDX
      with member [Measures].[validUS] as
      'ValidMeasure([Measures].[Unit Sales])'
      select NON EMPTY Crossjoin(
      {[Warehouse].[USA].children}, [Product].[All Products].children)
      ON COLUMNS,
      { [Measures].[validUS]}
      ON ROWS
      from [Warehouse and Sales]
    MDX
    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Warehouse].[USA].[CA], [Product].[Drink]}
      {[Warehouse].[USA].[CA], [Product].[Food]}
      {[Warehouse].[USA].[CA], [Product].[Non-Consumable]}
      {[Warehouse].[USA].[OR], [Product].[Drink]}
      {[Warehouse].[USA].[OR], [Product].[Food]}
      {[Warehouse].[USA].[OR], [Product].[Non-Consumable]}
      {[Warehouse].[USA].[WA], [Product].[Drink]}
      {[Warehouse].[USA].[WA], [Product].[Food]}
      {[Warehouse].[USA].[WA], [Product].[Non-Consumable]}
      Axis #2:
      {[Measures].[validUS]}
      Row #0: 24,597
      Row #0: 191,940
      Row #0: 50,236
      Row #0: 24,597
      Row #0: 191,940
      Row #0: 50,236
      Row #0: 24,597
      Row #0: 191,940
      Row #0: 50,236
    RESULT
  end

  # No fully joining dimensions.
  # Java: NativeEvalVirtualCubeTest#testDisjointDimensionCJ
  it "disjoint dimension crossjoin" do
    mdx = <<~MDX
      with member measures.vmWS as 'ValidMeasure(measures.[Warehouse Sales])'
       select NON EMPTY Crossjoin(
      {[Warehouse].[State Province].members}, {Gender.[All Gender].children} )
      ON COLUMNS,
      { [Measures].[Unit Sales], Measures.[vmWS] }
      ON ROWS
      from [Warehouse and Sales]
    MDX
    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Warehouse].[USA].[CA], [Gender].[F]}
      {[Warehouse].[USA].[CA], [Gender].[M]}
      {[Warehouse].[USA].[OR], [Gender].[F]}
      {[Warehouse].[USA].[OR], [Gender].[M]}
      {[Warehouse].[USA].[WA], [Gender].[F]}
      {[Warehouse].[USA].[WA], [Gender].[M]}
      Axis #2:
      {[Measures].[Unit Sales]}
      {[Measures].[vmWS]}
      Row #0:
      Row #0:
      Row #0:
      Row #0:
      Row #0:
      Row #0:
      Row #1: 57,814.858
      Row #1: 57,814.858
      Row #1: 38,835.053
      Row #1: 38,835.053
      Row #1: 100,120.976
      Row #1: 100,120.976
    RESULT
  end

  # Java: NativeEvalVirtualCubeTest#testWarehouseForcedToAllLevel
  it "Warehouse forced to all level" do
    mdx = <<~MDX
      with member [Measures].[validUS] as
      'ValidMeasure([Measures].[Unit Sales])'
      select NON EMPTY Crossjoin(
      {[Warehouse].[State Province].[CA],[Warehouse].[State Province].[WA]}, [Product].[All Products].children)
      ON COLUMNS,
      { [Measures].[validUS]}
      ON ROWS
      from [Warehouse and Sales]
    MDX
    verify_same_native_and_not(mdx)
  end

  # Java: NativeEvalVirtualCubeTest#testMdxCJOfApplicableAndNonApplicable
  it "MDX crossjoin of applicable and non-applicable" do
    mdx = <<~MDX
      WITH
      MEMBER Measures.[ValidM Unit Sales] as 'ValidMeasure([Measures].[Unit Sales])'
      SET [*NATIVE_CJ_SET_WITH_SLICER] AS 'NONEMPTYCROSSJOIN([*BASE_MEMBERS__Warehouse_],[*BASE_MEMBERS__Gender_])'
      SET [*NATIVE_CJ_SET] AS '[*NATIVE_CJ_SET_WITH_SLICER]'
      SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],[Warehouse].CURRENTMEMBER.ORDERKEY,BASC,ANCESTOR([Warehouse].CURRENTMEMBER,[Warehouse].[Country]).ORDERKEY,BASC,[Gender].CURRENTMEMBER.ORDERKEY,BASC)'
      SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[ValidM Unit Sales]}'
      SET [*BASE_MEMBERS__Gender_] AS '[Gender].[Gender].MEMBERS'
      SET [*BASE_MEMBERS__Warehouse_] AS '[Warehouse].[USA].Children'
      SET [*CJ_ROW_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Warehouse].CURRENTMEMBER,[Gender].CURRENTMEMBER)})'
      SELECT
      [*BASE_MEMBERS__Measures_] ON COLUMNS
      ,NON EMPTY
      [*SORTED_ROW_AXIS] ON ROWS
      FROM [Warehouse and Sales]
    MDX
    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Measures].[ValidM Unit Sales]}
      Axis #2:
      {[Warehouse].[USA].[CA], [Gender].[F]}
      {[Warehouse].[USA].[CA], [Gender].[M]}
      {[Warehouse].[USA].[OR], [Gender].[F]}
      {[Warehouse].[USA].[OR], [Gender].[M]}
      {[Warehouse].[USA].[WA], [Gender].[F]}
      {[Warehouse].[USA].[WA], [Gender].[M]}
      Row #0: 131,558
      Row #1: 135,215
      Row #2: 131,558
      Row #3: 135,215
      Row #4: 131,558
      Row #5: 135,215
    RESULT
  end

  # Java: NativeEvalVirtualCubeTest#testAllMemberTupleInapplicableDim
  it "all member tuple with inapplicable dimension" do
    mdx = <<~MDX
      WITH
      SET [*NATIVE_CJ_SET_WITH_SLICER] AS 'NONEMPTYCROSSJOIN([*BASE_MEMBERS__Warehouse_],[*BASE_MEMBERS__Gender_])'
      SET [*NATIVE_CJ_SET] AS '[*NATIVE_CJ_SET_WITH_SLICER]'
      SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],[Warehouse].CURRENTMEMBER.ORDERKEY,BASC,ANCESTOR([Warehouse].CURRENTMEMBER,[Warehouse].[Country]).ORDERKEY,BASC,[Gender].CURRENTMEMBER.ORDERKEY,BASC)'
      SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0],[Measures].[*CALCULATED_MEASURE_1]}'
      SET [*BASE_MEMBERS__Gender_] AS '[Gender].[Gender].MEMBERS'
      SET [*BASE_MEMBERS__Warehouse_] AS '[Warehouse].[USA].Children'
      SET [*CJ_ROW_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Warehouse].CURRENTMEMBER,[Gender].CURRENTMEMBER)})'
      MEMBER [Measures].[*CALCULATED_MEASURE_1] AS '( [Warehouse].[All Warehouses], [Measures].[Unit Sales] )', SOLVE_ORDER=0
      MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=500
      SELECT
      [*BASE_MEMBERS__Measures_] ON COLUMNS
      ,NON EMPTY
      [*SORTED_ROW_AXIS] ON ROWS
      FROM [Warehouse and Sales]
    MDX
    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Measures].[*FORMATTED_MEASURE_0]}
      {[Measures].[*CALCULATED_MEASURE_1]}
      Axis #2:
      {[Warehouse].[USA].[CA], [Gender].[F]}
      {[Warehouse].[USA].[CA], [Gender].[M]}
      {[Warehouse].[USA].[OR], [Gender].[F]}
      {[Warehouse].[USA].[OR], [Gender].[M]}
      {[Warehouse].[USA].[WA], [Gender].[F]}
      {[Warehouse].[USA].[WA], [Gender].[M]}
      Row #0:
      Row #0: 131,558
      Row #1:
      Row #1: 135,215
      Row #2:
      Row #2: 131,558
      Row #3:
      Row #3: 135,215
      Row #4:
      Row #4: 131,558
      Row #5:
      Row #5: 135,215
    RESULT
  end

  # Crossjoin places intermixed applicable and inapplicable
  # attributes, which verifies that the projected crossjoin is in the correct
  # order, even though the components may not be evaluated together.
  # (In this case gender and marital status are natively evaluated in a cj,
  # with warehouse evaluated in a separate group. The sets need to be
  # reassembled and projected correctly.)
  # Java: NativeEvalVirtualCubeTest#testIntermixedDimensionGroupings
  it "intermixed dimension groupings" do
    mdx = <<~MDX
      with member measures.vmUS as 'ValidMeasure(Measures.[Unit Sales])'
      select non empty crossjoin(crossjoin(gender.gender.members, warehouse.[USA].[CA]), [marital status].[marital status].members) on 0,
       measures.vmUS on 1 from [warehouse and sales]
    MDX
    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Gender].[F], [Warehouse].[USA].[CA], [Marital Status].[M]}
      {[Gender].[F], [Warehouse].[USA].[CA], [Marital Status].[S]}
      {[Gender].[M], [Warehouse].[USA].[CA], [Marital Status].[M]}
      {[Gender].[M], [Warehouse].[USA].[CA], [Marital Status].[S]}
      Axis #2:
      {[Measures].[vmUS]}
      Row #0: 65,336
      Row #0: 66,222
      Row #0: 66,460
      Row #0: 68,755
    RESULT
  end

  # First query doesn't use a measure like ValidMeasure, so results in an
  # empty tuples set being cached. The second query should not reuse the
  # cache results from the first query, since it *does* use VM.
  # Java: NativeEvalVirtualCubeTest#testCachedShouldNotBeUsed
  it "cached should not be used" do
    @olap.execute(
      "select non empty crossjoin(gender.gender.members, warehouse.[USA].[CA]) on 0, " \
      "measures.[unit sales] on 1 from [warehouse and sales]"
    )
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with member measures.vm as 'validmeasure(measures.[unit sales])'
      select non empty crossjoin(gender.gender.members, warehouse.[USA].[CA]) on 0,
      measures.vm on 1 from [warehouse and sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Gender].[F], [Warehouse].[USA].[CA]}
      {[Gender].[M], [Warehouse].[USA].[CA]}
      Axis #2:
      {[Measures].[vm]}
      Row #0: 131,558
      Row #0: 135,215
    RESULT
  end

  # Verify cache does get used for applicable grouped target tuple queries.
  # SQL-specific test: only runs on MySQL.
  # Java: NativeEvalVirtualCubeTest#testShouldUseCache
  it "should use cache" do
    skip "MySQL-specific SQL pattern test" unless MONDRIAN_DRIVER == "mysql"

    mysql_gender_query = <<~SQL.chomp
      select
          `customer`.`gender` as `c0`
      from
          `customer` as `customer`,
          `sales_fact_1997` as `sales_fact_1997`
      where
          `sales_fact_1997`.`customer_id` = `customer`.`customer_id`
      group by
          `customer`.`gender`
      order by
          ISNULL(`c0`) ASC, `c0` ASC
    SQL

    mdx = <<~MDX
      with member measures.vm as 'validmeasure(measures.[unit sales])'
      select non empty
      crossjoin(gender.gender.members, warehouse.[USA].[CA]) on 0,
      measures.vm on 1 from [warehouse and sales]
    MDX

    with_properties(GenerateFormattedSql: true) do
      # First MDX with a fresh connection should result in gender query
      Mondrian::OLAP::Connection.flush_schema_cache
      connection = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        first_queries = capture_sql { connection.execute(mdx) }
        normalized_expected = mysql_gender_query.gsub("\r\n", "\n").strip
        found_first = first_queries.any? { |q| q.gsub("\r\n", "\n").include?(normalized_expected) }
        assert found_first,
          "Expected gender SQL in first execution.\nExpected:\n#{normalized_expected}\nCaptured:\n#{first_queries.to_a.join("\n---\n")}"

        # Rerun the MDX, since the previous capture completes execution
        connection.execute(mdx)

        # Subsequent query should pull from cache, not rerun gender query
        second_queries = capture_sql { connection.execute(mdx) }
        found_second = second_queries.any? { |q| q.gsub("\r\n", "\n").include?(normalized_expected) }
        refute found_second,
          "Gender SQL should not appear in second execution (should be cached).\nCaptured:\n#{second_queries.to_a.join("\n---\n")}"
      ensure
        connection&.close
      end
    end
  end

  # Testcase for bug MONDRIAN-2597:
  # "readTuples and cardinality queries sent twice to the database
  # when using Virtual Cube (Not cached)".
  # SQL-specific test: only runs on MySQL.
  # Java: NativeEvalVirtualCubeTest#testTupleQueryShouldBeCachedForVirtualCube
  it "tuple query should be cached for virtual cube" do
    skip "MySQL-specific SQL pattern test" unless MONDRIAN_DRIVER == "mysql"

    mysql_members_query = <<~SQL.chomp
      select
          *
      from
          (select
          `product_class`.`product_family` as `c0`,
          `product_class`.`product_department` as `c1`,
          `time_by_day`.`the_year` as `c2`
      from
          `product` as `product`,
          `product_class` as `product_class`,
          `sales_fact_1997` as `sales_fact_1997`,
          `time_by_day` as `time_by_day`
      where
          `product`.`product_class_id` = `product_class`.`product_class_id`
      and
          `sales_fact_1997`.`product_id` = `product`.`product_id`
      and
          `sales_fact_1997`.`time_id` = `time_by_day`.`time_id`
      group by
          `product_class`.`product_family`,
          `product_class`.`product_department`,
          `time_by_day`.`the_year`
      union
      select
          `product_class`.`product_family` as `c0`,
          `product_class`.`product_department` as `c1`,
          `time_by_day`.`the_year` as `c2`
      from
          `product` as `product`,
          `product_class` as `product_class`,
          `inventory_fact_1997` as `inventory_fact_1997`,
          `time_by_day` as `time_by_day`
      where
          `product`.`product_class_id` = `product_class`.`product_class_id`
      and
          `inventory_fact_1997`.`product_id` = `product`.`product_id`
      and
          `inventory_fact_1997`.`time_id` = `time_by_day`.`time_id`
      group by
          `product_class`.`product_family`,
          `product_class`.`product_department`,
          `time_by_day`.`the_year`) as `unionQuery`
      order by
          ISNULL(1) ASC, 1 ASC,
          ISNULL(2) ASC, 2 ASC,
          ISNULL(3) ASC, 3 ASC
    SQL

    # The MDX with default measure of [Warehouse and Sales] virtual cube:
    # Store Sales that belongs to the regular [Sales] cube
    mdx = <<~MDX
      WITH
      SET [*NATIVE_CJ_SET] AS 'NONEMPTYCROSSJOIN([*BASE_MEMBERS__Product_],[*BASE_MEMBERS__Time_])'
      SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],ANCESTOR([Product].CURRENTMEMBER, [Product].[Product Family]).ORDERKEY,BASC,[Product].CURRENTMEMBER.ORDERKEY,BASC,[Time].CURRENTMEMBER.ORDERKEY,BASC)'
      SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'
      SET [*BASE_MEMBERS__Product_] AS '[Product].[Product Department].MEMBERS'
      SET [*BASE_MEMBERS__Time_] AS '[Time].[Year].MEMBERS'
      SET [*CJ_ROW_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Product].CURRENTMEMBER,[Time].CURRENTMEMBER)})'
      MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Store Sales]', FORMAT_STRING = '#,###.00', SOLVE_ORDER=500
      SELECT
      [*BASE_MEMBERS__Measures_] ON COLUMNS
      , NON EMPTY
      [*SORTED_ROW_AXIS] ON ROWS
      FROM [Warehouse and Sales]
    MDX

    # The MDX with added Warehouse Sales measure
    # that belongs to the regular [Warehouse] cube
    mdx_warehouse = <<~MDX
      WITH
      SET [*NATIVE_CJ_SET] AS 'NONEMPTYCROSSJOIN([*BASE_MEMBERS__Product_],[*BASE_MEMBERS__Time_])'
      SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],ANCESTOR([Product].CURRENTMEMBER, [Product].[Product Family]).ORDERKEY,BASC,[Product].CURRENTMEMBER.ORDERKEY,BASC,[Time].CURRENTMEMBER.ORDERKEY,BASC)'
      SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[Warehouse Sales]}'
      SET [*BASE_MEMBERS__Product_] AS '[Product].[Product Department].MEMBERS'
      SET [*BASE_MEMBERS__Time_] AS '[Time].[Year].MEMBERS'
      SET [*CJ_ROW_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Product].CURRENTMEMBER,[Time].CURRENTMEMBER)})'
      SELECT
      [*BASE_MEMBERS__Measures_] ON COLUMNS
      , NON EMPTY
      [*SORTED_ROW_AXIS] ON ROWS
      FROM [Warehouse and Sales]
    MDX

    with_properties(GenerateFormattedSql: true) do
      Mondrian::OLAP::Connection.flush_schema_cache
      connection = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        normalized_expected = mysql_members_query.gsub("\r\n", "\n").strip

        # First MDX with a fresh query should result in product_family,
        # product_department and the_year query.
        first_queries = capture_sql { connection.execute(mdx) }
        found_first = first_queries.any? { |q| q.gsub("\r\n", "\n").include?(normalized_expected) }
        assert found_first,
          "Expected members SQL in first execution.\nExpected:\n#{normalized_expected}\nCaptured:\n#{first_queries.to_a.join("\n---\n")}"

        # Rerun the MDX, since the previous capture completes execution
        connection.execute(mdx)

        # Subsequent query should pull from cache, not rerun the query
        second_queries = capture_sql { connection.execute(mdx) }
        found_second = second_queries.any? { |q| q.gsub("\r\n", "\n").include?(normalized_expected) }
        refute found_second,
          "Members SQL should not appear in second execution (should be cached).\nCaptured:\n#{second_queries.to_a.join("\n---\n")}"

        # Subsequent query with Warehouse Sales measure should also pull from cache
        warehouse_queries = capture_sql { connection.execute(mdx_warehouse) }
        found_warehouse = warehouse_queries.any? { |q| q.gsub("\r\n", "\n").include?(normalized_expected) }
        refute found_warehouse,
          "Members SQL should not appear in warehouse measure execution (should be cached).\nCaptured:\n#{warehouse_queries.to_a.join("\n---\n")}"
      ensure
        connection&.close
      end
    end
  end
end
