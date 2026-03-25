# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2003-2005 Julian Hyde
# Copyright (C) 2005-2021 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/olap/fun/FunctionTest.java
describe "FunctionTest VisualTotals" do
  before(:all) do
    create_olap_connection
  end

  def full_error_message(exception)
    messages = []
    cause = exception
    while cause
      messages << cause.message.to_s if cause.message
      next_cause = cause.respond_to?(:cause) ? cause.cause : nil
      break if next_cause.nil? || next_cause == cause
      cause = next_cause
    end
    messages.join("\n")
  end

  def assert_query_raises_with_cause(olap, mdx, pattern)
    error = assert_raises(Mondrian::OLAP::Error) { olap.execute(mdx) }
    full_message = full_error_message(error)
    assert full_message.include?(pattern),
      "Expected error containing '#{pattern}', got: #{full_message}"
  end

  # Java: FunctionTest#testVisualTotalsBasic
  it "basic VisualTotals with pattern" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select {[Measures].[Unit Sales]} on columns,
      {VisualTotals(
          {[Product].[All Products].[Food].[Baked Goods].[Bread],
           [Product].[All Products].[Food].[Baked Goods].[Bread].[Bagels],
           [Product].[All Products].[Food].[Baked Goods].[Bread].[Muffins]},
           "**Subtotal - *")} on rows
      from [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Product].[Food].[Baked Goods].[*Subtotal - Bread]}
      {[Product].[Food].[Baked Goods].[Bread].[Bagels]}
      {[Product].[Food].[Baked Goods].[Bread].[Muffins]}
      Row #0: 4,312
      Row #1: 815
      Row #2: 3,497
    RESULT
  end

  # Java: FunctionTest#testVisualTotalsConsecutively
  it "VisualTotals with consecutive duplicate members" do
    # Note that [Bagels] occurs 3 times, but only once does it
    # become a subtotal. Note that the subtotal does not include
    # the following [Bagels] member.
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select {[Measures].[Unit Sales]} on columns,
      {VisualTotals(
          {[Product].[All Products].[Food].[Baked Goods].[Bread],
           [Product].[All Products].[Food].[Baked Goods].[Bread].[Bagels],
           [Product].[All Products].[Food].[Baked Goods].[Bread].[Bagels],
           [Product].[All Products].[Food].[Baked Goods].[Bread].[Bagels].[Colony],
           [Product].[All Products].[Food].[Baked Goods].[Bread].[Bagels],
           [Product].[All Products].[Food].[Baked Goods].[Bread].[Muffins]},
           "**Subtotal - *")} on rows
      from [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Product].[Food].[Baked Goods].[*Subtotal - Bread]}
      {[Product].[Food].[Baked Goods].[Bread].[Bagels]}
      {[Product].[Food].[Baked Goods].[Bread].[*Subtotal - Bagels]}
      {[Product].[Food].[Baked Goods].[Bread].[Bagels].[Colony]}
      {[Product].[Food].[Baked Goods].[Bread].[Bagels]}
      {[Product].[Food].[Baked Goods].[Bread].[Muffins]}
      Row #0: 5,290
      Row #1: 815
      Row #2: 163
      Row #3: 163
      Row #4: 815
      Row #5: 3,497
    RESULT
  end

  # Java: FunctionTest#testVisualTotalsNoPattern
  it "VisualTotals without pattern" do
    # Note that the [Bread] visual member is just called [Bread].
    assert_axis_returns @olap,
      "VisualTotals(" \
      "    {[Product].[All Products].[Food].[Baked Goods].[Bread]," \
      "     [Product].[All Products].[Food].[Baked Goods].[Bread].[Bagels]," \
      "     [Product].[All Products].[Food].[Baked Goods].[Bread].[Muffins]})",
      <<~EXPECTED.chomp
        [Product].[Food].[Baked Goods].[Bread]
        [Product].[Food].[Baked Goods].[Bread].[Bagels]
        [Product].[Food].[Baked Goods].[Bread].[Muffins]
      EXPECTED
  end

  # Java: FunctionTest#testVisualTotalsWithFilter
  it "VisualTotals with filter" do
    # Note that [*Subtotal - Bread] still contains the
    # contribution of [Bagels] 815, which was filtered out.
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select {[Measures].[Unit Sales]} on columns,
      {Filter(
          VisualTotals(
              {[Product].[All Products].[Food].[Baked Goods].[Bread],
               [Product].[All Products].[Food].[Baked Goods].[Bread].[Bagels],
               [Product].[All Products].[Food].[Baked Goods].[Bread].[Muffins]},
              "**Subtotal - *"),
      [Measures].[Unit Sales] > 3400)} on rows
      from [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Product].[Food].[Baked Goods].[*Subtotal - Bread]}
      {[Product].[Food].[Baked Goods].[Bread].[Muffins]}
      Row #0: 4,312
      Row #1: 3,497
    RESULT
  end

  # Java: FunctionTest#testVisualTotalsNested
  it "nested VisualTotals" do
    # Yields the same -- no extra total.
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select {[Measures].[Unit Sales]} on columns,
      {VisualTotals(
          Filter(
              VisualTotals(
                  {[Product].[All Products].[Food].[Baked Goods].[Bread],
                   [Product].[All Products].[Food].[Baked Goods].[Bread].[Bagels],
                   [Product].[All Products].[Food].[Baked Goods].[Bread].[Muffins]},
                  "**Subtotal - *"),
          [Measures].[Unit Sales] > 3400),
          "Second total - *")} on rows
      from [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Product].[Food].[Baked Goods].[*Subtotal - Bread]}
      {[Product].[Food].[Baked Goods].[Bread].[Muffins]}
      Row #0: 4,312
      Row #1: 3,497
    RESULT
  end

  # Java: FunctionTest#testVisualTotalsFilterInside
  it "VisualTotals with filter inside" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select {[Measures].[Unit Sales]} on columns,
      {VisualTotals(
          Filter(
              {[Product].[All Products].[Food].[Baked Goods].[Bread],
               [Product].[All Products].[Food].[Baked Goods].[Bread].[Bagels],
               [Product].[All Products].[Food].[Baked Goods].[Bread].[Muffins]},
              [Measures].[Unit Sales] > 3400),
          "**Subtotal - *")} on rows
      from [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Product].[Food].[Baked Goods].[*Subtotal - Bread]}
      {[Product].[Food].[Baked Goods].[Bread].[Muffins]}
      Row #0: 3,497
      Row #1: 3,497
    RESULT
  end

  # Java: FunctionTest#testVisualTotalsOutOfOrder
  it "VisualTotals with out of order members" do
    # Note that [*Subtotal - Bread] 3497 does not include 815 for
    # bagels.
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select {[Measures].[Unit Sales]} on columns,
      {VisualTotals(
          {[Product].[All Products].[Food].[Baked Goods].[Bread].[Bagels],
           [Product].[All Products].[Food].[Baked Goods].[Bread],
           [Product].[All Products].[Food].[Baked Goods].[Bread].[Muffins]},
          "**Subtotal - *")} on rows
      from [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Product].[Food].[Baked Goods].[Bread].[Bagels]}
      {[Product].[Food].[Baked Goods].[*Subtotal - Bread]}
      {[Product].[Food].[Baked Goods].[Bread].[Muffins]}
      Row #0: 815
      Row #1: 3,497
      Row #2: 3,497
    RESULT
  end

  # Java: FunctionTest#testVisualTotalsGrandparentsAndOutOfOrder
  it "VisualTotals with grandparents and out of order" do
    # Note:
    # [*Subtotal - Food]  = 4513 = 815 + 311 + 3497
    # [*Subtotal - Bread] = 815, does not include muffins
    # [*Subtotal - Breakfast Foods] = 311 = 110 + 201, includes
    #     grandchildren
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select {[Measures].[Unit Sales]} on columns,
      {VisualTotals(
          {[Product].[All Products].[Food],
           [Product].[All Products].[Food].[Baked Goods].[Bread],
           [Product].[All Products].[Food].[Baked Goods].[Bread].[Bagels],
           [Product].[All Products].[Food].[Frozen Foods].[Breakfast Foods],
           [Product].[All Products].[Food].[Frozen Foods].[Breakfast Foods].[Pancake Mix].[Golden],
           [Product].[All Products].[Food].[Frozen Foods].[Breakfast Foods].[Pancake Mix].[Big Time],
           [Product].[All Products].[Food].[Baked Goods].[Bread].[Muffins]},
          "**Subtotal - *")} on rows
      from [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Product].[*Subtotal - Food]}
      {[Product].[Food].[Baked Goods].[*Subtotal - Bread]}
      {[Product].[Food].[Baked Goods].[Bread].[Bagels]}
      {[Product].[Food].[Frozen Foods].[*Subtotal - Breakfast Foods]}
      {[Product].[Food].[Frozen Foods].[Breakfast Foods].[Pancake Mix].[Golden]}
      {[Product].[Food].[Frozen Foods].[Breakfast Foods].[Pancake Mix].[Big Time]}
      {[Product].[Food].[Baked Goods].[Bread].[Muffins]}
      Row #0: 4,623
      Row #1: 815
      Row #2: 815
      Row #3: 311
      Row #4: 110
      Row #5: 201
      Row #6: 3,497
    RESULT
  end

  # Java: FunctionTest#testVisualTotalsCrossjoin
  it "VisualTotals with crossjoin raises error" do
    assert_query_raises_with_cause @olap,
      "SELECT {VisualTotals(Crossjoin([Gender].Members, [Store].children))} ON 0 FROM [Sales]",
      "Argument to 'VisualTotals' function must be a set of members; got set of tuples."
  end

  # Java: FunctionTest#testVisualTotalsAll
  # Test case for bug MONDRIAN-615, "VisualTotals doesn't work for the all member".
  it "VisualTotals works for the all member" do
    query = <<~MDX
      SELECT
        {[Measures].[Unit Sales]} ON 0,
        VisualTotals(
          {[Customers].[All Customers],
           [Customers].[USA],
           [Customers].[USA].[CA],
           [Customers].[USA].[OR]}) ON 1
      FROM [Sales]
    MDX
    assert_query_returns @olap, query, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Customers].[All Customers]}
      {[Customers].[USA]}
      {[Customers].[USA].[CA]}
      {[Customers].[USA].[OR]}
      Row #0: 142,407
      Row #1: 142,407
      Row #2: 74,748
      Row #3: 67,659
    RESULT

    # Check captions
    connection = @olap.raw_mondrian_connection
    internal_query = connection.parseQuery(query)
    result = connection.execute(internal_query)
    position_list = result.getAxes[1].getPositions
    assert_equal "All Customers", position_list.get(0).get(0).getCaption
    assert_equal "USA", position_list.get(1).get(0).getCaption
    assert_equal "CA", position_list.get(2).get(0).getCaption
  end

  # Java: FunctionTest#testVisualTotalsWithNamedSetAndPivot
  # Test case involving a named set and query pivoted. Suggested in
  # MONDRIAN-615, "VisualTotals doesn't work for the all member".
  it "VisualTotals with named set and pivot" do
    with_properties(EnableNativeNonEmpty: true) do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH SET [CA_OR] AS
            VisualTotals(
                {[Customers].[All Customers],
                 [Customers].[USA],
                 [Customers].[USA].[CA],
                 [Customers].[USA].[OR]})
        SELECT
            Drilldownlevel({[Time].[1997]}) ON 0,
            [CA_OR] ON 1
        FROM [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Time].[1997]}
        {[Time].[1997].[Q1]}
        {[Time].[1997].[Q2]}
        {[Time].[1997].[Q3]}
        {[Time].[1997].[Q4]}
        Axis #2:
        {[Customers].[All Customers]}
        {[Customers].[USA]}
        {[Customers].[USA].[CA]}
        {[Customers].[USA].[OR]}
        Row #0: 142,407
        Row #0: 36,177
        Row #0: 33,131
        Row #0: 35,310
        Row #0: 37,789
        Row #1: 142,407
        Row #1: 36,177
        Row #1: 33,131
        Row #1: 35,310
        Row #1: 37,789
        Row #2: 74,748
        Row #2: 16,890
        Row #2: 18,052
        Row #2: 18,370
        Row #2: 21,436
        Row #3: 67,659
        Row #3: 19,287
        Row #3: 15,079
        Row #3: 16,940
        Row #3: 16,353
      RESULT

      # same query, swap axes
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH SET [CA_OR] AS
            VisualTotals(
                {[Customers].[All Customers],
                 [Customers].[USA],
                 [Customers].[USA].[CA],
                 [Customers].[USA].[OR]})
        SELECT
            [CA_OR] ON 0,
            Drilldownlevel({[Time].[1997]}) ON 1
        FROM [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Customers].[All Customers]}
        {[Customers].[USA]}
        {[Customers].[USA].[CA]}
        {[Customers].[USA].[OR]}
        Axis #2:
        {[Time].[1997]}
        {[Time].[1997].[Q1]}
        {[Time].[1997].[Q2]}
        {[Time].[1997].[Q3]}
        {[Time].[1997].[Q4]}
        Row #0: 142,407
        Row #0: 142,407
        Row #0: 74,748
        Row #0: 67,659
        Row #1: 36,177
        Row #1: 36,177
        Row #1: 16,890
        Row #1: 19,287
        Row #2: 33,131
        Row #2: 33,131
        Row #2: 18,052
        Row #2: 15,079
        Row #3: 35,310
        Row #3: 35,310
        Row #3: 18,370
        Row #3: 16,940
        Row #4: 37,789
        Row #4: 37,789
        Row #4: 21,436
        Row #4: 16,353
      RESULT
    end
  end

  # Java: FunctionTest#testVisualTotalsIntersect
  # Tests that members generated by VisualTotals have correct identity.
  # Testcase for bug MONDRIAN-295, "Query generated by Excel 2007 gives incorrect results".
  it "VisualTotals with Intersect" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      WITH
      SET [XL_Row_Dim_0] AS 'VisualTotals(Distinct(Hierarchize({Ascendants([Customers].[All Customers].[USA]), Descendants([Customers].[All Customers].[USA])})))'
      SELECT
      NON EMPTY Hierarchize({[Time].[Year].members}) ON COLUMNS ,
      NON EMPTY Hierarchize(Intersect({DrilldownLevel({[Customers].[All Customers]})}, [XL_Row_Dim_0])) ON ROWS
      FROM [Sales]
      WHERE ([Measures].[Store Sales])
    MDX
      Axis #0:
      {[Measures].[Store Sales]}
      Axis #1:
      {[Time].[1997]}
      Axis #2:
      {[Customers].[All Customers]}
      {[Customers].[USA]}
      Row #0: 565,238.13
      Row #1: 565,238.13
    RESULT
  end

  # Java: FunctionTest#testVisualTotalsWithNamedSetAndPivotSameAxis
  # Testcase for bug MONDRIAN-668, "Intersect should return any VisualTotals members in right-hand set".
  it "VisualTotals with named set and pivot on same axis" do
    with_properties(EnableNativeNonEmpty: true) do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH SET [XL_Row_Dim_0] AS
         VisualTotals(
           Distinct(
             Hierarchize(
               {Ascendants([Store].[USA].[CA]),
                Descendants([Store].[USA].[CA])})))
        select NON EMPTY
          Hierarchize(
            Intersect(
              {DrilldownLevel({[Store].[USA]})},
              [XL_Row_Dim_0])) ON COLUMNS
        from [Sales]
        where [Measures].[Sales count]
      MDX
        Axis #0:
        {[Measures].[Sales Count]}
        Axis #1:
        {[Store].[USA]}
        {[Store].[USA].[CA]}
        Row #0: 24,442
        Row #0: 24,442
      RESULT

      # now with tuples
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH SET [XL_Row_Dim_0] AS
         VisualTotals(
           Distinct(
             Hierarchize(
               {Ascendants([Store].[USA].[CA]),
                Descendants([Store].[USA].[CA])})))
        select NON EMPTY
          Hierarchize(
            Intersect(
             [Marital Status].[M]
             * {DrilldownLevel({[Store].[USA]})}
             * [Gender].[F],
             [Marital Status].[M]
             * [XL_Row_Dim_0]
             * [Gender].[F])) ON COLUMNS
        from [Sales]
        where [Measures].[Sales count]
      MDX
        Axis #0:
        {[Measures].[Sales Count]}
        Axis #1:
        {[Marital Status].[M], [Store].[USA], [Gender].[F]}
        {[Marital Status].[M], [Store].[USA].[CA], [Gender].[F]}
        Row #0: 6,054
        Row #0: 6,054
      RESULT
    end
  end

  # Java: FunctionTest#testVisualTotalsDistinctCountMeasure
  # Testcase for bug MONDRIAN-682, "VisualTotals + Distinct-count measure gives wrong results".
  it "VisualTotals with distinct count measure" do
    # distinct measure
    assert_query_returns @olap, <<~MDX, <<~RESULT
      WITH SET [XL_Row_Dim_0] AS
       VisualTotals(
         Distinct(
           Hierarchize(
             {Ascendants([Store].[USA].[CA]),
              Descendants([Store].[USA].[CA])})))
      select NON EMPTY
        Hierarchize(
          Intersect(
            {DrilldownLevel({[Store].[All Stores]})},
            [XL_Row_Dim_0])) ON COLUMNS
      from [HR]
      where [Measures].[Number of Employees]
    MDX
      Axis #0:
      {[Measures].[Number of Employees]}
      Axis #1:
      {[Store].[All Stores]}
      {[Store].[USA]}
      Row #0: 193
      Row #0: 193
    RESULT

    # distinct measure with Beverly Hills and Los Angeles
    assert_query_returns @olap, <<~MDX, <<~RESULT
      WITH SET [XL_Row_Dim_0] AS
       VisualTotals(
         Distinct(
           Hierarchize(
             {Ascendants([Store].[USA].[CA].[Beverly Hills]),
              Descendants([Store].[USA].[CA].[Beverly Hills]),
              Ascendants([Store].[USA].[CA].[Los Angeles]),
              Descendants([Store].[USA].[CA].[Los Angeles])})))
      select NON EMPTY
        Hierarchize(
          Intersect(
            {DrilldownLevel({[Store].[All Stores]})},
            [XL_Row_Dim_0])) ON COLUMNS
      from [HR]
      where [Measures].[Number of Employees]
    MDX
      Axis #0:
      {[Measures].[Number of Employees]}
      Axis #1:
      {[Store].[All Stores]}
      {[Store].[USA]}
      Row #0: 110
      Row #0: 110
    RESULT

    # distinct measure on columns
    assert_query_returns @olap, <<~MDX, <<~RESULT
      WITH SET [XL_Row_Dim_0] AS
       VisualTotals(
         Distinct(
           Hierarchize(
             {Ascendants([Store].[USA].[CA]),
              Descendants([Store].[USA].[CA])})))
      select {[Measures].[Count], [Measures].[Number of Employees]} on COLUMNS,
       NON EMPTY
        Hierarchize(
          Intersect(
            {DrilldownLevel({[Store].[All Stores]})},
            [XL_Row_Dim_0])) ON ROWS
      from [HR]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Count]}
      {[Measures].[Number of Employees]}
      Axis #2:
      {[Store].[All Stores]}
      {[Store].[USA]}
      Row #0: 2,316
      Row #0: 193
      Row #1: 2,316
      Row #1: 193
    RESULT

    # distinct measure with tuples
    assert_query_returns @olap, <<~MDX, <<~RESULT
      WITH SET [XL_Row_Dim_0] AS
       VisualTotals(
         Distinct(
           Hierarchize(
             {Ascendants([Store].[USA].[CA]),
              Descendants([Store].[USA].[CA])})))
      select NON EMPTY
        Hierarchize(
          Intersect(
           [Marital Status].[M]
           * {DrilldownLevel({[Store].[USA]})}
           * [Gender].[F],
           [Marital Status].[M]
           * [XL_Row_Dim_0]
           * [Gender].[F])) ON COLUMNS
      from [Sales]
      where [Measures].[Customer count]
    MDX
      Axis #0:
      {[Measures].[Customer Count]}
      Axis #1:
      {[Marital Status].[M], [Store].[USA], [Gender].[F]}
      {[Marital Status].[M], [Store].[USA].[CA], [Gender].[F]}
      Row #0: 654
      Row #0: 654
    RESULT
  end

  # Java: FunctionTest#testVisualTotalsClassCast
  # Testcase for bug MONDRIAN-761, "VisualTotalMember cannot be cast to RolapCubeMember".
  it "VisualTotals does not cause ClassCastException" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      WITH  SET [XL_Row_Dim_0] AS
       VisualTotals(
         Distinct(
           Hierarchize(
             {Ascendants([Store].[USA].[WA].[Yakima]),
              Descendants([Store].[USA].[WA].[Yakima]),
              Ascendants([Store].[USA].[WA].[Walla Walla]),
              Descendants([Store].[USA].[WA].[Walla Walla]),
              Ascendants([Store].[USA].[WA].[Tacoma]),
              Descendants([Store].[USA].[WA].[Tacoma]),
              Ascendants([Store].[USA].[WA].[Spokane]),
              Descendants([Store].[USA].[WA].[Spokane]),
              Ascendants([Store].[USA].[WA].[Seattle]),
              Descendants([Store].[USA].[WA].[Seattle]),
              Ascendants([Store].[USA].[WA].[Bremerton]),
              Descendants([Store].[USA].[WA].[Bremerton]),
              Ascendants([Store].[USA].[OR]),
              Descendants([Store].[USA].[OR])})))
       SELECT NON EMPTY
       Hierarchize(
         Intersect(
           DrilldownMember(
             {{DrilldownMember(
               {{DrilldownMember(
                 {{DrilldownLevel(
                   {[Store].[All Stores]})}},
                 {[Store].[USA]})}},
               {[Store].[USA].[WA]})}},
             {[Store].[USA].[WA].[Bremerton]}),
             [XL_Row_Dim_0]))
      DIMENSION PROPERTIES
        PARENT_UNIQUE_NAME,
        [Store].[Store Name].[Store Type],
        [Store].[Store Name].[Store Manager],
        [Store].[Store Name].[Store Sqft],
        [Store].[Store Name].[Grocery Sqft],
        [Store].[Store Name].[Frozen Sqft],
        [Store].[Store Name].[Meat Sqft],
        [Store].[Store Name].[Has coffee bar],
        [Store].[Store Name].[Street address] ON COLUMNS
      FROM [HR]
      WHERE
        ([Measures].[Number of Employees])
      CELL PROPERTIES
        VALUE,
        FORMAT_STRING,
        LANGUAGE,
        BACK_COLOR,
        FORE_COLOR,
        FONT_FLAGS
    MDX
      Axis #0:
      {[Measures].[Number of Employees]}
      Axis #1:
      {[Store].[All Stores]}
      {[Store].[USA]}
      {[Store].[USA].[OR]}
      {[Store].[USA].[WA]}
      {[Store].[USA].[WA].[Bremerton]}
      {[Store].[USA].[WA].[Bremerton].[Store 3]}
      {[Store].[USA].[WA].[Seattle]}
      {[Store].[USA].[WA].[Spokane]}
      {[Store].[USA].[WA].[Tacoma]}
      {[Store].[USA].[WA].[Walla Walla]}
      {[Store].[USA].[WA].[Yakima]}
      Row #0: 419
      Row #0: 419
      Row #0: 136
      Row #0: 283
      Row #0: 62
      Row #0: 62
      Row #0: 62
      Row #0: 62
      Row #0: 74
      Row #0: 4
      Row #0: 19
    RESULT
  end

  # Java: FunctionTest#testVisualTotalsWithNamedSetOfTuples
  # Testcase for bug MONDRIAN-678, "VisualTotals gives UnsupportedOperationException calling getOrdinal".
  # Key difference from previous test is that there are multiple hierarchies in Named set.
  it "VisualTotals with named set of tuples" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      WITH SET [XL_Row_Dim_0] AS
       VisualTotals(
         Distinct(
           Hierarchize(
             {Ascendants([Customers].[All Customers].[USA].[CA].[Beverly Hills].[Ari Tweten]),
              Descendants([Customers].[All Customers].[USA].[CA].[Beverly Hills].[Ari Tweten]),
              Ascendants([Customers].[All Customers].[Mexico]),
              Descendants([Customers].[All Customers].[Mexico])})))
      select NON EMPTY
        Hierarchize(
          Intersect(
            (DrilldownMember(
              {{DrilldownMember(
                {{DrilldownLevel(
                  {[Customers].[All Customers]})}},
                {[Customers].[All Customers].[USA]})}},
              {[Customers].[All Customers].[USA].[CA]})),
              [XL_Row_Dim_0])) ON COLUMNS
      from [Sales]
      where [Measures].[Sales count]
    MDX
      Axis #0:
      {[Measures].[Sales Count]}
      Axis #1:
      {[Customers].[All Customers]}
      {[Customers].[USA]}
      {[Customers].[USA].[CA]}
      {[Customers].[USA].[CA].[Beverly Hills]}
      Row #0: 4
      Row #0: 4
      Row #0: 4
      Row #0: 4
    RESULT
  end

  # Java: FunctionTest#testVisualTotalsLevel
  it "VisualTotals members have correct level" do
    connection = @olap.raw_mondrian_connection
    internal_query = connection.parseQuery(<<~MDX)
      select {[Measures].[Unit Sales]} on columns,
      {[Product].[All Products],
       [Product].[All Products].[Food].[Baked Goods].[Bread],
       VisualTotals(
          {[Product].[All Products].[Food].[Baked Goods].[Bread],
           [Product].[All Products].[Food].[Baked Goods].[Bread].[Bagels],
           [Product].[All Products].[Food].[Baked Goods].[Bread].[Muffins]},
           "**Subtotal - *")} on rows
      from [Sales]
    MDX
    result = connection.execute(internal_query)
    row_positions = result.getAxes[1].getPositions

    member0 = row_positions.get(0).get(0)
    assert_equal "All Products", member0.getName
    assert_equal "(All)", member0.getLevel.getName

    member1 = row_positions.get(1).get(0)
    assert_equal "Bread", member1.getName
    assert_equal "Product Category", member1.getLevel.getName

    member2 = row_positions.get(2).get(0)
    assert_equal "*Subtotal - Bread", member2.getName
    assert_equal "Product Category", member2.getLevel.getName

    member3 = row_positions.get(3).get(0)
    assert_equal "Bagels", member3.getName
    assert_equal "Product Subcategory", member3.getLevel.getName

    member4 = row_positions.get(4).get(0)
    assert_equal "Muffins", member4.getName
    assert_equal "Product Subcategory", member4.getLevel.getName
  end

  # Java: FunctionTest#testVisualTotalsMemberInCalculation
  # Testcase for bug MONDRIAN-749, "Cannot use visual totals members in calculations".
  #
  # The bug is not currently fixed, so it is a negative test case. Row #2
  # cell #1 contains an exception, but should be "**Subtotal - Bread : Product Subcategory".
  it "visual totals member in calculation" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with member [Measures].[Foo] as
       [Product].CurrentMember.Name || ' : ' || [Product].Level.Name
      select {[Measures].[Unit Sales], [Measures].[Foo]} on columns,
      {[Product].[All Products],
       [Product].[All Products].[Food].[Baked Goods].[Bread],
       VisualTotals(
          {[Product].[All Products].[Food].[Baked Goods].[Bread],
           [Product].[All Products].[Food].[Baked Goods].[Bread].[Bagels],
           [Product].[All Products].[Food].[Baked Goods].[Bread].[Muffins]},
           "**Subtotal - *")} on rows
      from [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      {[Measures].[Foo]}
      Axis #2:
      {[Product].[All Products]}
      {[Product].[Food].[Baked Goods].[Bread]}
      {[Product].[Food].[Baked Goods].[*Subtotal - Bread]}
      {[Product].[Food].[Baked Goods].[Bread].[Bagels]}
      {[Product].[Food].[Baked Goods].[Bread].[Muffins]}
      Row #0: 266,773
      Row #0: All Products : (All)
      Row #1: 7,870
      Row #1: Bread : Product Category
      Row #2: 4,312
      Row #2: #ERR: mondrian.olap.fun.MondrianEvaluationException: Could not find an aggregator in the current evaluation context
      Row #3: 815
      Row #3: Bagels : Product Subcategory
      Row #4: 3,497
      Row #4: Muffins : Product Subcategory
    RESULT
  end
end
