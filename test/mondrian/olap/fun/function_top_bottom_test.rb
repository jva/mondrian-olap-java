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
describe "TopBottom functions" do
  before(:all) do
    create_olap_connection
  end

  # Assert that executing an axis expression raises an error whose root cause
  # message includes the given pattern. Mirrors Java's assertAxisThrows.
  def assert_axis_throws(expression, pattern, cube: "Sales")
    mdx = "SELECT {#{expression}} ON COLUMNS FROM [#{cube}]"
    error = assert_raises(Mondrian::OLAP::Error) { @olap.execute(mdx) }
    assert error.root_cause_message.include?(pattern),
      "Expected root cause containing '#{pattern}', got: #{error.root_cause_message}"
  end

  describe "DrilldownLevel" do
    # Java: FunctionTest#testDrilldownLevel
    it "drills down members at a specified level" do
      # Expect all children of USA
      assert_axis_returns @olap,
        "DrilldownLevel({[Store].[USA]}, [Store].[Store Country])",
        <<~EXPECTED.chomp
          [Store].[USA]
          [Store].[USA].[CA]
          [Store].[USA].[OR]
          [Store].[USA].[WA]
        EXPECTED

      # Expect same set, because [USA] is already drilled
      assert_axis_returns @olap,
        "DrilldownLevel({[Store].[USA], [Store].[USA].[CA]}, [Store].[Store Country])",
        <<~EXPECTED.chomp
          [Store].[USA]
          [Store].[USA].[CA]
        EXPECTED

      # Expect drill, because [USA] isn't already drilled. You can't
      # drill down on [CA] and get to [USA]
      assert_axis_returns @olap,
        "DrilldownLevel({[Store].[USA].[CA],[Store].[USA]}, [Store].[Store Country])",
        <<~EXPECTED.chomp
          [Store].[USA].[CA]
          [Store].[USA]
          [Store].[USA].[CA]
          [Store].[USA].[OR]
          [Store].[USA].[WA]
        EXPECTED

      assert_axis_returns @olap,
        "DrilldownLevel({[Store].[USA].[CA],[Store].[USA]},, 0)",
        <<~EXPECTED.chomp
          [Store].[USA].[CA]
          [Store].[USA].[CA].[Alameda]
          [Store].[USA].[CA].[Beverly Hills]
          [Store].[USA].[CA].[Los Angeles]
          [Store].[USA].[CA].[San Diego]
          [Store].[USA].[CA].[San Francisco]
          [Store].[USA]
          [Store].[USA].[CA]
          [Store].[USA].[OR]
          [Store].[USA].[WA]
        EXPECTED

      assert_axis_returns @olap,
        "DrilldownLevel({[Store].[USA].[CA],[Store].[USA]} * {[Gender].Members},, 0)",
        <<~EXPECTED.chomp
          {[Store].[USA].[CA], [Gender].[All Gender]}
          {[Store].[USA].[CA].[Alameda], [Gender].[All Gender]}
          {[Store].[USA].[CA].[Beverly Hills], [Gender].[All Gender]}
          {[Store].[USA].[CA].[Los Angeles], [Gender].[All Gender]}
          {[Store].[USA].[CA].[San Diego], [Gender].[All Gender]}
          {[Store].[USA].[CA].[San Francisco], [Gender].[All Gender]}
          {[Store].[USA].[CA], [Gender].[F]}
          {[Store].[USA].[CA].[Alameda], [Gender].[F]}
          {[Store].[USA].[CA].[Beverly Hills], [Gender].[F]}
          {[Store].[USA].[CA].[Los Angeles], [Gender].[F]}
          {[Store].[USA].[CA].[San Diego], [Gender].[F]}
          {[Store].[USA].[CA].[San Francisco], [Gender].[F]}
          {[Store].[USA].[CA], [Gender].[M]}
          {[Store].[USA].[CA].[Alameda], [Gender].[M]}
          {[Store].[USA].[CA].[Beverly Hills], [Gender].[M]}
          {[Store].[USA].[CA].[Los Angeles], [Gender].[M]}
          {[Store].[USA].[CA].[San Diego], [Gender].[M]}
          {[Store].[USA].[CA].[San Francisco], [Gender].[M]}
          {[Store].[USA], [Gender].[All Gender]}
          {[Store].[USA].[CA], [Gender].[All Gender]}
          {[Store].[USA].[OR], [Gender].[All Gender]}
          {[Store].[USA].[WA], [Gender].[All Gender]}
          {[Store].[USA], [Gender].[F]}
          {[Store].[USA].[CA], [Gender].[F]}
          {[Store].[USA].[OR], [Gender].[F]}
          {[Store].[USA].[WA], [Gender].[F]}
          {[Store].[USA], [Gender].[M]}
          {[Store].[USA].[CA], [Gender].[M]}
          {[Store].[USA].[OR], [Gender].[M]}
          {[Store].[USA].[WA], [Gender].[M]}
        EXPECTED

      assert_axis_returns @olap,
        "DrilldownLevel({[Store].[USA].[CA],[Store].[USA]} * {[Gender].Members},, 1)",
        <<~EXPECTED.chomp
          {[Store].[USA].[CA], [Gender].[All Gender]}
          {[Store].[USA].[CA], [Gender].[F]}
          {[Store].[USA].[CA], [Gender].[M]}
          {[Store].[USA].[CA], [Gender].[F]}
          {[Store].[USA].[CA], [Gender].[M]}
          {[Store].[USA], [Gender].[All Gender]}
          {[Store].[USA], [Gender].[F]}
          {[Store].[USA], [Gender].[M]}
          {[Store].[USA], [Gender].[F]}
          {[Store].[USA], [Gender].[M]}
        EXPECTED
    end
  end

  describe "DrilldownLevelTop" do
    # Java: FunctionTest#testDrilldownLevelTop
    it "drills down top N members at a level" do
      # <set>, <n>, <level>
      assert_axis_returns @olap,
        "DrilldownLevelTop({[Store].[USA]}, 2, [Store].[Store Country])",
        <<~EXPECTED.chomp
          [Store].[USA]
          [Store].[USA].[WA]
          [Store].[USA].[CA]
        EXPECTED

      # similarly DrilldownLevelBottom
      assert_axis_returns @olap,
        "DrilldownLevelBottom({[Store].[USA]}, 2, [Store].[Store Country])",
        <<~EXPECTED.chomp
          [Store].[USA]
          [Store].[USA].[OR]
          [Store].[USA].[CA]
        EXPECTED

      # <set>, <n>
      assert_axis_returns @olap,
        "DrilldownLevelTop({[Store].[USA]}, 2)",
        <<~EXPECTED.chomp
          [Store].[USA]
          [Store].[USA].[WA]
          [Store].[USA].[CA]
        EXPECTED

      # <n> greater than number of children
      assert_axis_returns @olap,
        "DrilldownLevelTop({[Store].[USA], [Store].[Canada]}, 4)",
        <<~EXPECTED.chomp
          [Store].[USA]
          [Store].[USA].[WA]
          [Store].[USA].[CA]
          [Store].[USA].[OR]
          [Store].[Canada]
          [Store].[Canada].[BC]
        EXPECTED

      # <n> negative
      assert_axis_returns @olap,
        "DrilldownLevelTop({[Store].[USA]}, 2 - 3)",
        "[Store].[USA]"

      # <n> zero
      assert_axis_returns @olap,
        "DrilldownLevelTop({[Store].[USA]}, 2 - 2)",
        "[Store].[USA]"

      # <n> null
      assert_axis_returns @olap,
        "DrilldownLevelTop({[Store].[USA]}, null)",
        "[Store].[USA]"

      # mixed bag, no level, all expanded
      assert_axis_returns @olap,
        "DrilldownLevelTop({[Store].[USA], " \
        "[Store].[USA].[CA].[San Francisco], " \
        "[Store].[All Stores], " \
        "[Store].[Canada].[BC]}, " \
        "2)",
        <<~EXPECTED.chomp
          [Store].[USA]
          [Store].[USA].[WA]
          [Store].[USA].[CA]
          [Store].[USA].[CA].[San Francisco]
          [Store].[USA].[CA].[San Francisco].[Store 14]
          [Store].[All Stores]
          [Store].[USA]
          [Store].[Canada]
          [Store].[Canada].[BC]
          [Store].[Canada].[BC].[Vancouver]
          [Store].[Canada].[BC].[Victoria]
        EXPECTED

      # mixed bag, only specified level expanded
      assert_axis_returns @olap,
        "DrilldownLevelTop({[Store].[USA], " \
        "[Store].[USA].[CA].[San Francisco], " \
        "[Store].[All Stores], " \
        "[Store].[Canada].[BC]}, 2, [Store].[Store City])",
        <<~EXPECTED.chomp
          [Store].[USA]
          [Store].[USA].[CA].[San Francisco]
          [Store].[USA].[CA].[San Francisco].[Store 14]
          [Store].[All Stores]
          [Store].[Canada].[BC]
        EXPECTED

      # bad level
      assert_axis_throws(
        "DrilldownLevelTop({[Store].[USA]}, 2, [Customers].[Country])",
        "Level '[Customers].[Country]' not compatible with member '[Store].[USA]'")
    end
  end

  describe "DrilldownMember" do
    # Java: FunctionTest#testDrilldownMemberEmptyExpr
    it "drills down level top with no level and with expression" do
      # no level, with expression
      assert_axis_returns @olap,
        "DrilldownLevelTop({[Store].[USA]}, 2, , [Measures].[Unit Sales])",
        <<~EXPECTED.chomp
          [Store].[USA]
          [Store].[USA].[WA]
          [Store].[USA].[CA]
        EXPECTED

      # reverse expression
      assert_axis_returns @olap,
        "DrilldownLevelTop({[Store].[USA]}, 2, , - [Measures].[Unit Sales])",
        <<~EXPECTED.chomp
          [Store].[USA]
          [Store].[USA].[OR]
          [Store].[USA].[CA]
        EXPECTED
    end

    # Java: FunctionTest#testDrilldownMember
    it "drills down members of first set that appear in second set" do
      # Expect all children of USA
      assert_axis_returns @olap,
        "DrilldownMember({[Store].[USA]}, {[Store].[USA]})",
        <<~EXPECTED.chomp
          [Store].[USA]
          [Store].[USA].[CA]
          [Store].[USA].[OR]
          [Store].[USA].[WA]
        EXPECTED

      # Expect all children of USA.CA and USA.OR
      assert_axis_returns @olap,
        "DrilldownMember({[Store].[USA].[CA], [Store].[USA].[OR]}, " \
        "{[Store].[USA].[CA], [Store].[USA].[OR], [Store].[USA].[WA]})",
        <<~EXPECTED.chomp
          [Store].[USA].[CA]
          [Store].[USA].[CA].[Alameda]
          [Store].[USA].[CA].[Beverly Hills]
          [Store].[USA].[CA].[Los Angeles]
          [Store].[USA].[CA].[San Diego]
          [Store].[USA].[CA].[San Francisco]
          [Store].[USA].[OR]
          [Store].[USA].[OR].[Portland]
          [Store].[USA].[OR].[Salem]
        EXPECTED

      # Second set is empty
      assert_axis_returns @olap,
        "DrilldownMember({[Store].[USA]}, {})",
        "[Store].[USA]"

      # Drill down a leaf member
      assert_axis_returns @olap,
        "DrilldownMember({[Store].[All Stores].[USA].[CA].[San Francisco].[Store 14]}, " \
        "{[Store].[USA].[CA].[San Francisco].[Store 14]})",
        "[Store].[USA].[CA].[San Francisco].[Store 14]"

      # Complex case with option recursive
      assert_axis_returns @olap,
        "DrilldownMember({[Store].[All Stores].[USA]}, " \
        "{[Store].[All Stores].[USA], [Store].[All Stores].[USA].[CA], " \
        "[Store].[All Stores].[USA].[CA].[San Diego], [Store].[All Stores].[USA].[WA]}, " \
        "RECURSIVE)",
        <<~EXPECTED.chomp
          [Store].[USA]
          [Store].[USA].[CA]
          [Store].[USA].[CA].[Alameda]
          [Store].[USA].[CA].[Beverly Hills]
          [Store].[USA].[CA].[Los Angeles]
          [Store].[USA].[CA].[San Diego]
          [Store].[USA].[CA].[San Diego].[Store 24]
          [Store].[USA].[CA].[San Francisco]
          [Store].[USA].[OR]
          [Store].[USA].[WA]
          [Store].[USA].[WA].[Bellingham]
          [Store].[USA].[WA].[Bremerton]
          [Store].[USA].[WA].[Seattle]
          [Store].[USA].[WA].[Spokane]
          [Store].[USA].[WA].[Tacoma]
          [Store].[USA].[WA].[Walla Walla]
          [Store].[USA].[WA].[Yakima]
        EXPECTED

      # Sets of tuples
      assert_axis_returns @olap,
        "DrilldownMember({([Store Type].[Supermarket], [Store].[USA])}, {[Store].[USA]})",
        <<~EXPECTED.chomp
          {[Store Type].[Supermarket], [Store].[USA]}
          {[Store Type].[Supermarket], [Store].[USA].[CA]}
          {[Store Type].[Supermarket], [Store].[USA].[OR]}
          {[Store Type].[Supermarket], [Store].[USA].[WA]}
        EXPECTED
    end
  end

  describe "BottomCount" do
    # Java: FunctionTest#testBottomCount
    it "returns bottom N members ordered by measure" do
      assert_axis_returns @olap,
        "BottomCount({[Promotion Media].[Media Type].members}, 2, [Measures].[Unit Sales])",
        <<~EXPECTED.chomp
          [Promotion Media].[Radio]
          [Promotion Media].[Sunday Paper, Radio, TV]
        EXPECTED
    end

    # Java: FunctionTest#testBottomCountUnordered
    it "returns bottom N members without ordering expression" do
      assert_axis_returns @olap,
        "BottomCount({[Promotion Media].[Media Type].members}, 2)",
        <<~EXPECTED.chomp
          [Promotion Media].[Sunday Paper, Radio, TV]
          [Promotion Media].[TV]
        EXPECTED
    end
  end

  describe "BottomPercent" do
    # Java: FunctionTest#testBottomPercent
    it "returns bottom members up to a percentage of total" do
      assert_axis_returns @olap,
        "BottomPercent(Filter({[Store].[All Stores].[USA].[CA].Children, [Store].[All Stores].[USA].[OR].Children, " \
        "[Store].[All Stores].[USA].[WA].Children}, ([Measures].[Unit Sales] > 0.0)), 100.0, [Measures].[Store Sales])",
        <<~EXPECTED.chomp
          [Store].[USA].[CA].[San Francisco]
          [Store].[USA].[WA].[Walla Walla]
          [Store].[USA].[WA].[Bellingham]
          [Store].[USA].[WA].[Yakima]
          [Store].[USA].[CA].[Beverly Hills]
          [Store].[USA].[WA].[Spokane]
          [Store].[USA].[WA].[Seattle]
          [Store].[USA].[WA].[Bremerton]
          [Store].[USA].[CA].[San Diego]
          [Store].[USA].[CA].[Los Angeles]
          [Store].[USA].[OR].[Portland]
          [Store].[USA].[WA].[Tacoma]
          [Store].[USA].[OR].[Salem]
        EXPECTED

      assert_axis_returns @olap,
        "BottomPercent({[Promotion Media].[Media Type].members}, 1, [Measures].[Unit Sales])",
        <<~EXPECTED.chomp
          [Promotion Media].[Radio]
          [Promotion Media].[Sunday Paper, Radio, TV]
        EXPECTED
    end
  end

  describe "BottomSum" do
    # Java: FunctionTest#testBottomSum
    it "returns bottom members up to a sum threshold" do
      assert_axis_returns @olap,
        "BottomSum({[Promotion Media].[Media Type].members}, 5000, [Measures].[Unit Sales])",
        <<~EXPECTED.chomp
          [Promotion Media].[Radio]
          [Promotion Media].[Sunday Paper, Radio, TV]
        EXPECTED
    end
  end

  describe "TopCount" do
    # Java: FunctionTest#testTopCount
    it "returns top N members ordered by measure" do
      assert_axis_returns @olap,
        "TopCount({[Promotion Media].[Media Type].members}, 2, [Measures].[Unit Sales])",
        <<~EXPECTED.chomp
          [Promotion Media].[No Media]
          [Promotion Media].[Daily Paper, Radio, TV]
        EXPECTED
    end

    # Java: FunctionTest#testTopCountUnordered
    it "returns top N members without ordering expression" do
      assert_axis_returns @olap,
        "TopCount({[Promotion Media].[Media Type].members}, 2)",
        <<~EXPECTED.chomp
          [Promotion Media].[Bulk Mail]
          [Promotion Media].[Cash Register Handout]
        EXPECTED
    end

    # Java: FunctionTest#testTopCountTuple
    it "returns top N members using a tuple expression" do
      assert_axis_returns @olap,
        "TopCount([Customers].[Name].members,2,(Time.[1997].[Q1],[Measures].[Store Sales]))",
        <<~EXPECTED.chomp
          [Customers].[USA].[WA].[Spokane].[Grace McLaughlin]
          [Customers].[USA].[WA].[Spokane].[Matt Bellah]
        EXPECTED
    end

    # Java: FunctionTest#testTopCountEmpty
    it "returns empty set when input is empty" do
      assert_axis_returns @olap,
        "TopCount(Filter({[Promotion Media].[Media Type].members}, 1=0), 2, [Measures].[Unit Sales])",
        ""
    end

    # Java: FunctionTest#testTopCountDepends
    it "depends on correct hierarchies" do
      # TODO: assertExprDependsOn not yet available
      skip "assertSetExprDependsOn not yet available"
    end

    # Java: FunctionTest#testTopCountHuge
    it "handles large result set with TopCount" do
      # Before optimizing (see FunUtil.partialSort), on a 2-core 32-bit 2.4GHz
      # machine, the 1st query took 14.5 secs, the 2nd query took 5.0 secs.
      # After optimizing, who knows?
      query = <<~MDX
        SELECT [Measures].[Store Sales] ON 0,
        TopCount([Time].[Month].members * [Customers].[Name].members, 3, [Measures].[Store Sales]) ON 1
        FROM [Sales]
      MDX
      expected = <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Store Sales]}
        Axis #2:
        {[Time].[1997].[Q1].[3], [Customers].[USA].[WA].[Spokane].[George Todero]}
        {[Time].[1997].[Q3].[7], [Customers].[USA].[WA].[Spokane].[James Horvat]}
        {[Time].[1997].[Q4].[11], [Customers].[USA].[WA].[Olympia].[Charles Stanley]}
        Row #0: 234.83
        Row #1: 199.46
        Row #2: 191.90
      RESULT
      assert_query_returns @olap, query, expected
      # Run a second time to exercise caching
      assert_query_returns @olap, query, expected
    end
  end

  describe "TopPercent" do
    # Java: FunctionTest#testTopPercent
    it "returns top members up to a percentage of total" do
      assert_axis_returns @olap,
        "TopPercent({[Promotion Media].[Media Type].members}, 70, [Measures].[Unit Sales])",
        "[Promotion Media].[No Media]"
    end
  end

  describe "TopSum" do
    # Java: FunctionTest#testTopSum
    it "returns top members up to a sum threshold" do
      assert_axis_returns @olap,
        "TopSum({[Promotion Media].[Media Type].members}, 200000, [Measures].[Unit Sales])",
        <<~EXPECTED.chomp
          [Promotion Media].[No Media]
          [Promotion Media].[Daily Paper, Radio, TV]
        EXPECTED
    end

    # Java: FunctionTest#testTopSumEmpty
    it "returns empty set when input is empty" do
      assert_axis_returns @olap,
        "TopSum(Filter({[Promotion Media].[Media Type].members}, 1=0), 200000, [Measures].[Unit Sales])",
        ""
    end
  end

  describe "Union" do
    # Java: FunctionTest#testUnionAll
    it "Union ALL preserves duplicates and order" do
      assert_axis_returns @olap,
        "Union({[Gender].[M]}, {[Gender].[F]}, ALL)",
        <<~EXPECTED.chomp
          [Gender].[M]
          [Gender].[F]
        EXPECTED
    end

    # Java: FunctionTest#testUnionAllTuple
    it "Union ALL with tuples does not repeat rows" do
      # With the bug, the last 8 rows are repeated.
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
        set [Set1] as 'Crossjoin({[Time].[1997].[Q1]:[Time].[1997].[Q4]},{[Store].[USA].[CA]:[Store].[USA].[OR]})'
        set [Set2] as 'Crossjoin({[Time].[1997].[Q2]:[Time].[1997].[Q3]},{[Store].[Mexico].[DF]:[Store].[Mexico].[Veracruz]})'
        select
        {[Measures].[Unit Sales]} ON COLUMNS,
        Union([Set1], [Set2], ALL) ON ROWS
        from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Time].[1997].[Q1], [Store].[USA].[CA]}
        {[Time].[1997].[Q1], [Store].[USA].[OR]}
        {[Time].[1997].[Q2], [Store].[USA].[CA]}
        {[Time].[1997].[Q2], [Store].[USA].[OR]}
        {[Time].[1997].[Q3], [Store].[USA].[CA]}
        {[Time].[1997].[Q3], [Store].[USA].[OR]}
        {[Time].[1997].[Q4], [Store].[USA].[CA]}
        {[Time].[1997].[Q4], [Store].[USA].[OR]}
        {[Time].[1997].[Q2], [Store].[Mexico].[DF]}
        {[Time].[1997].[Q2], [Store].[Mexico].[Guerrero]}
        {[Time].[1997].[Q2], [Store].[Mexico].[Jalisco]}
        {[Time].[1997].[Q2], [Store].[Mexico].[Veracruz]}
        {[Time].[1997].[Q3], [Store].[Mexico].[DF]}
        {[Time].[1997].[Q3], [Store].[Mexico].[Guerrero]}
        {[Time].[1997].[Q3], [Store].[Mexico].[Jalisco]}
        {[Time].[1997].[Q3], [Store].[Mexico].[Veracruz]}
        Row #0: 16,890
        Row #1: 19,287
        Row #2: 18,052
        Row #3: 15,079
        Row #4: 18,370
        Row #5: 16,940
        Row #6: 21,436
        Row #7: 16,353
        Row #8:
        Row #9:
        Row #10:
        Row #11:
        Row #12:
        Row #13:
        Row #14:
        Row #15:
      RESULT
    end

    # Java: FunctionTest#testUnion
    it "Union removes duplicates by default" do
      assert_axis_returns @olap,
        "Union({[Store].[USA], [Store].[USA], [Store].[USA].[OR]}, " \
        "{[Store].[USA].[CA], [Store].[USA]})",
        <<~EXPECTED.chomp
          [Store].[USA]
          [Store].[USA].[OR]
          [Store].[USA].[CA]
        EXPECTED
    end

    # Java: FunctionTest#testUnionEmptyBoth
    it "Union of two empty sets returns empty" do
      assert_axis_returns @olap,
        "Union({}, {})",
        ""
    end

    # Java: FunctionTest#testUnionEmptyRight
    it "Union with empty right set returns left set" do
      assert_axis_returns @olap,
        "Union({[Gender].[M]}, {})",
        "[Gender].[M]"
    end

    # Java: FunctionTest#testUnionTuple
    it "Union removes duplicate tuples" do
      assert_axis_returns @olap,
        "Union({" \
        " ([Gender].[M], [Marital Status].[S])," \
        " ([Gender].[F], [Marital Status].[S])" \
        "}, {" \
        " ([Gender].[M], [Marital Status].[M])," \
        " ([Gender].[M], [Marital Status].[S])" \
        "})",
        <<~EXPECTED.chomp
          {[Gender].[M], [Marital Status].[S]}
          {[Gender].[F], [Marital Status].[S]}
          {[Gender].[M], [Marital Status].[M]}
        EXPECTED
    end

    # Java: FunctionTest#testUnionTupleDistinct
    it "Union with Distinct flag removes duplicate tuples" do
      assert_axis_returns @olap,
        "Union({" \
        " ([Gender].[M], [Marital Status].[S])," \
        " ([Gender].[F], [Marital Status].[S])" \
        "}, {" \
        " ([Gender].[M], [Marital Status].[M])," \
        " ([Gender].[M], [Marital Status].[S])" \
        "}, Distinct)",
        <<~EXPECTED.chomp
          {[Gender].[M], [Marital Status].[S]}
          {[Gender].[F], [Marital Status].[S]}
          {[Gender].[M], [Marital Status].[M]}
        EXPECTED
    end

    # Java: FunctionTest#testUnionQuery
    it "Union in a complex crossjoin query returns correct number of rows" do
      mdx = <<~MDX
        select {[Measures].[Unit Sales],
        [Measures].[Store Cost],
        [Measures].[Store Sales]} on columns,
         Hierarchize(
           Union(
             Crossjoin(
               Crossjoin([Gender].[All Gender].children,
                         [Marital Status].[All Marital Status].children),
               Crossjoin([Customers].[All Customers].children,
                         [Product].[All Products].children) ),
             Crossjoin({([Gender].[All Gender].[M], [Marital Status].[All Marital Status].[M])},
               Crossjoin(
                 [Customers].[All Customers].[USA].children,
                 [Product].[All Products].children) ) )) on rows
        from Sales where ([Time].[1997])
      MDX
      result = @olap.execute(mdx)
      rows_axis = result.raw_cell_set.getAxes.get(1)
      assert_equal 45, rows_axis.getPositions.size
    end
  end

  describe "TopPercentWithAlias" do
    # Java: FunctionTest#testTopPercentWithAlias
    it "TopPercent with a named set alias returns the same result as without alias" do
      query_without_alias = <<~MDX
        select
         {[Measures].[Store Cost]}on rows,
         TopPercent([Product].[Brand Name].Members*[Time].[1997].children, 50, [Measures].[Unit Sales]) on columns
        from Sales
      MDX
      query_with_alias = <<~MDX
        with
         set [*aaa] as '[Product].[Brand Name].Members*[Time].[1997].children'
        select
         {[Measures].[Store Cost]}on rows,
         TopPercent([*aaa], 50, [Measures].[Unit Sales]) on columns
        from Sales
      MDX
      result_without_alias = @olap.execute(query_without_alias)
      formatted_without_alias = format_result(result_without_alias)
      result_with_alias = @olap.execute(query_with_alias)
      formatted_with_alias = format_result(result_with_alias)
      assert_equal formatted_without_alias, formatted_with_alias
    end
  end
end
