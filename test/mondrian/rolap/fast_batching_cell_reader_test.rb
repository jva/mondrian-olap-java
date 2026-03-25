# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2021 Hitachi Vantara.  All rights reserved.
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/FastBatchingCellReaderTest.java
describe "FastBatchingCellReader" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Java: FastBatchingCellReaderTest#testMissingSubtotalBugMetricFilter
  it "missing subtotal bug metric filter" do
    assert_query_returns @olap, <<~MDX.chomp, <<~RESULT
      With
      Set [*NATIVE_CJ_SET] as
        'NonEmptyCrossJoin({[Time].[Year].[1997]},
          NonEmptyCrossJoin({[Product].[All Products].[Drink]},
            {[Education Level].[All Education Levels].[Bachelors Degree]}))'
      Set [*METRIC_CJ_SET] as
        'Filter([*NATIVE_CJ_SET],[Measures].[*Unit Sales_SEL~SUM] > 1000.0)'
      Set [*METRIC_MEMBERS_Education Level] as
        'Generate([*METRIC_CJ_SET], {[Education Level].CurrentMember})'
      Member [Measures].[*Unit Sales_SEL~SUM] as
        '([Measures].[Unit Sales],[Time].[Time].CurrentMember,[Product].CurrentMember,[Education Level].CurrentMember)',
        SOLVE_ORDER=200
      Member [Education Level].[*CTX_MEMBER_SEL~SUM] as
        'Sum(Filter([*METRIC_MEMBERS_Education Level],[Measures].[*Unit Sales_SEL~SUM] > 1000.0))',
        SOLVE_ORDER=-102
      Select
      {[Measures].[Unit Sales]} on columns,
      Non Empty Union(
        CrossJoin(
          Generate([*METRIC_CJ_SET], {([Time].[Time].CurrentMember,[Product].CurrentMember)}),
          {[Education Level].[*CTX_MEMBER_SEL~SUM]}),
        Generate([*METRIC_CJ_SET], {([Time].[Time].CurrentMember,[Product].CurrentMember,[Education Level].CurrentMember)}))
      on rows
      From [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Time].[1997], [Product].[Drink], [Education Level].[*CTX_MEMBER_SEL~SUM]}
      {[Time].[1997], [Product].[Drink], [Education Level].[Bachelors Degree]}
      Row #0: 6,423
      Row #1: 6,423
    RESULT
  end

  # Java: FastBatchingCellReaderTest#testMissingSubtotalBugMultiLevelMetricFilter
  it "missing subtotal bug multi level metric filter" do
    assert_query_returns @olap, <<~MDX.chomp, <<~RESULT
      With
      Set [*NATIVE_CJ_SET] as
        'NonEmptyCrossJoin([*BASE_MEMBERS_Product],[*BASE_MEMBERS_Education Level])'
      Set [*METRIC_CJ_SET] as
        'Filter([*NATIVE_CJ_SET],[Measures].[*Store Cost_SEL~SUM] > 1000.0)'
      Set [*BASE_MEMBERS_Product] as
        '{[Product].[All Products].[Drink].[Beverages],[Product].[All Products].[Food].[Baked Goods]}'
      Set [*METRIC_MEMBERS_Product] as
        'Generate([*METRIC_CJ_SET], {[Product].CurrentMember})'
      Set [*BASE_MEMBERS_Education Level] as
        '{[Education Level].[All Education Levels].[High School Degree],[Education Level].[All Education Levels].[Partial High School]}'
      Set [*METRIC_MEMBERS_Education Level] as
        'Generate([*METRIC_CJ_SET], {[Education Level].CurrentMember})'
      Member [Measures].[*Store Cost_SEL~SUM] as
        '([Measures].[Store Cost],[Product].CurrentMember,[Education Level].CurrentMember)',
        SOLVE_ORDER=200
      Member [Product].[Drink].[*CTX_MEMBER_SEL~SUM] as
        'Sum(Filter([*METRIC_MEMBERS_Product],[Product].CurrentMember.Parent = [Product].[All Products].[Drink]))',
        SOLVE_ORDER=-100
      Member [Product].[Food].[*CTX_MEMBER_SEL~SUM] as
        'Sum(Filter([*METRIC_MEMBERS_Product],[Product].CurrentMember.Parent = [Product].[All Products].[Food]))',
        SOLVE_ORDER=-100
      Member [Education Level].[*CTX_MEMBER_SEL~SUM] as
        'Sum(Filter([*METRIC_MEMBERS_Education Level],[Measures].[*Store Cost_SEL~SUM] > 1000.0))',
        SOLVE_ORDER=-101
      Select
      {[Measures].[Store Cost]} on columns,
      NonEmptyCrossJoin(
        {[Product].[Drink].[*CTX_MEMBER_SEL~SUM],[Product].[Food].[*CTX_MEMBER_SEL~SUM]},
        {[Education Level].[*CTX_MEMBER_SEL~SUM]})
      on rows
      From [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Store Cost]}
      Axis #2:
      {[Product].[Drink].[*CTX_MEMBER_SEL~SUM], [Education Level].[*CTX_MEMBER_SEL~SUM]}
      {[Product].[Food].[*CTX_MEMBER_SEL~SUM], [Education Level].[*CTX_MEMBER_SEL~SUM]}
      Row #0: 6,535.30
      Row #1: 3,860.89
    RESULT
  end

  # Java: FastBatchingCellReaderTest#testAggregateDistinctCount
  it "aggregate distinct count" do
    # solve_order=1 says to aggregate [CA] and [OR] before computing their sums
    assert_query_returns @olap, <<~MDX.chomp, <<~RESULT
      WITH MEMBER [Time].[Time].[1997 Q1 plus Q2] AS
        'AGGREGATE({[Time].[1997].[Q1], [Time].[1997].[Q2]})', solve_order=1
      SELECT {[Measures].[Customer Count]} ON COLUMNS,
        {[Time].[1997].[Q1], [Time].[1997].[Q2], [Time].[1997 Q1 plus Q2]} ON ROWS
      FROM Sales
      WHERE ([Store].[USA].[CA])
    MDX
      Axis #0:
      {[Store].[USA].[CA]}
      Axis #1:
      {[Measures].[Customer Count]}
      Axis #2:
      {[Time].[1997].[Q1]}
      {[Time].[1997].[Q2]}
      {[Time].[1997 Q1 plus Q2]}
      Row #0: 1,110
      Row #1: 1,173
      Row #2: 1,854
    RESULT
  end

  # Java: FastBatchingCellReaderTest#testAggregateDistinctCount2
  it "aggregate distinct count with members from different levels" do
    assert_query_returns @olap, <<~MDX.chomp, <<~RESULT
      WITH MEMBER [Time].[Time].[1997 Q1 plus July] AS
        'AGGREGATE({[Time].[1997].[Q1], [Time].[1997].[Q3].[7]})', solve_order=1
      SELECT {[Measures].[Unit Sales], [Measures].[Customer Count]} ON COLUMNS,
        {[Time].[1997].[Q1],
         [Time].[1997].[Q2],
         [Time].[1997].[Q3].[7],
         [Time].[1997 Q1 plus July]} ON ROWS
      FROM Sales
      WHERE ([Store].[USA].[CA])
    MDX
      Axis #0:
      {[Store].[USA].[CA]}
      Axis #1:
      {[Measures].[Unit Sales]}
      {[Measures].[Customer Count]}
      Axis #2:
      {[Time].[1997].[Q1]}
      {[Time].[1997].[Q2]}
      {[Time].[1997].[Q3].[7]}
      {[Time].[1997 Q1 plus July]}
      Row #0: 16,890
      Row #0: 1,110
      Row #1: 18,052
      Row #1: 1,173
      Row #2: 5,403
      Row #2: 412
      Row #3: 22,293
      Row #3: 1,386
    RESULT
  end

  # Java: FastBatchingCellReaderTest#testAggregateDistinctCount3
  it "aggregate distinct count with two calc members" do
    # FIXME: assertQuerySql also fails in Java on MySQL (failsafe report confirms).
    assert_query_returns @olap, <<~MDX.chomp, <<~RESULT
      WITH
        MEMBER [Promotion Media].[TV plus Radio] AS
          'AGGREGATE({[Promotion Media].[TV], [Promotion Media].[Radio]})', solve_order=1
        MEMBER [Time].[Time].[1997 Q1 plus July] AS
          'AGGREGATE({[Time].[1997].[Q1], [Time].[1997].[Q3].[7]})', solve_order=1
      SELECT {[Promotion Media].[TV plus Radio],
              [Promotion Media].[TV],
              [Promotion Media].[Radio]} ON COLUMNS,
             {[Time].[1997],
              [Time].[1997].[Q1],
              [Time].[1997 Q1 plus July]} ON ROWS
      FROM Sales
      WHERE [Measures].[Customer Count]
    MDX
      Axis #0:
      {[Measures].[Customer Count]}
      Axis #1:
      {[Promotion Media].[TV plus Radio]}
      {[Promotion Media].[TV]}
      {[Promotion Media].[Radio]}
      Axis #2:
      {[Time].[1997]}
      {[Time].[1997].[Q1]}
      {[Time].[1997 Q1 plus July]}
      Row #0: 455
      Row #0: 274
      Row #0: 186
      Row #1: 139
      Row #1: 99
      Row #1: 40
      Row #2: 139
      Row #2: 99
      Row #2: 40
    RESULT

    sql_mdx = <<~MDX
      WITH
        MEMBER [Promotion Media].[TV plus Radio] AS
          'AGGREGATE({[Promotion Media].[TV], [Promotion Media].[Radio]})', solve_order=1
        MEMBER [Time].[Time].[1997 Q1 plus July] AS
          'AGGREGATE({[Time].[1997].[Q1], [Time].[1997].[Q3].[7]})', solve_order=1
      SELECT {[Promotion Media].[TV plus Radio],
              [Promotion Media].[TV],
              [Promotion Media].[Radio]} ON COLUMNS,
             {[Time].[1997],
              [Time].[1997].[Q1],
              [Time].[1997 Q1 plus July]} ON ROWS
      FROM Sales
      WHERE [Measures].[Customer Count]
    MDX
    assert_query_sql @olap, sql_mdx,
      "mysql" => "select `time_by_day`.`the_year` as `c0`, `time_by_day`.`quarter` as `c1`, " \
        "`promotion`.`media_type` as `c2`, count(distinct `sales_fact_1997`.`customer_id`) as `m0` " \
        "from `time_by_day` as `time_by_day`, `sales_fact_1997` as `sales_fact_1997`, " \
        "`promotion` as `promotion` " \
        "where `sales_fact_1997`.`time_id` = `time_by_day`.`time_id` and " \
        "`time_by_day`.`the_year` = 1997 and `time_by_day`.`quarter` = 'Q1' and " \
        "`sales_fact_1997`.`promotion_id` = `promotion`.`promotion_id` and " \
        "`promotion`.`media_type` in ('Radio', 'TV') " \
        "group by `time_by_day`.`the_year`, `time_by_day`.`quarter`, `promotion`.`media_type`"
  end

  # Java: FastBatchingCellReaderTest#testAggregateDistinctCount4
  it "aggregate distinct count with overlapping members" do
    # CA and USA are overlapping members
    assert_query_returns @olap, <<~MDX.chomp, <<~RESULT
      WITH
        MEMBER [Store].[CA plus USA] AS
          'AGGREGATE({[Store].[USA].[CA], [Store].[USA]})', solve_order=1
        MEMBER [Time].[Time].[Q1 plus July] AS
          'AGGREGATE({[Time].[1997].[Q1], [Time].[1997].[Q3].[7]})', solve_order=1
      SELECT {[Measures].[Customer Count], [Measures].[Unit Sales]} ON COLUMNS,
        Union({[Store].[CA plus USA]} * {[Time].[Q1 plus July]},
        Union({[Store].[USA].[CA]} * {[Time].[Q1 plus July]},
        Union({[Store].[USA]} * {[Time].[Q1 plus July]},
        Union({[Store].[CA plus USA]} * {[Time].[1997].[Q1]},
              {[Store].[CA plus USA]} * {[Time].[1997].[Q3].[7]})))) ON ROWS
      FROM Sales
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Customer Count]}
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[CA plus USA], [Time].[Q1 plus July]}
      {[Store].[USA].[CA], [Time].[Q1 plus July]}
      {[Store].[USA], [Time].[Q1 plus July]}
      {[Store].[CA plus USA], [Time].[1997].[Q1]}
      {[Store].[CA plus USA], [Time].[1997].[Q3].[7]}
      Row #0: 3,505
      Row #0: 112,347
      Row #1: 1,386
      Row #1: 22,293
      Row #2: 3,505
      Row #2: 90,054
      Row #3: 2,981
      Row #3: 83,181
      Row #4: 1,462
      Row #4: 29,166
    RESULT
  end

  # Java: FastBatchingCellReaderTest#testAggregateDistinctCount5
  it "aggregate distinct count with aggregate in slicer" do
    # FIXME: assertQuerySql also fails in Java on MySQL (failsafe report confirms).
    # Java test only asserts SQL patterns. We additionally verify query results.
    mdx = <<~MDX
      With
      Set [Products] as
        '{[Product].[Drink],
          [Product].[Food],
          [Product].[Non-Consumable]}'
      Member [Product].[Selected Products] as
        'Aggregate([Products])', SOLVE_ORDER=2
      Select
        {[Store].[Store State].Members} on rows,
        {[Measures].[Customer Count]} on columns
      From [Sales]
      Where ([Product].[Selected Products])
    MDX

    with_properties(MaxConstraints: 2) do
      assert_query_returns @olap, mdx.chomp, <<~RESULT
        Axis #0:
        {[Product].[Selected Products]}
        Axis #1:
        {[Measures].[Customer Count]}
        Axis #2:
        {[Store].[Canada].[BC]}
        {[Store].[Mexico].[DF]}
        {[Store].[Mexico].[Guerrero]}
        {[Store].[Mexico].[Jalisco]}
        {[Store].[Mexico].[Veracruz]}
        {[Store].[Mexico].[Yucatan]}
        {[Store].[Mexico].[Zacatecas]}
        {[Store].[USA].[CA]}
        {[Store].[USA].[OR]}
        {[Store].[USA].[WA]}
        Row #0:
        Row #1:
        Row #2:
        Row #3:
        Row #4:
        Row #5:
        Row #6:
        Row #7: 2,716
        Row #8: 1,037
        Row #9: 1,828
      RESULT

      assert_query_sql @olap, mdx,
        "mysql" => "select `store`.`store_state` as `c0`, `time_by_day`.`the_year` as `c1`, " \
          "count(distinct `sales_fact_1997`.`customer_id`) as `m0` " \
          "from `store` as `store`, `sales_fact_1997` as `sales_fact_1997`, " \
          "`time_by_day` as `time_by_day` " \
          "where `sales_fact_1997`.`store_id` = `store`.`store_id` " \
          "and `sales_fact_1997`.`time_id` = `time_by_day`.`time_id` " \
          "and `time_by_day`.`the_year` = 1997 " \
          "group by `store`.`store_state`, `time_by_day`.`the_year`"
    end
  end

  # Java: FastBatchingCellReaderTest#testAggregateDistinctCount6
  it "aggregate distinct count with multiple levels in same hierarchy" do
    # CA and USA are overlapping members
    assert_query_returns @olap, <<~MDX.chomp, <<~RESULT
      WITH
        MEMBER [Store].[Select Region] AS
          'AGGREGATE({[Store].[USA].[CA], [Store].[Mexico], [Store].[Canada], [Store].[USA].[OR]})', solve_order=1
        MEMBER [Time].[Time].[Select Time Period] AS
          'AGGREGATE({[Time].[1997].[Q1], [Time].[1997].[Q3].[7], [Time].[1997].[Q4], [Time].[1997]})', solve_order=1
      SELECT {[Measures].[Customer Count], [Measures].[Unit Sales]} ON COLUMNS,
        Union({[Store].[Select Region]} * {[Time].[Select Time Period]},
        Union({[Store].[Select Region]} * {[Time].[1997].[Q1]},
        Union({[Store].[Select Region]} * {[Time].[1997].[Q3].[7]},
        Union({[Store].[Select Region]} * {[Time].[1997].[Q4]},
              {[Store].[Select Region]} * {[Time].[1997]}))))
      ON ROWS
      FROM Sales
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Customer Count]}
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[Select Region], [Time].[Select Time Period]}
      {[Store].[Select Region], [Time].[1997].[Q1]}
      {[Store].[Select Region], [Time].[1997].[Q3].[7]}
      {[Store].[Select Region], [Time].[1997].[Q4]}
      {[Store].[Select Region], [Time].[1997]}
      Row #0: 3,753
      Row #0: 229,496
      Row #1: 1,877
      Row #1: 36,177
      Row #2: 845
      Row #2: 13,123
      Row #3: 2,073
      Row #3: 37,789
      Row #4: 3,753
      Row #4: 142,407
    RESULT
  end

  # Java: FastBatchingCellReaderTest#testDistinctCountBug1785406
  it "distinct count bug 1785406" do
    # FIXME: assertQuerySql also fails in Java on MySQL (failsafe report confirms).
    mdx = <<~MDX
      With
      Set [*BASE_MEMBERS_Product] as {[Product].[All Products].[Food].[Deli]}
      Set [*BASE_MEMBERS_Store] as {[Store].[All Stores].[USA].[WA]}
      Member [Product].[*CTX_MEMBER_SEL~SUM] As Aggregate([*BASE_MEMBERS_Product])
      Select
      {[Measures].[Customer Count]} on columns,
      NonEmptyCrossJoin([*BASE_MEMBERS_Store],{([Product].[*CTX_MEMBER_SEL~SUM])})
      on rows
      From [Sales]
      where ([Time].[1997])
    MDX
    assert_query_returns @olap, mdx.chomp, <<~RESULT
      Axis #0:
      {[Time].[1997]}
      Axis #1:
      {[Measures].[Customer Count]}
      Axis #2:
      {[Store].[USA].[WA], [Product].[*CTX_MEMBER_SEL~SUM]}
      Row #0: 889
    RESULT

    assert_query_sql @olap, mdx,
      "mysql" => "select `store`.`store_state` as `c0`, `time_by_day`.`the_year` as `c1`, " \
        "count(distinct `sales_fact_1997`.`customer_id`) as `m0` " \
        "from `store` as `store`, `sales_fact_1997` as `sales_fact_1997`, " \
        "`time_by_day` as `time_by_day`, `product_class` as `product_class`, `product` as `product` " \
        "where `sales_fact_1997`.`store_id` = `store`.`store_id` and `store`.`store_state` = 'WA' " \
        "and `sales_fact_1997`.`time_id` = `time_by_day`.`time_id` and `time_by_day`.`the_year` = 1997 " \
        "and `sales_fact_1997`.`product_id` = `product`.`product_id` " \
        "and `product`.`product_class_id` = `product_class`.`product_class_id` " \
        "and (`product_class`.`product_department` = 'Deli' and `product_class`.`product_family` = 'Food') " \
        "group by `store`.`store_state`, `time_by_day`.`the_year`"
  end

  # Java: FastBatchingCellReaderTest#testDistinctCountBug1785406_2
  it "distinct count bug 1785406 second variant" do
    # FIXME: assertQuerySql also fails in Java on MySQL (failsafe report confirms).
    mdx = <<~MDX
      With
      Member [Product].[x] as 'Aggregate({Gender.CurrentMember})'
      member [Measures].[foo] as '([Product].[x],[Measures].[Customer Count])'
      select Filter([Gender].members,(Not IsEmpty([Measures].[foo]))) on 0
      from Sales
    MDX
    assert_query_returns @olap, mdx.chomp, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Gender].[All Gender]}
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 266,773
      Row #0: 131,558
      Row #0: 135,215
    RESULT

    assert_query_sql @olap, mdx,
      "mysql" => "select `time_by_day`.`the_year` as `c0`, " \
        "count(distinct `sales_fact_1997`.`customer_id`) as `m0` " \
        "from `time_by_day` as `time_by_day`, `sales_fact_1997` as `sales_fact_1997` " \
        "where `sales_fact_1997`.`time_id` = `time_by_day`.`time_id` " \
        "and `time_by_day`.`the_year` = 1997 " \
        "group by `time_by_day`.`the_year`"
  end

  # Java: FastBatchingCellReaderTest#testAggregateDistinctCount2ndParameter
  it "aggregate distinct count 2nd parameter" do
    # Simple case of count distinct measure as second argument to Aggregate().
    # Should apply distinct-count aggregator (MONDRIAN-2016).
    assert_query_returns @olap, <<~MDX.chomp, <<~RESULT
      with
        set periods as [Time].[1997].[Q1].[1] : [Time].[1997].[Q4].[10]
        member [Time].[agg] as Aggregate(periods, [Measures].[Customer Count])
      select
        [Time].[agg] ON COLUMNS,
        [Gender].[M] on ROWS
      FROM [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Time].[agg]}
      Axis #2:
      {[Gender].[M]}
      Row #0: 2,651
    RESULT

    assert_query_returns @olap, <<~MDX.chomp, <<~RESULT
      WITH MEMBER [Measures].[My Distinct Count] AS
        'AGGREGATE([1997].Children, [Measures].[Customer Count])'
      SELECT {[Measures].[My Distinct Count], [Measures].[Customer Count]} ON COLUMNS,
        {[1997].Children} ON ROWS
      FROM Sales
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[My Distinct Count]}
      {[Measures].[Customer Count]}
      Axis #2:
      {[Time].[1997].[Q1]}
      {[Time].[1997].[Q2]}
      {[Time].[1997].[Q3]}
      {[Time].[1997].[Q4]}
      Row #0: 5,581
      Row #0: 2,981
      Row #1: 5,581
      Row #1: 2,973
      Row #2: 5,581
      Row #2: 3,026
      Row #3: 5,581
      Row #3: 3,261
    RESULT
  end

  # Java: FastBatchingCellReaderTest#testCountDistinctAggWithOtherCountDistinctInContext
  it "count distinct agg with other count distinct in context" do
    # Tests that Aggregate(<set>, <count-distinct measure>) aggregates the
    # correct measure when a different count-distinct measure is in context (MONDRIAN-2128).
    cube_xml = <<~XML
      <Cube name="2CountDistincts" defaultMeasure="Store Count">
        <Table name="sales_fact_1997"/>
        <DimensionUsage name="Time" source="Time" foreignKey="time_id"/>
        <DimensionUsage name="Store" source="Store" foreignKey="store_id"/>
        <DimensionUsage name="Product" source="Product" foreignKey="product_id"/>
        <Measure name="Store Count" column="store_id" aggregator="distinct-count"/>
        <Measure name="Customer Count" column="customer_id" aggregator="distinct-count"/>
        <Measure name="Unit Sales" column="unit_sales" aggregator="sum"/>
      </Cube>
    XML
    schema = SchemaHelper::FOODMART_SCHEMA.sub("<VirtualCube", "#{cube_xml}<VirtualCube")
    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    olap = Mondrian::OLAP::Connection.create(params)
    begin
      # We should get the same answer whether the default [Store Count]
      # measure is in context or [Unit Sales].
      result1 = format_result(olap.execute(<<~MDX))
        with member Store.agg as
          'aggregate({[Store].[USA].[CA],[Store].[USA].[OR]}, measures.[Customer Count])'
        select Store.agg on 0 from [2CountDistincts]
      MDX
      result2 = format_result(olap.execute(<<~MDX))
        with member Store.agg as
          'aggregate({[Store].[USA].[CA],[Store].[USA].[OR]}, measures.[Customer Count])'
        select Store.agg on 0 from [2CountDistincts] where measures.[Unit Sales]
      MDX
      # Compare measure values (everything after first '}')
      assert_equal measure_values(result1), measure_values(result2)

      assert_query_returns olap, <<~MDX.chomp, <<~RESULT
        with member measures.agg as
          'aggregate({[Store].[USA].[CA],[Store].[USA].[OR]}, measures.[Customer Count])'
        select {measures.agg, measures.[Customer Count]} on 0,
          [Product].[All Products].children on 1
        from [2CountDistincts]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[agg]}
        {[Measures].[Customer Count]}
        Axis #2:
        {[Product].[Drink]}
        {[Product].[Food]}
        {[Product].[Non-Consumable]}
        Row #0: 2,243
        Row #0: 3,485
        Row #1: 3,711
        Row #1: 5,525
        Row #2: 2,957
        Row #2: 4,468
      RESULT

      # [Customer Count] should override context
      assert_query_returns olap, <<~MDX.chomp, <<~RESULT
        with member Store.agg as
          'aggregate({[Store].[USA].[CA],[Store].[USA].[OR]}, measures.[Customer Count])'
        select {measures.[Store Count], measures.[Customer Count]} on 0,
          [Store].agg on 1
        from [2CountDistincts]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Store Count]}
        {[Measures].[Customer Count]}
        Axis #2:
        {[Store].[agg]}
        Row #0: 3,753
        Row #0: 3,753
      RESULT

      # Aggregate should pick up measure in context
      assert_query_returns olap, <<~MDX.chomp, <<~RESULT
        with member Store.agg as
          'aggregate({[Store].[USA].[CA],[Store].[USA].[OR]})'
        select {measures.[Store Count], measures.[Customer Count]} on 0,
          [Store].agg on 1
        from [2CountDistincts]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Store Count]}
        {[Measures].[Customer Count]}
        Axis #2:
        {[Store].[agg]}
        Row #0: 6
        Row #0: 3,753
      RESULT
    ensure
      olap.close
    end
  end

  # Java: FastBatchingCellReaderTest#testContextSetCorrectlyWith2ParamAggregate
  it "context set correctly with 2 param aggregate" do
    # Aggregate with a second parameter may change context. Verify
    # the evaluator is restored.
    assert_query_returns @olap, <<~MDX.chomp, <<~RESULT
      with
      member Store.cond as 'iif(
        aggregate({[Store].[All Stores].[USA]}, measures.[unit sales])
          > 70000, (Store.[All Stores], measures.currentMember), 0)'
      select Store.cond on 0 from sales
      where measures.[store sales]
    MDX
      Axis #0:
      {[Measures].[Store Sales]}
      Axis #1:
      {[Store].[cond]}
      Row #0: 565,238.13
    RESULT
  end

  # Java: FastBatchingCellReaderTest#testAggregateDistinctCountInDimensionFilter
  it "aggregate distinct count in dimension filter" do
    # FIXME: assertQuerySql also fails in Java on MySQL (failsafe report confirms).
    mdx = <<~MDX
      With
      Set [Products] as '{[Product].[All Products].[Drink], [Product].[All Products].[Food]}'
      Set [States] as '{[Store].[All Stores].[USA].[CA], [Store].[All Stores].[USA].[OR]}'
      Member [Product].[Selected Products] as 'Aggregate([Products])', SOLVE_ORDER=2
      Select
      Filter([States], not IsEmpty([Measures].[Customer Count])) on rows,
      {[Measures].[Customer Count]} on columns
      From [Sales]
      Where ([Product].[Selected Products])
    MDX
    assert_query_returns @olap, mdx.chomp, <<~RESULT
      Axis #0:
      {[Product].[Selected Products]}
      Axis #1:
      {[Measures].[Customer Count]}
      Axis #2:
      {[Store].[USA].[CA]}
      {[Store].[USA].[OR]}
      Row #0: 2,692
      Row #1: 1,036
    RESULT

    assert_query_sql @olap, mdx,
      "mysql" => "select `store`.`store_state` as `c0`, `time_by_day`.`the_year` as `c1`, " \
        "count(distinct `sales_fact_1997`.`customer_id`) as `m0` " \
        "from `store` as `store`, `sales_fact_1997` as `sales_fact_1997`, " \
        "`time_by_day` as `time_by_day`, `product_class` as `product_class`, `product` as `product` " \
        "where `sales_fact_1997`.`store_id` = `store`.`store_id` and " \
        "`store`.`store_state` in ('CA', 'OR') and " \
        "`sales_fact_1997`.`time_id` = `time_by_day`.`time_id` and " \
        "`time_by_day`.`the_year` = 1997 and " \
        "`sales_fact_1997`.`product_id` = `product`.`product_id` and " \
        "`product`.`product_class_id` = `product_class`.`product_class_id` and " \
        "`product_class`.`product_family` in ('Drink', 'Food') " \
        "group by `store`.`store_state`, `time_by_day`.`the_year`"
  end

  # Java: FastBatchingCellReaderTest#testLoadDistinctSqlMeasure
  it "load distinct SQL measure" do
    # Some databases cannot handle scalar subqueries inside count(distinct).
    # MySQL and PostgreSQL can, so this test runs on both.
    # FIXME: assertQuerySql also fails in Java on MySQL (failsafe report confirms).
    quote = case MONDRIAN_DRIVER
            when "postgresql" then '"'
            else "`"
            end

    cube_xml = <<~XML.gsub('`', quote)
      <Cube name="Warehouse2">
        <Table name="warehouse"/>
        <DimensionUsage name="Store Type" source="Store Type" foreignKey="stores_id"/>
        <Measure name="Count Distinct of Warehouses (Large Owned)" aggregator="distinct count" formatString="#,##0">
          <MeasureExpression>
            <SQL dialect="generic">(select `warehouse_class`.`warehouse_class_id` AS `warehouse_class_id` from `warehouse_class` AS `warehouse_class` where `warehouse_class`.`warehouse_class_id` = `warehouse`.`warehouse_class_id` and `warehouse_class`.`description` = 'Large Owned')</SQL>
          </MeasureExpression>
        </Measure>
        <Measure name="Count Distinct of Warehouses (Large Independent)" aggregator="distinct count" formatString="#,##0">
          <MeasureExpression>
            <SQL dialect="generic">(select `warehouse_class`.`warehouse_class_id` AS `warehouse_class_id` from `warehouse_class` AS `warehouse_class` where `warehouse_class`.`warehouse_class_id` = `warehouse`.`warehouse_class_id` and `warehouse_class`.`description` = 'Large Independent')</SQL>
          </MeasureExpression>
        </Measure>
        <Measure name="Count All of Warehouses (Large Independent)" aggregator="count" formatString="#,##0">
          <MeasureExpression>
            <SQL dialect="generic">(select `warehouse_class`.`warehouse_class_id` AS `warehouse_class_id` from `warehouse_class` AS `warehouse_class` where `warehouse_class`.`warehouse_class_id` = `warehouse`.`warehouse_class_id` and `warehouse_class`.`description` = 'Large Independent')</SQL>
          </MeasureExpression>
        </Measure>
        <Measure name="Count Distinct Store+Warehouse" aggregator="distinct count" formatString="#,##0">
          <MeasureExpression><SQL dialect="generic">`store_id`+`warehouse_id`</SQL></MeasureExpression>
        </Measure>
        <Measure name="Count All Store+Warehouse" aggregator="count" formatString="#,##0">
          <MeasureExpression><SQL dialect="generic">`store_id`+`warehouse_id`</SQL></MeasureExpression>
        </Measure>
        <Measure name="Store Count" column="stores_id" aggregator="count" formatString="#,###"/>
      </Cube>
    XML
    schema = SchemaHelper::FOODMART_SCHEMA.sub("<VirtualCube", "#{cube_xml}<VirtualCube")
    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    olap = Mondrian::OLAP::Connection.create(params)
    begin
      assert_query_returns olap, <<~MDX.chomp, <<~RESULT
        select
          [Store Type].Children on rows,
          {[Measures].[Count Distinct of Warehouses (Large Owned)],
           [Measures].[Count Distinct of Warehouses (Large Independent)],
           [Measures].[Count All of Warehouses (Large Independent)],
           [Measures].[Count Distinct Store+Warehouse],
           [Measures].[Count All Store+Warehouse],
           [Measures].[Store Count]} on columns
        from [Warehouse2]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Count Distinct of Warehouses (Large Owned)]}
        {[Measures].[Count Distinct of Warehouses (Large Independent)]}
        {[Measures].[Count All of Warehouses (Large Independent)]}
        {[Measures].[Count Distinct Store+Warehouse]}
        {[Measures].[Count All Store+Warehouse]}
        {[Measures].[Store Count]}
        Axis #2:
        {[Store Type].[Deluxe Supermarket]}
        {[Store Type].[Gourmet Supermarket]}
        {[Store Type].[HeadQuarters]}
        {[Store Type].[Mid-Size Grocery]}
        {[Store Type].[Small Grocery]}
        {[Store Type].[Supermarket]}
        Row #0: 1
        Row #0: 0
        Row #0: 0
        Row #0: 6
        Row #0: 6
        Row #0: 6
        Row #1: 1
        Row #1: 0
        Row #1: 0
        Row #1: 2
        Row #1: 2
        Row #1: 2
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #3: 0
        Row #3: 1
        Row #3: 1
        Row #3: 4
        Row #3: 4
        Row #3: 4
        Row #4: 0
        Row #4: 1
        Row #4: 1
        Row #4: 4
        Row #4: 4
        Row #4: 4
        Row #5: 0
        Row #5: 1
        Row #5: 3
        Row #5: 8
        Row #5: 8
        Row #5: 8
      RESULT

      sql_mdx = <<~MDX
        select
          [Store Type].Children on rows,
          {[Measures].[Count Distinct of Warehouses (Large Owned)],
           [Measures].[Count Distinct of Warehouses (Large Independent)],
           [Measures].[Count All of Warehouses (Large Independent)],
           [Measures].[Count Distinct Store+Warehouse],
           [Measures].[Count All Store+Warehouse],
           [Measures].[Store Count]} on columns
        from [Warehouse2]
      MDX
      assert_query_sql olap, sql_mdx,
        "mysql" => "select `store`.`store_type` as `c0`, " \
          "count(distinct (select `warehouse_class`.`warehouse_class_id` AS `warehouse_class_id` " \
          "from `warehouse_class` AS `warehouse_class` " \
          "where `warehouse_class`.`warehouse_class_id` = `warehouse`.`warehouse_class_id` " \
          "and `warehouse_class`.`description` = 'Large Owned')) as `m0`, " \
          "count(distinct (select `warehouse_class`.`warehouse_class_id` AS `warehouse_class_id` " \
          "from `warehouse_class` AS `warehouse_class` " \
          "where `warehouse_class`.`warehouse_class_id` = `warehouse`.`warehouse_class_id` " \
          "and `warehouse_class`.`description` = 'Large Independent')) as `m1`, " \
          "count((select `warehouse_class`.`warehouse_class_id` AS `warehouse_class_id` " \
          "from `warehouse_class` AS `warehouse_class` " \
          "where `warehouse_class`.`warehouse_class_id` = `warehouse`.`warehouse_class_id` " \
          "and `warehouse_class`.`description` = 'Large Independent')) as `m2`, " \
          "count(distinct `store_id`+`warehouse_id`) as `m3`, " \
          "count(`store_id`+`warehouse_id`) as `m4`, " \
          "count(`warehouse`.`stores_id`) as `m5` " \
          "from `store` as `store`, `warehouse` as `warehouse` " \
          "where `warehouse`.`stores_id` = `store`.`store_id` " \
          "group by `store`.`store_type`"
    ensure
      olap.close
    end
  end

  # Java: FastBatchingCellReaderTest#testCellBatchSizeWithUdf
  it "cell batch size with UDF" do
    # Tests that UdfResolver handles CellRequestQuantumExceededException.
    with_properties(CellBatchSize: 1) do
      assert_query_returns @olap, <<~MDX.chomp, <<~RESULT
        select lastnonempty([education level].members, measures.[unit sales]) on 0 from sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Education Level].[Partial High School]}
        Row #0: 79,155
      RESULT
    end
  end

  # ===== Grouping function and dialect tests =====

  # Java: FastBatchingCellReaderTest#testDoesDBSupportGroupingSets
  it "does DB support grouping sets" do
    dialect = @olap.raw_mondrian_connection.getSchema.getDialect
    case MONDRIAN_DRIVER
    when "mysql", "postgresql"
      assert_equal false, dialect.supportsGroupingSets
    end
  end

  # Java: FastBatchingCellReaderTest#testShouldUseGroupingFunctionOnPropertyTrueAndOnSupportedDB
  it "should use grouping function on property true and on supported DB" do
    with_properties(EnableGroupingSets: true) do
      with_batch_context do
        batch_loader = create_batch_loader(true, sales_cube)
        assert_equal true, invoke_should_use_grouping_function(batch_loader)
      end
    end
  end

  # Java: FastBatchingCellReaderTest#testShouldUseGroupingFunctionOnPropertyTrueAndOnNonSupportedDB
  it "should use grouping function on property true and on non-supported DB" do
    with_properties(EnableGroupingSets: true) do
      with_batch_context do
        batch_loader = create_batch_loader(false, sales_cube)
        assert_equal false, invoke_should_use_grouping_function(batch_loader)
      end
    end
  end

  # Java: FastBatchingCellReaderTest#testShouldUseGroupingFunctionOnPropertyFalseOnSupportedDB
  it "should use grouping function on property false on supported DB" do
    with_properties(EnableGroupingSets: false) do
      with_batch_context do
        batch_loader = create_batch_loader(true, sales_cube)
        assert_equal false, invoke_should_use_grouping_function(batch_loader)
      end
    end
  end

  # Java: FastBatchingCellReaderTest#testShouldUseGroupingFunctionOnPropertyFalseOnNonSupportedDB
  it "should use grouping function on property false on non-supported DB" do
    with_properties(EnableGroupingSets: false) do
      with_batch_context do
        batch_loader = create_batch_loader(false, sales_cube)
        assert_equal false, invoke_should_use_grouping_function(batch_loader)
      end
    end
  end

  # ===== Batch grouping tests =====

  # Java: FastBatchingCellReaderTest#testGroupBatchesForNonGroupableBatchesWithSorting
  it "group batches for non-groupable batches with sorting" do
    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      gender_batch = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["gender"], ["F"]))
      marital_status_batch = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["marital_status"], ["M"]))

      batch_list = java.util.ArrayList.new
      batch_list.add(gender_batch)
      batch_list.add(marital_status_batch)

      grouped_batches = invoke_group_batches(batch_list)
      assert_equal batch_list.size, grouped_batches.size
      assert_equal gender_batch, get_detailed_batch(grouped_batches.get(0))
      assert_equal marital_status_batch, get_detailed_batch(grouped_batches.get(1))
    end
  end

  # Java: FastBatchingCellReaderTest#testGroupBatchesForNonGroupableBatchesWithConstraints
  it "group batches for non-groupable batches with constraints" do
    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      compound_members = [%w[USA CA], %w[Canada BC]]
      constraint = make_constraint_country_state(compound_members)

      gender_batch = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["gender"], ["F"], constraint))
      marital_status_batch = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["marital_status"], ["M"], constraint))

      batch_list = java.util.ArrayList.new
      batch_list.add(gender_batch)
      batch_list.add(marital_status_batch)

      grouped_batches = invoke_group_batches(batch_list)
      assert_equal batch_list.size, grouped_batches.size
      assert_equal gender_batch, get_detailed_batch(grouped_batches.get(0))
      assert_equal marital_status_batch, get_detailed_batch(grouped_batches.get(1))
    end
  end

  # Java: FastBatchingCellReaderTest#testGroupBatchesForGroupableBatches
  #
  # The Java test creates anonymous Batch subclasses that override the package-private
  # canBatch() method to return fixed true/false values, then verifies that groupBatches()
  # merges the "always-true" batch as a summary under the "always-false" batch.
  #
  # In JRuby, Batch is a non-static inner class of the package-private BatchLoader.
  # Subclassing it to override canBatch() is not feasible: JRuby cannot extend a
  # non-public inner class, and bytecode generation (e.g. ASM) would be needed to
  # create a Java subclass at runtime. An alternative would be to make canBatch()
  # or Batch itself protected/public in the Mondrian fork.
  it "group batches for groupable batches" do
    skip "FIXME: requires anonymous Batch subclass with custom canBatch() — not feasible from JRuby"
  end

  # Java: FastBatchingCellReaderTest#testGroupBatchesForGroupableBatchesAndNonGroupableBatches
  #
  # Same problem as testGroupBatchesForGroupableBatches above: the Java test creates
  # five Batch subclasses with custom canBatch() that form two groups (group1 with 3
  # batches, group2 with 2 batches), then asserts groupBatches() produces exactly 2
  # CompositeBatches with the correct detailed/summary assignments.
  it "group batches for groupable batches and non-groupable batches" do
    skip "FIXME: requires anonymous Batch subclass with custom canBatch() — not feasible from JRuby"
  end

  # Java: FastBatchingCellReaderTest#testGroupBatchesForTwoSetOfGroupableBatches
  it "group batches for two sets of groupable batches" do
    field_values_store_type = %w[Deluxe\ Supermarket Gourmet\ Supermarket HeadQuarters Mid-Size\ Grocery Small\ Grocery Supermarket]
    field_values_warehouse_country = %w[Canada Mexico USA]

    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      batch1_rollup_on_gender = create_multi_batch(batch_loader,
        %w[time_by_day store product_class], %w[the_year store_type product_family],
        [%w[1997], field_values_store_type, %w[Food Non-Consumable Drink]],
        "Sales", "[Measures].[Unit Sales]")

      batch1_rollup_on_gender_and_product_dept = create_multi_batch(batch_loader,
        %w[time_by_day product_class], %w[the_year product_family],
        [%w[1997], %w[Food Non-Consumable Drink]],
        "Sales", "[Measures].[Unit Sales]")

      batch1_rollup_on_store_type_and_product_dept = create_multi_batch(batch_loader,
        %w[time_by_day customer], %w[the_year gender],
        [%w[1997], %w[M F]],
        "Sales", "[Measures].[Unit Sales]")

      batch1_detailed = create_multi_batch(batch_loader,
        %w[time_by_day store product_class customer], %w[the_year store_type product_family gender],
        [%w[1997], field_values_store_type, %w[Food Non-Consumable Drink], %w[M F]],
        "Sales", "[Measures].[Unit Sales]")

      batch2_rollup_on_store_type = create_multi_batch(batch_loader,
        %w[warehouse time_by_day product_class], %w[warehouse_country the_year product_family],
        [field_values_warehouse_country, %w[1997], %w[Food Non-Consumable Drink]],
        "Warehouse", "[Measures].[Warehouse Sales]")

      batch2_rollup_on_store_type_and_warehouse_country = create_multi_batch(batch_loader,
        %w[time_by_day product_class], %w[the_year product_family],
        [%w[1997], %w[Food Non-Consumable Drink]],
        "Warehouse", "[Measures].[Warehouse Sales]")

      batch2_rollup_on_product_family_and_warehouse_country = create_multi_batch(batch_loader,
        %w[time_by_day store], %w[the_year store_type],
        [%w[1997], field_values_store_type],
        "Warehouse", "[Measures].[Warehouse Sales]")

      batch2_detailed = create_multi_batch(batch_loader,
        %w[warehouse time_by_day store product_class], %w[warehouse_country the_year store_type product_family],
        [field_values_warehouse_country, %w[1997], field_values_store_type, %w[Food Non-Consumable Drink]],
        "Warehouse", "[Measures].[Warehouse Sales]")

      batch_list = java.util.ArrayList.new
      batch_list.add(batch1_rollup_on_gender)
      batch_list.add(batch2_rollup_on_store_type)
      batch_list.add(batch2_rollup_on_store_type_and_warehouse_country)
      batch_list.add(batch2_rollup_on_product_family_and_warehouse_country)
      batch_list.add(batch1_rollup_on_gender_and_product_dept)
      batch_list.add(batch1_rollup_on_store_type_and_product_dept)
      batch_list.add(batch2_detailed)
      batch_list.add(batch1_detailed)

      grouped_batches = invoke_group_batches(batch_list)
      grouped_batch_count = grouped_batches.size

      # Until MONDRIAN-1001 is fixed, behavior is flaky due to interaction with previous tests.
      # Bug.BugMondrian1001Fixed is false, so count may be 2 or 4.
      assert(grouped_batch_count == 2 || grouped_batch_count == 4,
        "Expected grouped batch count of 2 or 4, got #{grouped_batch_count}")
    end
  end

  # Java: FastBatchingCellReaderTest#testAddToCompositeBatchForBothBatchesNotPartOfCompositeBatch
  it "add to composite batch for both batches not part of composite batch" do
    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      batch1 = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["country"], ["F"]))
      batch2 = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["gender"], ["F"]))

      batch_groups = java.util.HashMap.new
      invoke_add_to_composite_batch(batch_loader, batch_groups, batch1, batch2)

      assert_equal 1, batch_groups.size
      composite_batch = batch_groups.get(get_batch_key(batch1))
      assert_equal batch1, get_detailed_batch(composite_batch)
      assert_equal 1, get_summary_batches(composite_batch).size
      assert get_summary_batches(composite_batch).contains(batch2)
    end
  end

  # Java: FastBatchingCellReaderTest#testAddToCompositeBatchForDetailedBatchAlreadyPartOfACompositeBatch
  it "add to composite batch for detailed batch already part of a composite batch" do
    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      detailed_batch = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["country"], ["F"]))
      agg_batch1 = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["gender"], ["F"]))
      agg_batch_already_in_composite = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["gender"], ["F"]))

      batch_groups = java.util.HashMap.new
      existing_composite_batch = create_composite_batch(detailed_batch)
      add_to_summary(existing_composite_batch, agg_batch_already_in_composite)
      batch_groups.put(get_batch_key(detailed_batch), existing_composite_batch)

      invoke_add_to_composite_batch(batch_loader, batch_groups, detailed_batch, agg_batch1)

      assert_equal 1, batch_groups.size
      composite_batch = batch_groups.get(get_batch_key(detailed_batch))
      assert_equal detailed_batch, get_detailed_batch(composite_batch)
      assert_equal 2, get_summary_batches(composite_batch).size
      assert get_summary_batches(composite_batch).contains(agg_batch1)
      assert get_summary_batches(composite_batch).contains(agg_batch_already_in_composite)
    end
  end

  # Java: FastBatchingCellReaderTest#testAddToCompositeBatchForAggregationBatchAlreadyPartOfACompositeBatch
  it "add to composite batch for aggregation batch already part of a composite batch" do
    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      detailed_batch = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["country"], ["F"]))
      agg_batch_to_add = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["gender"], ["F"]))
      agg_batch_already_in_composite = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["city"], ["F"]))

      batch_groups = java.util.HashMap.new
      existing_composite_batch = create_composite_batch(agg_batch_to_add)
      add_to_summary(existing_composite_batch, agg_batch_already_in_composite)
      batch_groups.put(get_batch_key(agg_batch_to_add), existing_composite_batch)

      invoke_add_to_composite_batch(batch_loader, batch_groups, detailed_batch, agg_batch_to_add)

      assert_equal 1, batch_groups.size
      composite_batch = batch_groups.get(get_batch_key(detailed_batch))
      assert_equal detailed_batch, get_detailed_batch(composite_batch)
      assert_equal 2, get_summary_batches(composite_batch).size
      assert get_summary_batches(composite_batch).contains(agg_batch_to_add)
      assert get_summary_batches(composite_batch).contains(agg_batch_already_in_composite)
    end
  end

  # Java: FastBatchingCellReaderTest#testAddToCompositeBatchForBothBatchAlreadyPartOfACompositeBatch
  it "add to composite batch for both batch already part of a composite batch" do
    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      detailed_batch = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["country"], ["F"]))
      agg_batch_to_add = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["gender"], ["F"]))
      agg_batch_already_in_composite_of_agg = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["city"], ["F"]))
      agg_batch_already_in_composite_of_detail = create_batch_from_request(batch_loader,
        create_cell_request("Sales", "[Measures].[Unit Sales]", ["customer"], ["state_province"], ["F"]))

      batch_groups = java.util.HashMap.new
      existing_agg_composite = create_composite_batch(agg_batch_to_add)
      add_to_summary(existing_agg_composite, agg_batch_already_in_composite_of_agg)
      batch_groups.put(get_batch_key(agg_batch_to_add), existing_agg_composite)

      existing_detail_composite = create_composite_batch(detailed_batch)
      add_to_summary(existing_detail_composite, agg_batch_already_in_composite_of_detail)
      batch_groups.put(get_batch_key(detailed_batch), existing_detail_composite)

      invoke_add_to_composite_batch(batch_loader, batch_groups, detailed_batch, agg_batch_to_add)

      assert_equal 1, batch_groups.size
      composite_batch = batch_groups.get(get_batch_key(detailed_batch))
      assert_equal detailed_batch, get_detailed_batch(composite_batch)
      assert_equal 3, get_summary_batches(composite_batch).size
      assert get_summary_batches(composite_batch).contains(agg_batch_to_add)
      assert get_summary_batches(composite_batch).contains(agg_batch_already_in_composite_of_agg)
      assert get_summary_batches(composite_batch).contains(agg_batch_already_in_composite_of_detail)
    end
  end

  # ===== canBatch tests =====

  # Java: FastBatchingCellReaderTest#testCanBatchForSuperSet
  it "can batch for super set" do
    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      aggregation_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class], %w[the_year product_family product_department],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department],
        "Sales", "[Measures].[Unit Sales]")

      detailed_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class customer], %w[the_year product_family product_department gender],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department, %w[M F]],
        "Sales", "[Measures].[Unit Sales]")

      assert_equal true, invoke_can_batch(detailed_batch, aggregation_batch)
      assert_equal false, invoke_can_batch(aggregation_batch, detailed_batch)
    end
  end

  # Java: FastBatchingCellReaderTest#testCanBatchForBatchWithConstraint
  it "can batch for batch with constraint" do
    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      constraint = make_constraint_country_state([%w[USA CA], %w[Canada BC]])

      aggregation_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class], %w[the_year product_family product_department],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department],
        "Sales", "[Measures].[Unit Sales]", constraint)

      detailed_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class customer], %w[the_year product_family product_department gender],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department, %w[M F]],
        "Sales", "[Measures].[Unit Sales]", constraint)

      assert_equal true, invoke_can_batch(detailed_batch, aggregation_batch)
      assert_equal false, invoke_can_batch(aggregation_batch, detailed_batch)
    end
  end

  # Java: FastBatchingCellReaderTest#testCanBatchForBatchWithConstraint2
  it "can batch for batch with different constraints" do
    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      # Different constraint will cause the Batch not to match.
      constraint1 = make_constraint_country_state([%w[USA CA], %w[Canada BC]])
      constraint2 = make_constraint_country_state([%w[USA CA], %w[USA OR]])

      aggregation_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class], %w[the_year product_family product_department],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department],
        "Sales", "[Measures].[Unit Sales]", constraint1)

      detailed_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class customer], %w[the_year product_family product_department gender],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department, %w[M F]],
        "Sales", "[Measures].[Unit Sales]", constraint2)

      assert_equal true, invoke_can_batch(detailed_batch, aggregation_batch)
      assert_equal false, invoke_can_batch(aggregation_batch, detailed_batch)
    end
  end

  # Java: FastBatchingCellReaderTest#testCanBatchForBatchWithDistinctCountInDetailedBatch
  it "can batch for batch with distinct count in detailed batch" do
    unless mondrian_property(:UseAggregates).get && mondrian_property(:ReadAggregates).get
      skip "Only applicable when UseAggregates and ReadAggregates are enabled"
    end

    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      aggregation_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class], %w[the_year product_family product_department],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department],
        "Sales", "[Measures].[Unit Sales]")

      detailed_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class], %w[the_year product_family product_department],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department],
        "Sales", "[Measures].[Customer Count]")

      assert_equal false, invoke_can_batch(detailed_batch, aggregation_batch)
      assert_equal false, invoke_can_batch(aggregation_batch, detailed_batch)
    end
  end

  # Java: FastBatchingCellReaderTest#testCanBatchForBatchWithDistinctCountInAggregateBatch
  it "can batch for batch with distinct count in aggregate batch" do
    unless mondrian_property(:UseAggregates).get && mondrian_property(:ReadAggregates).get
      skip "Only applicable when UseAggregates and ReadAggregates are enabled"
    end

    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      aggregation_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class], %w[the_year product_family product_department],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department],
        "Sales", "[Measures].[Customer Count]")

      detailed_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class], %w[the_year product_family product_department],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department],
        "Sales", "[Measures].[Unit Sales]")

      assert_equal false, invoke_can_batch(detailed_batch, aggregation_batch)
      assert_equal false, invoke_can_batch(aggregation_batch, detailed_batch)
    end
  end

  # Java: FastBatchingCellReaderTest#testCanBatchSummaryBatchWithDetailedBatchWithDistinctCount
  it "can batch summary batch with detailed batch with distinct count" do
    if mondrian_property(:UseAggregates).get || mondrian_property(:ReadAggregates).get
      skip "Only applicable when UseAggregates and ReadAggregates are both disabled"
    end

    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      aggregation_batch = create_multi_batch(batch_loader,
        %w[time_by_day], %w[the_year],
        [%w[1997]],
        "Sales", "[Measures].[Customer Count]")

      detailed_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class], %w[the_year product_family product_department],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department],
        "Sales", "[Measures].[Unit Sales]")

      assert_equal false, invoke_can_batch(detailed_batch, aggregation_batch)
      assert_equal false, invoke_can_batch(aggregation_batch, detailed_batch)
    end
  end

  # Java: FastBatchingCellReaderTest#testNonSuperSet
  it "non-super set cannot batch" do
    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      aggregation_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class], %w[the_year product_family product_department],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department],
        "Sales", "[Measures].[Unit Sales]")

      detailed_batch = create_multi_batch(batch_loader,
        %w[product_class product_class customer], %w[product_family product_department gender],
        [%w[Food Non-Consumable Drink], field_value_product_department, %w[M F]],
        "Sales", "[Measures].[Unit Sales]")

      assert_equal false, invoke_can_batch(detailed_batch, aggregation_batch)
      assert_equal false, invoke_can_batch(aggregation_batch, detailed_batch)
    end
  end

  # Java: FastBatchingCellReaderTest#testSuperSetAndNotAllValues
  it "super set and not all values cannot batch" do
    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      aggregation_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class], %w[the_year product_family product_department],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department],
        "Sales", "[Measures].[Unit Sales]")

      detailed_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class customer], %w[the_year product_family product_department gender],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department, %w[M]],
        "Sales", "[Measures].[Unit Sales]")

      assert_equal false, invoke_can_batch(detailed_batch, aggregation_batch)
      assert_equal false, invoke_can_batch(aggregation_batch, detailed_batch)
    end
  end

  # Java: FastBatchingCellReaderTest#testCanBatchForBatchesFromSameAggregationButDifferentRollupOption
  it "can batch for batches from same aggregation but different rollup option" do
    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      batch1 = create_multi_batch(batch_loader,
        %w[time_by_day], %w[the_year],
        [%w[1997]],
        "Sales", "[Measures].[Unit Sales]")

      batch2 = create_multi_batch(batch_loader,
        %w[time_by_day time_by_day time_by_day], %w[the_year quarter month_of_year],
        [%w[1997], %w[Q1 Q2 Q3 Q4], %w[1 2 3 4 5 6 7 8 9 10 11 12]],
        "Sales", "[Measures].[Unit Sales]")

      batch2_can_batch1 = invoke_can_batch(batch2, batch1)
      batch1_can_batch2 = invoke_can_batch(batch1, batch2)

      # Bug.BugMondrian1001Fixed is false — behavior is flaky due to interaction
      # with previous tests. When the bug is fixed, the assertions below should
      # be unconditional.
      bug_mondrian_1001_fixed = false
      if bug_mondrian_1001_fixed
        if mondrian_property(:UseAggregates).get && mondrian_property(:ReadAggregates).get
          assert_equal false, batch2_can_batch1
          assert_equal false, batch1_can_batch2
        else
          assert_equal true, batch2_can_batch1
        end
      end
    end
  end

  # Java: FastBatchingCellReaderTest#testSuperSetDifferentValues
  it "super set with different values cannot batch" do
    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      aggregation_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class], %w[the_year product_family product_department],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department],
        "Sales", "[Measures].[Unit Sales]")

      detailed_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class customer], %w[the_year product_family product_department gender],
        [%w[1998], %w[Food Non-Consumable Drink], field_value_product_department, %w[M F]],
        "Sales", "[Measures].[Unit Sales]")

      assert_equal false, invoke_can_batch(detailed_batch, aggregation_batch)
      assert_equal false, invoke_can_batch(aggregation_batch, detailed_batch)
    end
  end

  # Java: FastBatchingCellReaderTest#testCanBatchForBatchWithDifferentAggregationTable
  it "can batch for batch with different aggregation table" do
    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      summary_batch = create_multi_batch(batch_loader,
        %w[time_by_day], %w[the_year],
        [%w[1997]],
        "Sales", "[Measures].[Unit Sales]")

      detailed_batch = create_multi_batch(batch_loader,
        %w[time_by_day customer], %w[the_year gender],
        [%w[1997], %w[M F]],
        "Sales", "[Measures].[Unit Sales]")

      if mondrian_property(:UseAggregates).get && mondrian_property(:ReadAggregates).get
        assert_equal false, invoke_can_batch(detailed_batch, summary_batch)
        assert_equal false, invoke_can_batch(summary_batch, detailed_batch)
      else
        assert_equal true, invoke_can_batch(detailed_batch, summary_batch)
        assert_equal false, invoke_can_batch(summary_batch, detailed_batch)
      end
    end
  end

  # Java: FastBatchingCellReaderTest#testCannotBatchTwoBatchesAtTheSameLevel
  it "cannot batch two batches at the same level" do
    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      first_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class], %w[the_year product_family product_department],
        [%w[1997], %w[Food], field_value_product_department],
        "Sales", "[Measures].[Customer Count]")

      second_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class], %w[the_year product_family product_department],
        [%w[1997], %w[Drink], field_value_product_department],
        "Sales", "[Measures].[Customer Count]")

      assert_equal false, invoke_can_batch(first_batch, second_batch)
      assert_equal false, invoke_can_batch(second_batch, first_batch)
    end
  end

  # Java: FastBatchingCellReaderTest#testCompositeBatchLoadAggregation
  it "composite batch load aggregation" do
    dialect = @olap.raw_mondrian_connection.getSchema.getDialect
    skip "Only applicable when dialect supports grouping sets" unless dialect.supportsGroupingSets

    with_batch_context do
      batch_loader = create_batch_loader(nil, sales_cube)
      summary_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class], %w[the_year product_family product_department],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department],
        "Sales", "[Measures].[Unit Sales]")

      detailed_batch = create_multi_batch(batch_loader,
        %w[time_by_day product_class product_class customer], %w[the_year product_family product_department gender],
        [%w[1997], %w[Food Non-Consumable Drink], field_value_product_department, %w[M F]],
        "Sales", "[Measures].[Unit Sales]")

      composite_batch = create_composite_batch(detailed_batch)
      add_to_summary(composite_batch, summary_batch)

      segment_futures = java.util.ArrayList.new
      agg_mgr = @execution.getMondrianStatement.getMondrianConnection.getServer.getAggregationManager
      locus = Java::MondrianServer::Locus.peek
      agg_mgr.cacheMgr.execute(LoadCommand.new(locus, composite_batch, segment_futures))

      assert_equal 1, segment_futures.size
      assert_equal 2, segment_futures.get(0).get.size

      # The order of segments is not deterministic — find a match for each batch's bit key.
      segments = segment_futures.get(0).get
      detailed_key = invoke_get_constrained_columns_bit_key(detailed_batch)
      summary_key = invoke_get_constrained_columns_bit_key(summary_batch)

      found_detailed = segments.keySet.any? { |seg| seg.getConstrainedColumnsBitKey == detailed_key }
      found_summary = segments.keySet.any? { |seg| seg.getConstrainedColumnsBitKey == summary_key }
      assert found_detailed, "No bitkey match found for detailed batch"
      assert found_summary, "No bitkey match found for summary batch"
    end
  end

  # ===== In-memory aggregation tests =====

  describe "in-memory aggregation" do
    # Java: FastBatchingCellReaderTest#testInMemoryAggSum
    it "sum" do
      sum = Java::MondrianRolap::RolapAggregator::Sum
      numeric = Java::MondrianSpi::Dialect::Datatype::Numeric
      integer = Java::MondrianSpi::Dialect::Datatype::Integer

      # Test with double
      assert_equal 3.5, sum.aggregate(to_java_list([nil, 0.0, 1.1, 2.4], :double), numeric)
      assert_nil sum.aggregate(to_java_list([nil, nil, nil], :double), numeric)
      # Empty array — Java expects AssertionError from `assert rawData.size() > 0`,
      # but this only fires with JVM -ea flag. Without -ea, returns nil.
      assert_raises(java.lang.AssertionError) { sum.aggregate(to_java_list([], :double), numeric) }
      assert_equal 4.6, sum.aggregate(to_java_list([2.7, 1.9], :double), numeric)

      # Test with int
      assert_equal 5, sum.aggregate(to_java_list([nil, 0, 1, 4], :int), integer)
      assert_nil sum.aggregate(to_java_list([nil, nil, nil], :int), integer)
      assert_raises(java.lang.AssertionError) { sum.aggregate(to_java_list([], :int), integer) }
      assert_equal 10, sum.aggregate(to_java_list([3, 7], :int), integer)
    end

    # Java: FastBatchingCellReaderTest#testInMemoryAggMin
    it "min" do
      min = Java::MondrianRolap::RolapAggregator::Min
      numeric = Java::MondrianSpi::Dialect::Datatype::Numeric
      integer = Java::MondrianSpi::Dialect::Datatype::Integer

      # Test with double
      assert_equal 0.0, min.aggregate(to_java_list([nil, 0.0, 1.1, 2.4], :double), numeric)
      assert_nil min.aggregate(to_java_list([nil, nil, nil], :double), numeric)
      assert_raises(java.lang.AssertionError) { min.aggregate(to_java_list([], :double), numeric) }
      assert_equal 1.9, min.aggregate(to_java_list([2.7, 1.9], :double), numeric)

      # Test with int
      assert_equal 0, min.aggregate(to_java_list([nil, 0, 1, 4], :int), integer)
      assert_nil min.aggregate(to_java_list([nil, nil, nil], :int), integer)
      assert_raises(java.lang.AssertionError) { min.aggregate(to_java_list([], :int), integer) }
      assert_equal 3, min.aggregate(to_java_list([3, 7], :int), integer)
    end

    # Java: FastBatchingCellReaderTest#testInMemoryAggMax
    it "max" do
      max = Java::MondrianRolap::RolapAggregator::Max
      numeric = Java::MondrianSpi::Dialect::Datatype::Numeric
      integer = Java::MondrianSpi::Dialect::Datatype::Integer

      # Test with double
      assert_equal 2.4, max.aggregate(to_java_list([nil, 0.0, 1.1, 2.4], :double), numeric)
      assert_nil max.aggregate(to_java_list([nil, nil, nil], :double), numeric)
      assert_equal(-1.2, max.aggregate(to_java_list([-1.2, -3.4], :double), numeric))
      assert_raises(java.lang.AssertionError) { max.aggregate(to_java_list([], :double), numeric) }
      assert_equal 2.7, max.aggregate(to_java_list([2.7, 1.9], :double), numeric)

      # Test with int
      assert_equal 4, max.aggregate(to_java_list([nil, 0, 1, 4], :int), integer)
      assert_nil max.aggregate(to_java_list([nil, nil, nil], :int), integer)
      assert_raises(java.lang.AssertionError) { max.aggregate(to_java_list([], :int), integer) }
      assert_equal 7, max.aggregate(to_java_list([3, 7], :int), integer)
    end
  end

  private

  # ===== Helpers for assertQueriesReturnSimilarResults =====

  def measure_values(result_string)
    index = result_string.index("}")
    index ? result_string[index..] : result_string
  end

  # Mirrors Java's assertQuerySql — captures SQL during MDX execution and checks that
  # the expected SQL substring appears. Only checks patterns for the current driver;
  # if no pattern is defined for the current driver, the assertion is a no-op (same as Java).
  # sql_patterns is a Hash of driver name => expected SQL substring.
  def assert_query_sql(olap, mdx, sql_patterns)
    pattern = sql_patterns[MONDRIAN_DRIVER]
    return unless pattern

    Mondrian::OLAP::Connection.flush_schema_cache
    captured = capture_sql { olap.execute(mdx) }
    normalized_pattern = pattern.gsub(/\s+/, " ").strip
    found = captured.any? { |sql| sql.gsub(/\s+/, " ").strip.include?(normalized_pattern) }
    assert found,
      "Expected SQL pattern not found in captured queries.\n\nExpected:\n#{pattern}\n\nCaptured (#{captured.size} queries):\n#{captured.to_a.join("\n\n")}"
  end

  # ===== Helpers for in-memory aggregation tests =====

  def to_java_list(values, type)
    java_values = values.map do |v|
      next nil if v.nil?
      case type
      when :double then java.lang.Double.new(v.to_f)
      when :int then java.lang.Integer.new(v.to_i)
      else v
      end
    end
    java.util.Arrays.asList(java_values.to_java(java.lang.Object))
  end

  # ===== Helpers for batch internal tests =====

  # Field value constants matching BatchTestCase
  def field_value_product_department
    %w[Alcoholic\ Beverages Baked\ Goods Baking\ Goods Beverages Breakfast\ Foods
       Canned\ Foods Canned\ Products Carousel Checkout Dairy Deli Eggs Frozen\ Foods
       Health\ and\ Hygiene Household Meat Packaged\ Foods Periodicals Produce Seafood
       Snack\ Foods Snacks Starchy\ Foods]
  end

  def find_java_class(name)
    class_loader = @olap.raw_mondrian_connection.getClass.getClassLoader
    java.lang.Class.forName(name, true, class_loader)
  end

  def find_declared_method(java_object, method_name, *param_types)
    cls = java_object.is_a?(java.lang.Class) ? java_object : java_object.getClass
    while cls
      begin
        method = cls.getDeclaredMethod(method_name, param_types.to_java(java.lang.Class))
        method.setAccessible(true)
        return method
      rescue java.lang.NoSuchMethodException
        cls = cls.getSuperclass
      end
    end
    raise "Method #{method_name} not found on #{java_object}"
  end

  def find_declared_field(java_object, field_name)
    cls = java_object.is_a?(java.lang.Class) ? java_object : java_object.getClass
    while cls
      begin
        field = cls.getDeclaredField(field_name)
        field.setAccessible(true)
        return field
      rescue java.lang.NoSuchFieldException
        cls = cls.getSuperclass
      end
    end
    raise "Field #{field_name} not found on #{java_object}"
  end

  def sales_cube
    connection = @olap.raw_mondrian_connection
    connection.getSchemaReader.withLocus.getCubes[0]
  end

  def get_cube(name)
    connection = @olap.raw_mondrian_connection
    cubes = connection.getSchemaReader.withLocus.getCubes
    cubes.to_a.find { |c| c.getName == name } || cubes[0]
  end

  def get_star_measure(cube_name, measure_name)
    cube = get_cube(cube_name)
    measure_id = Java::MondrianOlap::Util.parseIdentifier(measure_name)
    measure = cube.getSchemaReader(nil).getMemberByUniqueName(measure_id, true)
    Java::MondrianRolap::RolapStar.getStarMeasure(measure)
  end

  # Creates a CellRequest with constrained columns, mirroring BatchTestCase.createRequest().
  # All referenced classes/methods are public.
  def create_cell_request(cube_name, measure_name, tables, columns, values, constraint = nil)
    star_measure = get_star_measure(cube_name, measure_name)
    star = star_measure.getStar
    request = Java::MondrianRolapAgg::CellRequest.new(star_measure, false, false)

    tables.each_with_index do |table, i|
      column = star.lookupColumn(table, columns[i])
      predicate = Java::MondrianRolapAgg::ValueColumnPredicate.new(column, values[i])
      request.addConstrainedColumn(column, predicate)
    end

    apply_constraint(request, star, constraint) if constraint
    request
  end

  def apply_constraint(request, star, constraint)
    constraint_columns = constraint[:tables].each_with_index.map do |table, i|
      star.lookupColumn(table, constraint[:columns][i])
    end

    bit_key = Java::MondrianRolap::BitKey::Factory.makeBitKey(star.getColumnCount)
    constraint_columns.each { |col| bit_key.set(col.getBitPosition) }

    # Build compound AND predicates from value tuples, then OR them together
    and_predicates = constraint[:values].map do |value_set|
      value_predicates = java.util.ArrayList.new
      value_set.each_with_index do |val, i|
        value_predicates.add(Java::MondrianRolapAgg::ValueColumnPredicate.new(constraint_columns[i], val))
      end
      Java::MondrianRolapAgg::AndPredicate.new(value_predicates)
    end

    # addAggregateList takes (BitKey, StarPredicate) — call once per compound predicate
    and_predicates.each { |pred| request.addAggregateList(bit_key, pred) }
  end

  def make_constraint_country_state(compound_members)
    {
      tables: %w[store store],
      columns: %w[store_country store_state],
      values: compound_members
    }
  end

  # BatchLoader is package-private — use reflection to instantiate.
  def create_batch_loader(use_grouping_sets, cube)
    star = cube.getStar
    dialect = star.getSqlQueryDialect

    unless use_grouping_sets.nil?
      dialect = dialect_with_grouping_sets(dialect, use_grouping_sets)
    end

    locus = Java::MondrianServer::Locus.peek
    agg_mgr = @execution.getMondrianStatement.getMondrianConnection.getServer.getAggregationManager

    batch_loader_class = find_java_class("mondrian.rolap.BatchLoader")
    constructor = batch_loader_class.getDeclaredConstructors.find { |c| c.getParameterCount == 4 }
    constructor.setAccessible(true)
    constructor.newInstance(locus, agg_mgr.cacheMgr, dialect, cube)
  end

  def dialect_with_grouping_sets(dialect, supports)
    handler = DialectInvocationHandler.new(dialect, supports)
    dialect_class = find_java_class("mondrian.spi.Dialect")
    java.lang.reflect.Proxy.newProxyInstance(
      dialect.getClass.getClassLoader,
      [dialect_class].to_java(java.lang.Class),
      handler)
  end

  # Package-private method — needs reflection
  def invoke_should_use_grouping_function(batch_loader)
    find_declared_method(batch_loader, "shouldUseGroupingFunction").invoke(batch_loader)
  end

  # Batch is an inner class of package-private BatchLoader — use reflection.
  def create_batch_from_request(batch_loader, cell_request)
    batch_class = find_java_class("mondrian.rolap.BatchLoader$Batch")
    constructor = batch_class.getDeclaredConstructors.find { |c| c.getParameterCount == 2 }
    constructor.setAccessible(true)
    constructor.newInstance(batch_loader, cell_request)
  end

  # Mirrors BatchTestCase.createBatch() — creates a Batch with all value combinations.
  # Initial request uses ALL columns with first value from each field.
  def create_multi_batch(batch_loader, table_names, field_names, field_values, cube_name, measure, constraint = nil)
    initial_values = field_values.map { |field_vals| field_vals[0] }
    request = create_cell_request(cube_name, measure, table_names, field_names, initial_values, constraint)
    batch = create_batch_from_request(batch_loader, request)
    add_batch_requests(batch, cube_name, measure, table_names, field_names, field_values, [], 0, constraint)
    batch
  end

  # Recursively generates all value combinations and adds each as a CellRequest.
  def add_batch_requests(batch, cube_name, measure, table_names, field_names, field_values, selected_values, position, constraint)
    if position < field_names.length
      field_values[position].each do |value|
        selected_values.push(value)
        add_batch_requests(batch, cube_name, measure, table_names, field_names, field_values, selected_values, position + 1, constraint)
        selected_values.pop
      end
    else
      request = create_cell_request(cube_name, measure, table_names, field_names, selected_values, constraint)
      batch.add(request)
    end
  end

  # Package-private static method — needs reflection
  def invoke_group_batches(batch_list)
    find_declared_method(find_java_class("mondrian.rolap.BatchLoader"), "groupBatches",
      java.util.List.java_class).invoke(nil, batch_list)
  end

  # Package-private static method — needs reflection
  def invoke_add_to_composite_batch(batch_loader, batch_groups, batch1, batch2)
    batch_class = find_java_class("mondrian.rolap.BatchLoader$Batch")
    find_declared_method(find_java_class("mondrian.rolap.BatchLoader"), "addToCompositeBatch",
      java.util.Map.java_class, batch_class, batch_class).invoke(nil, batch_groups, batch1, batch2)
  end

  # Package-private method — needs reflection
  def invoke_can_batch(batch, other)
    find_declared_method(batch, "canBatch",
      find_java_class("mondrian.rolap.BatchLoader$Batch")).invoke(batch, other)
  end

  def get_batch_key(batch)
    find_declared_field(batch, "batchKey").get(batch)
  end

  def get_detailed_batch(composite_batch)
    find_declared_field(composite_batch, "detailedBatch").get(composite_batch)
  end

  def get_summary_batches(composite_batch)
    find_declared_field(composite_batch, "summaryBatches").get(composite_batch)
  end

  # Package-private constructor — needs reflection
  def create_composite_batch(detailed_batch)
    batch_class = find_java_class("mondrian.rolap.BatchLoader$Batch")
    composite_class = find_java_class("mondrian.rolap.BatchLoader$CompositeBatch")
    constructor = composite_class.getDeclaredConstructor(batch_class)
    constructor.setAccessible(true)
    constructor.newInstance(detailed_batch)
  end

  # Package-private method — needs reflection
  def add_to_summary(composite_batch, batch)
    find_declared_method(composite_batch, "add",
      find_java_class("mondrian.rolap.BatchLoader$Batch")).invoke(composite_batch, batch)
  end

  def invoke_get_constrained_columns_bit_key(batch)
    batch.getConstrainedColumnsBitKey
  end

  # Sets up Locus context for batch internal tests and yields.
  def with_batch_context
    connection = @olap.raw_mondrian_connection
    connection.getCacheControl(nil).flushSchemaCache
    statement = connection.getInternalStatement
    @execution = Java::MondrianServer::Execution.new(statement, 0)
    locus = Java::MondrianServer::Locus.new(@execution, "FastBatchingCellReaderTest", nil)
    Java::MondrianServer::Locus.push(locus)
    begin
      yield
    ensure
      Java::MondrianServer::Locus.pop(locus)
      @execution = nil
    end
  end
end

# Dialect proxy that overrides supportsGroupingSets.
# Defined at file level to avoid constant lookup issues.
class DialectInvocationHandler
  include java.lang.reflect.InvocationHandler

  def initialize(delegate, supports_grouping_sets)
    @delegate = delegate
    @supports_grouping_sets = supports_grouping_sets
  end

  def invoke(_proxy, method, args)
    if method.getName == "supportsGroupingSets"
      return @supports_grouping_sets
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

# SegmentCacheManager.Command implementation that calls CompositeBatch.load().
# Defined at file level to avoid constant lookup issues with JRuby Java class extension.
class LoadCommand < Java::MondrianRolapAgg::SegmentCacheManager::Command
  def initialize(locus, composite_batch, segment_futures)
    super()
    @locus = locus
    @composite_batch = composite_batch
    @segment_futures = segment_futures
  end

  def call
    @composite_batch.load(@segment_futures)
    nil
  end

  def getLocus
    @locus
  end
end
