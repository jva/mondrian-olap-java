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
describe "FunctionTest Range and Rank" do
  before(:all) do
    create_olap_connection
  end

  def root_cause_message(exception)
    cause = exception
    cause = cause.cause while cause.cause && cause.cause != cause
    cause.message
  end

  def assert_query_raises_with_cause(olap, mdx, pattern)
    error = assert_raises(Mondrian::OLAP::Error) { olap.execute(mdx) }
    full_message = "#{error.message} #{root_cause_message(error)}"
    assert full_message.include?(pattern),
      "Expected error containing '#{pattern}', got: #{full_message}"
  end

  describe "Range" do
    # Java: FunctionTest#testRange
    it "returns members in range between two members" do
      assert_axis_returns @olap,
        "[Time].[1997].[Q1].[2] : [Time].[1997].[Q2].[5]",
        <<~EXPECTED.chomp
          [Time].[1997].[Q1].[2]
          [Time].[1997].[Q1].[3]
          [Time].[1997].[Q2].[4]
          [Time].[1997].[Q2].[5]
        EXPECTED

      # Testcase for bug XXXXX: braces required
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with set [Set1] as '[Product].[Drink]:[Product].[Food]'

        select [Set1] on columns, {[Measures].defaultMember} on rows

        from Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Product].[Drink]}
        {[Product].[Food]}
        Axis #2:
        {[Measures].[Unit Sales]}
        Row #0: 24,597
        Row #0: 191,940
      RESULT
    end

    # Java: FunctionTest#testNullRange
    # Tests that a null passed in returns an empty set in range function
    it "returns empty set when one end of range is null" do
      assert_axis_returns @olap,
        "[Time].[1997].[Q1].[2] : NULL",
        ""
    end

    # Java: FunctionTest#testTwoNullRange
    # Tests that an exception is thrown if both parameters in a range function are null.
    it "raises error when both range endpoints are null" do
      assert_query_raises_with_cause @olap,
        "select {NULL : NULL} on columns from Sales",
        "Cannot deduce type of call to function ':'"
    end

    # Java: FunctionTest#testRangeLarge
    # Large dimensions use a different member reader, therefore need to be tested separately.
    it "returns members in range for large dimension" do
      assert_axis_returns @olap,
        "[Customers].[USA].[CA].[San Francisco] : [Customers].[USA].[WA].[Bellingham]",
        <<~EXPECTED.chomp
          [Customers].[USA].[CA].[San Francisco]
          [Customers].[USA].[CA].[San Gabriel]
          [Customers].[USA].[CA].[San Jose]
          [Customers].[USA].[CA].[Santa Cruz]
          [Customers].[USA].[CA].[Santa Monica]
          [Customers].[USA].[CA].[Spring Valley]
          [Customers].[USA].[CA].[Torrance]
          [Customers].[USA].[CA].[West Covina]
          [Customers].[USA].[CA].[Woodland Hills]
          [Customers].[USA].[OR].[Albany]
          [Customers].[USA].[OR].[Beaverton]
          [Customers].[USA].[OR].[Corvallis]
          [Customers].[USA].[OR].[Lake Oswego]
          [Customers].[USA].[OR].[Lebanon]
          [Customers].[USA].[OR].[Milwaukie]
          [Customers].[USA].[OR].[Oregon City]
          [Customers].[USA].[OR].[Portland]
          [Customers].[USA].[OR].[Salem]
          [Customers].[USA].[OR].[W. Linn]
          [Customers].[USA].[OR].[Woodburn]
          [Customers].[USA].[WA].[Anacortes]
          [Customers].[USA].[WA].[Ballard]
          [Customers].[USA].[WA].[Bellingham]
        EXPECTED
    end

    # Java: FunctionTest#testRangeStartEqualsEnd
    it "returns single member when range start equals end" do
      assert_axis_returns @olap,
        "[Time].[1997].[Q3].[7] : [Time].[1997].[Q3].[7]",
        "[Time].[1997].[Q3].[7]"
    end

    # Java: FunctionTest#testRangeStartEqualsEndLarge
    it "returns single member when range start equals end for large dimension" do
      assert_axis_returns @olap,
        "[Customers].[USA].[CA] : [Customers].[USA].[CA]",
        "[Customers].[USA].[CA]"
    end

    # Java: FunctionTest#testRangeEndBeforeStart
    it "returns members in correct order when range end is before start" do
      assert_axis_returns @olap,
        "[Time].[1997].[Q3].[7] : [Time].[1997].[Q2].[5]",
        <<~EXPECTED.chomp
          [Time].[1997].[Q2].[5]
          [Time].[1997].[Q2].[6]
          [Time].[1997].[Q3].[7]
        EXPECTED
    end

    # Java: FunctionTest#testRangeEndBeforeStartLarge
    it "returns members in correct order when range end is before start for large dimension" do
      assert_axis_returns @olap,
        "[Customers].[USA].[WA] : [Customers].[USA].[CA]",
        <<~EXPECTED.chomp
          [Customers].[USA].[CA]
          [Customers].[USA].[OR]
          [Customers].[USA].[WA]
        EXPECTED
    end

    # Java: FunctionTest#testRangeBetweenDifferentLevelsIsError
    it "raises error when range spans different levels" do
      assert_query_raises_with_cause @olap,
        "select {[Time].[1997].[Q2] : [Time].[1997].[Q2].[5]} on columns from Sales",
        "Members must belong to the same level"
    end

    # Java: FunctionTest#testRangeBoundedByAll
    it "returns All member when range is bounded by All" do
      assert_axis_returns @olap,
        "[Gender] : [Gender]",
        "[Gender].[All Gender]"
    end

    # Java: FunctionTest#testRangeBoundedByAllLarge
    it "returns All member when range is bounded by All for large dimension" do
      assert_axis_returns @olap,
        "[Customers].DefaultMember : [Customers]",
        "[Customers].[All Customers]"
    end

    # Java: FunctionTest#testRangeBoundedByNull
    it "returns empty set when range is bounded by null member" do
      assert_axis_returns @olap,
        "[Gender].[F] : [Gender].[M].NextMember",
        ""
    end

    # Java: FunctionTest#testRangeBoundedByNullLarge
    it "returns empty set when range is bounded by null member for large dimension" do
      assert_axis_returns @olap,
        "[Customers].PrevMember : [Customers].[USA].[OR]",
        ""
    end

    # Java: FunctionTest#testSetContainingLevelFails
    it "raises error when set contains a level" do
      assert_query_raises_with_cause @olap,
        "select {[Store].[Store City]} on columns from Sales",
        "No function matches signature '{<Level>}'"
    end
  end

  describe "Bug fixes" do
    # Java: FunctionTest#testBug715177
    it "bug 715177: children returns immutable list, set operator makes it mutable" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH MEMBER [Product].[Non-Consumable].[Other] AS
         'Sum(Except( [Product].[Product Department].Members,
               TopCount([Product].[Product Department].Members, 3)),
               Measures.[Unit Sales])'
        SELECT
          { [Measures].[Unit Sales] } ON COLUMNS,
          { TopCount([Product].[Product Department].Members,3),
                      [Product].[Non-Consumable].[Other] } ON ROWS
        FROM [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Product].[Drink].[Alcoholic Beverages]}
        {[Product].[Drink].[Beverages]}
        {[Product].[Drink].[Dairy]}
        {[Product].[Non-Consumable].[Other]}
        Row #0: 6,838
        Row #1: 13,573
        Row #2: 4,186
        Row #3: 242,176
      RESULT
    end

    # Java: FunctionTest#testBug714707
    # Same issue as bug 715177 -- "children" returns immutable
    # list, which set operator must make mutable.
    it "bug 714707: children with union set operator" do
      assert_axis_returns @olap,
        "{[Store].[USA].[CA].children, [Store].[USA]}",
        <<~EXPECTED.chomp
          [Store].[USA].[CA].[Alameda]
          [Store].[USA].[CA].[Beverly Hills]
          [Store].[USA].[CA].[Los Angeles]
          [Store].[USA].[CA].[San Diego]
          [Store].[USA].[CA].[San Francisco]
          [Store].[USA]
        EXPECTED
    end

    # Java: FunctionTest#testBug715177c
    it "bug 715177c: Order with TopCount on children" do
      assert_axis_returns @olap,
        "Order(TopCount({[Store].[USA].[CA].children}," \
        " [Measures].[Unit Sales], 2), [Measures].[Unit Sales])",
        <<~EXPECTED.chomp
          [Store].[USA].[CA].[Alameda]
          [Store].[USA].[CA].[San Francisco]
          [Store].[USA].[CA].[Beverly Hills]
          [Store].[USA].[CA].[San Diego]
          [Store].[USA].[CA].[Los Angeles]
        EXPECTED
    end
  end

  describe "Rank" do
    # Java: FunctionTest#testRank
    it "returns rank of member within set" do
      # Member within set
      assert_expression_returns @olap,
        "Rank([Store].[USA].[CA], " \
        "{[Store].[USA].[OR]," \
        " [Store].[USA].[CA]," \
        " [Store].[USA]})", "2"

      # Member not in set
      assert_expression_returns @olap,
        "Rank([Store].[USA].[WA], " \
        "{[Store].[USA].[OR]," \
        " [Store].[USA].[CA]," \
        " [Store].[USA]})", "0"

      # Member not in empty set
      assert_expression_returns @olap,
        "Rank([Store].[USA].[WA], {})", "0"

      # Null member not in set returns null.
      assert_expression_returns @olap,
        "Rank([Store].Parent, " \
        "{[Store].[USA].[OR]," \
        " [Store].[USA].[CA]," \
        " [Store].[USA]})", ""

      # Null member in empty set. (MSAS returns an error "Formula error -
      # dimension count is not valid - in the Rank function" but I think
      # null is the correct behavior.)
      assert_expression_returns @olap,
        "Rank([Gender].Parent, {})", ""

      # Member occurs twice in set -- pick first
      assert_expression_returns @olap,
        "Rank([Store].[USA].[WA], " \
        "{[Store].[USA].[WA]," \
        " [Store].[USA].[CA]," \
        " [Store].[USA]," \
        " [Store].[USA].[WA]})", "1"

      # Tuple not in set
      assert_expression_returns @olap,
        "Rank(([Gender].[F], [Marital Status].[M]), " \
        "{([Gender].[F], [Marital Status].[S])," \
        " ([Gender].[M], [Marital Status].[S])," \
        " ([Gender].[M], [Marital Status].[M])})", "0"

      # Tuple in set
      assert_expression_returns @olap,
        "Rank(([Gender].[F], [Marital Status].[M]), " \
        "{([Gender].[F], [Marital Status].[S])," \
        " ([Gender].[M], [Marital Status].[S])," \
        " ([Gender].[F], [Marital Status].[M])})", "3"

      # Tuple not in empty set
      assert_expression_returns @olap,
        "Rank(([Gender].[F], [Marital Status].[M]), " \
        "{})", "0"

      # Partially null tuple in set, returns null
      assert_expression_returns @olap,
        "Rank(([Gender].[F], [Marital Status].Parent), " \
        "{([Gender].[F], [Marital Status].[S])," \
        " ([Gender].[M], [Marital Status].[S])," \
        " ([Gender].[F], [Marital Status].[M])})", ""
    end

    # Java: FunctionTest#testRankWithExpr
    # Skip: PostgreSQL returns BigDecimal for aggregate values, causing ClassCastException
    # in RankFunDef$SortedListCalc when comparing Double vs BigDecimal. Java tests pass on MySQL.
    it "returns rank with expression-based ordering" do
      skip "BigDecimal/Double ClassCastException on PostgreSQL" if %w[postgresql].include?(MONDRIAN_DRIVER)
      # Note that [Good] and [Top Measure] have the same [Unit Sales]
      # value (5), but [Good] ranks 1 and [Top Measure] ranks 2. Even though
      # they are sorted descending on unit sales, they remain in their
      # natural order (member name) because MDX sorts are stable.
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member [Measures].[Sibling Rank] as ' Rank([Product].CurrentMember, [Product].CurrentMember.Siblings) '
          member [Measures].[Sales Rank] as ' Rank([Product].CurrentMember, Order([Product].Parent.Children, [Measures].[Unit Sales], DESC)) '
          member [Measures].[Sales Rank2] as ' Rank([Product].CurrentMember, [Product].Parent.Children, [Measures].[Unit Sales]) '
        select {[Measures].[Unit Sales], [Measures].[Sales Rank], [Measures].[Sales Rank2]} on columns,
         {[Product].[All Products].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].children} on rows
        from [Sales]
        WHERE ([Store].[USA].[OR].[Portland].[Store 11], [Time].[1997].[Q2].[6])
      MDX
        Axis #0:
        {[Store].[USA].[OR].[Portland].[Store 11], [Time].[1997].[Q2].[6]}
        Axis #1:
        {[Measures].[Unit Sales]}
        {[Measures].[Sales Rank]}
        {[Measures].[Sales Rank2]}
        Axis #2:
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Pearl]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Portsmouth]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Top Measure]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Walrus]}
        Row #0: 5
        Row #0: 1
        Row #0: 1
        Row #1:
        Row #1: 5
        Row #1: 5
        Row #2: 3
        Row #2: 3
        Row #2: 3
        Row #3: 5
        Row #3: 2
        Row #3: 1
        Row #4: 3
        Row #4: 4
        Row #4: 3
      RESULT
    end

    # Java: FunctionTest#testRankMembersWithTiedExpr
    # Skip: same BigDecimal/Double ClassCastException on PostgreSQL as testRankWithExpr
    it "returns rank for members with tied expression values" do
      skip "BigDecimal/Double ClassCastException on PostgreSQL" if %w[postgresql].include?(MONDRIAN_DRIVER)
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
         Set [Beers] as {[Product].[All Products].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].children}
          member [Measures].[Sales Rank] as ' Rank([Product].CurrentMember, [Beers], [Measures].[Unit Sales]) '
        select {[Measures].[Unit Sales], [Measures].[Sales Rank]} on columns,
         Generate([Beers], {[Product].CurrentMember}) on rows
        from [Sales]
        WHERE ([Store].[USA].[OR].[Portland].[Store 11], [Time].[1997].[Q2].[6])
      MDX
        Axis #0:
        {[Store].[USA].[OR].[Portland].[Store 11], [Time].[1997].[Q2].[6]}
        Axis #1:
        {[Measures].[Unit Sales]}
        {[Measures].[Sales Rank]}
        Axis #2:
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Pearl]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Portsmouth]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Top Measure]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Walrus]}
        Row #0: 5
        Row #0: 1
        Row #1:
        Row #1: 5
        Row #2: 3
        Row #2: 3
        Row #3: 5
        Row #3: 1
        Row #4: 3
        Row #4: 3
      RESULT
    end

    # Java: FunctionTest#testRankTuplesWithTiedExpr
    # Skip: same BigDecimal/Double ClassCastException on PostgreSQL as testRankWithExpr
    it "returns rank for tuples with tied expression values" do
      skip "BigDecimal/Double ClassCastException on PostgreSQL" if %w[postgresql].include?(MONDRIAN_DRIVER)
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
         Set [Beers for Store] as 'NonEmptyCrossJoin(
        [Product].[All Products].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].children,
        {[Store].[USA].[OR].[Portland].[Store 11]})'
          member [Measures].[Sales Rank] as ' Rank(([Product].CurrentMember,[Store].CurrentMember), [Beers for Store], [Measures].[Unit Sales]) '
        select {[Measures].[Unit Sales], [Measures].[Sales Rank]} on columns,
         Generate([Beers for Store], {([Product].CurrentMember, [Store].CurrentMember)}) on rows
        from [Sales]
        WHERE ([Time].[1997].[Q2].[6])
      MDX
        Axis #0:
        {[Time].[1997].[Q2].[6]}
        Axis #1:
        {[Measures].[Unit Sales]}
        {[Measures].[Sales Rank]}
        Axis #2:
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good], [Store].[USA].[OR].[Portland].[Store 11]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Portsmouth], [Store].[USA].[OR].[Portland].[Store 11]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Top Measure], [Store].[USA].[OR].[Portland].[Store 11]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Walrus], [Store].[USA].[OR].[Portland].[Store 11]}
        Row #0: 5
        Row #0: 1
        Row #1: 3
        Row #1: 3
        Row #2: 5
        Row #2: 1
        Row #3: 3
        Row #3: 3
      RESULT
    end

    # Java: FunctionTest#testRankWithExpr2
    # Skip: same BigDecimal/Double ClassCastException on PostgreSQL as testRankWithExpr
    it "returns rank with expression for various scenarios" do
      skip "BigDecimal/Double ClassCastException on PostgreSQL" if %w[postgresql].include?(MONDRIAN_DRIVER)
      # Data: Unit Sales
      # All gender 266,733
      # F          131,558
      # M          135,215
      assert_expression_returns @olap,
        "Rank([Gender].[All Gender]," \
        " {[Gender].Members}," \
        " [Measures].[Unit Sales])", "1"

      assert_expression_returns @olap,
        "Rank([Gender].[F]," \
        " {[Gender].Members}," \
        " [Measures].[Unit Sales])", "3"

      assert_expression_returns @olap,
        "Rank([Gender].[M]," \
        " {[Gender].Members}," \
        " [Measures].[Unit Sales])", "2"

      # Null member. Expression evaluates to null, therefore value does
      # not appear in the list of values, therefore the rank is null.
      assert_expression_returns @olap,
        "Rank([Gender].[All Gender].Parent," \
        " {[Gender].Members}," \
        " [Measures].[Unit Sales])", ""

      # Empty set. Value would appear after all elements in the empty set,
      # therefore rank is 1.
      # Note that SSAS gives error 'The first argument to the Rank function,
      # a tuple expression, should reference the same hierachies as the
      # second argument, a set expression'. I think that's because it can't
      # deduce a type for '{}'. SSAS's problem, not Mondrian's. :)
      assert_expression_returns @olap,
        "Rank([Gender].[M]," \
        " {}," \
        " [Measures].[Unit Sales])",
        "1"

      # As above, but SSAS can type-check this.
      assert_expression_returns @olap,
        "Rank([Gender].[M]," \
        " Filter(Gender.Members, 1 = 0)," \
        " [Measures].[Unit Sales])",
        "1"

      # Member is not in set
      assert_expression_returns @olap,
        "Rank([Gender].[M]," \
        " {[Gender].[All Gender], [Gender].[F]})",
        "0"

      # Even though M is not in the set, its value lies between [All Gender]
      # and [F].
      assert_expression_returns @olap,
        "Rank([Gender].[M]," \
        " {[Gender].[All Gender], [Gender].[F]}," \
        " [Measures].[Unit Sales])", "2"

      # Expr evaluates to null for some values of set.
      assert_expression_returns @olap,
        "Rank([Product].[Non-Consumable].[Household]," \
        " {[Product].[Food], [Product].[All Products], [Product].[Drink].[Dairy]}," \
        " [Product].CurrentMember.Parent)", "2"

      # Expr evaluates to null for all values in the set.
      assert_expression_returns @olap,
        "Rank([Gender].[M]," \
        " {[Gender].[All Gender], [Gender].[F]}," \
        " [Marital Status].[All Marital Status].Parent)", "1"
    end

    # Java: FunctionTest#testRankWithNulls
    # Tests the 3-arg version of the RANK function with a value which returns null within a set of nulls.
    it "returns rank with nulls in 3-arg form" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member [Measures].[X] as
        'iif([Measures].[Store Sales]=777,
        [Measures].[Store Sales],Null)'
        member [Measures].[Y] as 'Rank([Gender].[M],
        {[Measures].[X],[Measures].[X],[Measures].[X]},
         [Marital Status].[All Marital Status].Parent)'
        select {[Measures].[Y]} on columns from Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Y]}
        Row #0: 1
      RESULT
    end

    # Java: FunctionTest#testRankHuge
    # Tests a RANK function which is so large that we need to use caching
    # in order to execute it efficiently.
    it "executes huge rank query efficiently with caching" do
      # If caching is disabled, don't even try -- it will take too long.
      skip "Requires EnableExpCache" unless Java::MondrianOlap::MondrianProperties.instance.EnableExpCache.get

      mdx = "WITH \n" \
        "  MEMBER [Measures].[Rank among products] \n" \
        "    AS ' Rank([Product].CurrentMember, " \
        "            Order([Product].members, " \
        "            [Measures].[Unit Sales], BDESC)) '\n" \
        "SELECT CrossJoin(\n" \
        "  [Gender].members,\n" \
        "  {[Measures].[Unit Sales],\n" \
        "   [Measures].[Rank among products]}) ON COLUMNS,\n" \
        "  {[Product].members} ON ROWS\n" \
        "FROM [Sales]"

      connection = @olap.raw_mondrian_connection
      query = connection.parseQuery(mdx)
      result = connection.execute(query)
      axes = result.getAxes
      rows_axis = axes[1]
      row_count = rows_axis.getPositions.size
      assert_equal 2256, row_count

      # [All Products], [All Gender], [Rank]
      cell = result.getCell([1, 0].to_java(:int))
      assert_equal "1", cell.getFormattedValue

      # [Robust Monthly Sports Magazine]
      member = rows_axis.getPositions.get(row_count - 1).get(0)
      assert_equal "Robust Monthly Sports Magazine", member.getName

      # [Robust Monthly Sports Magazine], [All Gender], [Unit Sales]
      cell = result.getCell([0, row_count - 1].to_java(:int))
      assert_equal "152", cell.getFormattedValue

      # [Robust Monthly Sports Magazine], [All Gender], [Rank]
      cell = result.getCell([1, row_count - 1].to_java(:int))
      assert_equal "1,871", cell.getFormattedValue

      # [Robust Monthly Sports Magazine], [Gender].[F], [Unit Sales]
      cell = result.getCell([2, row_count - 1].to_java(:int))
      assert_equal "90", cell.getFormattedValue

      # [Robust Monthly Sports Magazine], [Gender].[F], [Rank]
      cell = result.getCell([3, row_count - 1].to_java(:int))
      assert_equal "1,150", cell.getFormattedValue

      # [Robust Monthly Sports Magazine], [Gender].[M], [Unit Sales]
      cell = result.getCell([4, row_count - 1].to_java(:int))
      assert_equal "62", cell.getFormattedValue

      # [Robust Monthly Sports Magazine], [Gender].[M], [Rank]
      cell = result.getCell([5, row_count - 1].to_java(:int))
      assert_equal "2,147", cell.getFormattedValue
    end
  end
end
