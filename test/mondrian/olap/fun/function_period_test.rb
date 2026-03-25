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
describe "Period Functions" do
  before(:all) do
    create_olap_connection
  end

  # Execute an axis expression and return the single member, or nil if the
  # axis is empty. Mirrors Java's TestContext#executeSingletonAxis.
  def execute_singleton_axis(expression, cube: "Sales")
    mdx = "SELECT {#{expression}} ON COLUMNS FROM [#{cube}]"
    result = @olap.execute(mdx)
    cell_set = result.raw_cell_set
    axis = cell_set.getAxes.get(0)
    positions = axis.getPositions
    case positions.size
    when 0
      nil
    when 1
      positions.get(0).getMembers.get(0)
    else
      raise "Expression returned #{positions.size} positions, expected 0 or 1"
    end
  end

  # Assert that executing an axis expression raises an error whose root cause
  # message includes the given pattern. Mirrors Java's assertAxisThrows.
  def assert_axis_throws(expression, pattern, cube: "Sales")
    mdx = "SELECT {#{expression}} ON COLUMNS FROM [#{cube}]"
    error = assert_raises(Mondrian::OLAP::Error) { @olap.execute(mdx) }
    assert error.root_cause_message.include?(pattern),
      "Expected root cause containing '#{pattern}', got: #{error.root_cause_message}"
  end

  # Assert that executing MDX raises an error whose root cause message
  # includes the given pattern. Wraps assert_raises + root_cause_message.
  def assert_mdx_raises(mdx, pattern)
    error = assert_raises(Mondrian::OLAP::Error) { @olap.execute(mdx) }
    assert error.root_cause_message.include?(pattern),
      "Expected root cause containing '#{pattern}', got: #{error.root_cause_message}"
  end

  describe "ParallelPeriod early" do
    # Java: FunctionTest#testParallelPeriodMinValue
    it "handles Integer.MIN_VALUE in ParallelPeriod" do
      # By running the query and getting a result without an exception, we should assert the return value which will
      # have empty rows, because the parallel period value is too large, so rows will be empty
      # data, but it will still return a result.
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
        member [measures].[foo] as
        '([Measures].[unit sales],
        ParallelPeriod([Time].[Quarter], -2147483648))'
        select
        [measures].[foo] on columns,
        [time].[1997].children on rows
        from [sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[foo]}
        Axis #2:
        {[Time].[1997].[Q1]}
        {[Time].[1997].[Q2]}
        {[Time].[1997].[Q3]}
        {[Time].[1997].[Q4]}
        Row #0:#{' '}
        Row #1:#{' '}
        Row #2:#{' '}
        Row #3:#{' '}
      RESULT
    end

    # Java: FunctionTest#testLagMinValue
    it "handles Integer.MIN_VALUE in Lag" do
      # By running the query and getting a result without an exception, we should assert the return value which will
      # have empty rows, because the lag value is too large for the traversal it needs to make, so rows will be empty
      # data, but it will still return a result.
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
        member [measures].[foo] as
        '([Measures].[unit sales], [Time].[1997].[Q1].Lag(-2147483648))'
        select
        [measures].[foo] on columns,
        [time].[1997].children on rows
        from [sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[foo]}
        Axis #2:
        {[Time].[1997].[Q1]}
        {[Time].[1997].[Q2]}
        {[Time].[1997].[Q3]}
        {[Time].[1997].[Q4]}
        Row #0:#{' '}
        Row #1:#{' '}
        Row #2:#{' '}
        Row #3:#{' '}
      RESULT
    end

    # Java: FunctionTest#testParallelPeriodWithSlicer
    it "ParallelPeriod with Aggregate function works" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        With
        Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Time],[*BASE_MEMBERS_Product])'
        Set [*BASE_MEMBERS_Measures] as '{[Measures].[*FORMATTED_MEASURE_0], [Measures].[*FORMATTED_MEASURE_1]}'
        Set [*BASE_MEMBERS_Time] as '{[Time].[1997].[Q2].[6]}'
        Set [*NATIVE_MEMBERS_Time] as 'Generate([*NATIVE_CJ_SET], {[Time].[Time].CurrentMember})'
        Set [*BASE_MEMBERS_Product] as '{[Product].[All Products].[Drink],[Product].[All Products].[Food]}'
        Set [*NATIVE_MEMBERS_Product] as 'Generate([*NATIVE_CJ_SET], {[Product].CurrentMember})'
        Member [Measures].[*FORMATTED_MEASURE_0] as '[Measures].[Customer Count]', FORMAT_STRING = '#,##0', SOLVE_ORDER=400
        Member [Measures].[*FORMATTED_MEASURE_1] as '([Measures].[Customer Count], ParallelPeriod([Time].[Quarter], 1, [Time].[Time].currentMember))', FORMAT_STRING = '#,##0', SOLVE_ORDER=-200
        Member [Product].[*FILTER_MEMBER] as 'Aggregate ([*NATIVE_MEMBERS_Product])', SOLVE_ORDER=-300
        Select
        [*BASE_MEMBERS_Measures] on columns, Non Empty Generate([*NATIVE_CJ_SET], {([Time].[Time].CurrentMember)}) on rows
        From [Sales]
        Where ([Product].[*FILTER_MEMBER])
      MDX
        Axis #0:
        {[Product].[*FILTER_MEMBER]}
        Axis #1:
        {[Measures].[*FORMATTED_MEASURE_0]}
        {[Measures].[*FORMATTED_MEASURE_1]}
        Axis #2:
        {[Time].[1997].[Q2].[6]}
        Row #0: 1,314
        Row #0: 1,447
      RESULT
    end

    # Java: FunctionTest#testParallelperiodOnLevelsString
    it "ParallelPeriod on Levels string" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member Measures.[Prev Unit Sales] as 'parallelperiod(Levels("[Time].[Month]"))'
        select {[Measures].[Unit Sales], Measures.[Prev Unit Sales]} ON COLUMNS,
        [Gender].members ON ROWS
        from [Sales]
        where [Time].[1997].[Q2].[5]
      MDX
        Axis #0:
        {[Time].[1997].[Q2].[5]}
        Axis #1:
        {[Measures].[Unit Sales]}
        {[Measures].[Prev Unit Sales]}
        Axis #2:
        {[Gender].[All Gender]}
        {[Gender].[F]}
        {[Gender].[M]}
        Row #0: 21,081
        Row #0: 20,179
        Row #1: 10,536
        Row #1: 9,990
        Row #2: 10,545
        Row #2: 10,189
      RESULT
    end

    # Java: FunctionTest#testParallelperiodOnStrToMember
    it "ParallelPeriod on StrToMember" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member Measures.[Prev Unit Sales] as 'parallelperiod(strToMember("[Time].[1997].[Q2]"))'
        select {[Measures].[Unit Sales], Measures.[Prev Unit Sales]} ON COLUMNS,
        [Gender].members ON ROWS
        from [Sales]
        where [Time].[1997].[Q2].[5]
      MDX
        Axis #0:
        {[Time].[1997].[Q2].[5]}
        Axis #1:
        {[Measures].[Unit Sales]}
        {[Measures].[Prev Unit Sales]}
        Axis #2:
        {[Gender].[All Gender]}
        {[Gender].[F]}
        {[Gender].[M]}
        Row #0: 21,081
        Row #0: 20,957
        Row #1: 10,536
        Row #1: 10,266
        Row #2: 10,545
        Row #2: 10,691
      RESULT

      assert_mdx_raises(
        "with member Measures.[Prev Unit Sales] as " \
        "'parallelperiod(strToMember(\"[Time].[Quarter]\"))'\n" \
        "select {[Measures].[Unit Sales], Measures.[Prev Unit Sales]} ON COLUMNS,\n" \
        "[Gender].members ON ROWS\n" \
        "from [Sales]\n" \
        "where [Time].[1997].[Q2].[5]",
        "Cannot find MDX member '[Time].[Quarter]'")
    end
  end

  describe "ClosingPeriod" do
    # Java: FunctionTest#testClosingPeriodNoArgs
    it "ClosingPeriod with no args" do
      # MSOLAP returns [1997].[Q4], because [Time].CurrentMember = [1997].
      member = execute_singleton_axis("ClosingPeriod()")
      assert_equal "[Time].[1997].[Q4]", member.getUniqueName
    end

    # Java: FunctionTest#testClosingPeriodLevel
    it "ClosingPeriod with level argument" do
      member = execute_singleton_axis("ClosingPeriod([Year])")
      assert_equal "[Time].[1997]", member.getUniqueName

      member = execute_singleton_axis("ClosingPeriod([Quarter])")
      assert_equal "[Time].[1997].[Q4]", member.getUniqueName

      member = execute_singleton_axis("ClosingPeriod([Month])")
      assert_equal "[Time].[1997].[Q4].[12]", member.getUniqueName

      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member [Measures].[Closing Unit Sales] as '([Measures].[Unit Sales], ClosingPeriod([Time].[Month]))'
        select non empty {[Measures].[Closing Unit Sales]} on columns,
         {Descendants([Time].[1997])} on rows
        from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Closing Unit Sales]}
        Axis #2:
        {[Time].[1997]}
        {[Time].[1997].[Q1]}
        {[Time].[1997].[Q1].[1]}
        {[Time].[1997].[Q1].[2]}
        {[Time].[1997].[Q1].[3]}
        {[Time].[1997].[Q2]}
        {[Time].[1997].[Q2].[4]}
        {[Time].[1997].[Q2].[5]}
        {[Time].[1997].[Q2].[6]}
        {[Time].[1997].[Q3]}
        {[Time].[1997].[Q3].[7]}
        {[Time].[1997].[Q3].[8]}
        {[Time].[1997].[Q3].[9]}
        {[Time].[1997].[Q4]}
        {[Time].[1997].[Q4].[10]}
        {[Time].[1997].[Q4].[11]}
        {[Time].[1997].[Q4].[12]}
        Row #0: 26,796
        Row #1: 23,706
        Row #2: 21,628
        Row #3: 20,957
        Row #4: 23,706
        Row #5: 21,350
        Row #6: 20,179
        Row #7: 21,081
        Row #8: 21,350
        Row #9: 20,388
        Row #10: 23,763
        Row #11: 21,697
        Row #12: 20,388
        Row #13: 26,796
        Row #14: 19,958
        Row #15: 25,270
        Row #16: 26,796
      RESULT

      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member [Measures].[Closing Unit Sales] as '([Measures].[Unit Sales], ClosingPeriod([Time].[Month]))'
        select {[Measures].[Unit Sales], [Measures].[Closing Unit Sales]} on columns,
         {[Time].[1997], [Time].[1997].[Q1], [Time].[1997].[Q1].[1], [Time].[1997].[Q1].[3], [Time].[1997].[Q4].[12]} on rows
        from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        {[Measures].[Closing Unit Sales]}
        Axis #2:
        {[Time].[1997]}
        {[Time].[1997].[Q1]}
        {[Time].[1997].[Q1].[1]}
        {[Time].[1997].[Q1].[3]}
        {[Time].[1997].[Q4].[12]}
        Row #0: 266,773
        Row #0: 26,796
        Row #1: 66,291
        Row #1: 23,706
        Row #2: 21,628
        Row #2: 21,628
        Row #3: 23,706
        Row #3: 23,706
        Row #4: 26,796
        Row #4: 26,796
      RESULT
    end

    # Java: FunctionTest#testClosingPeriodLevelNotInTimeFails
    it "ClosingPeriod with level not in Time hierarchy fails" do
      assert_axis_throws(
        "ClosingPeriod([Store].[Store City])",
        "The <level> and <member> arguments to ClosingPeriod must be from " \
        "the same hierarchy. The level was from '[Store]' but the member " \
        "was from '[Time]'")
    end

    # Java: FunctionTest#testClosingPeriodMember
    it "ClosingPeriod with member argument is not a valid form" do
      # This test is mistaken. Valid forms are ClosingPeriod(<level>)
      # and ClosingPeriod(<level>, <member>), but not
      # ClosingPeriod(<member>)
      # The Java test has this guarded by `if (false)`, so it is never executed.
      # We just verify the test is acknowledged.
      assert true
    end

    # Java: FunctionTest#testClosingPeriodMemberLeaf
    it "ClosingPeriod at leaf level returns null member" do
      # The first part of the Java test is guarded by `if (false)` — skipped.
      # The else branch runs when isDefaultNullMemberRepresentation() is true (the default).
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member [Measures].[Foo] as ClosingPeriod().uniquename
        select {[Measures].[Foo]} on columns,
          {[Time].[1997],
           [Time].[1997].[Q2],
           [Time].[1997].[Q2].[4]} on rows
        from Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Foo]}
        Axis #2:
        {[Time].[1997]}
        {[Time].[1997].[Q2]}
        {[Time].[1997].[Q2].[4]}
        Row #0: [Time].[1997].[Q4]
        Row #1: [Time].[1997].[Q2].[6]
        Row #2: [Time].[#null]
      RESULT
    end

    # Java: FunctionTest#testClosingPeriod
    it "ClosingPeriod with level and member arguments" do
      # TODO: assertMemberExprDependsOn not yet available

      assert_axis_returns @olap,
        "ClosingPeriod([Time].[Year], [Time].[1997].[Q3])", ""

      assert_axis_returns @olap,
        "ClosingPeriod([Time].[Quarter], [Time].[1997].[Q3])",
        "[Time].[1997].[Q3]"

      assert_axis_returns @olap,
        "ClosingPeriod([Time].[Month], [Time].[1997].[Q3])",
        "[Time].[1997].[Q3].[9]"

      assert_axis_returns @olap,
        "ClosingPeriod([Time].[Quarter], [Time].[1997])",
        "[Time].[1997].[Q4]"

      assert_axis_returns @olap,
        "ClosingPeriod([Time].[Year], [Time].[1997])", "[Time].[1997]"

      assert_axis_returns @olap,
        "ClosingPeriod([Time].[Month], [Time].[1997])",
        "[Time].[1997].[Q4].[12]"

      # leaf member
      assert_axis_returns @olap,
        "ClosingPeriod([Time].[Year], [Time].[1997].[Q3].[8])", ""

      assert_axis_returns @olap,
        "ClosingPeriod([Time].[Quarter], [Time].[1997].[Q3].[8])", ""

      assert_axis_returns @olap,
        "ClosingPeriod([Time].[Month], [Time].[1997].[Q3].[8])",
        "[Time].[1997].[Q3].[8]"

      # non-Time dimension
      assert_axis_returns @olap,
        "ClosingPeriod([Product].[Product Name], [Product].[All Products].[Drink])",
        "[Product].[Drink].[Dairy].[Dairy].[Milk].[Gorilla].[Gorilla Whole Milk]"

      assert_axis_returns @olap,
        "ClosingPeriod([Product].[Product Family], [Product].[All Products].[Drink])",
        "[Product].[Drink]"

      # 'all' level
      assert_axis_returns @olap,
        "ClosingPeriod([Product].[(All)], [Product].[All Products].[Drink])",
        ""

      # ragged
      assert_axis_returns @olap,
        "ClosingPeriod([Store].[Store City], [Store].[All Stores].[Israel])",
        "[Store].[Israel].[Israel].[Tel Aviv]",
        cube: "Sales Ragged"

      # Default member is [Time].[1997].
      assert_axis_returns @olap,
        "ClosingPeriod([Time].[Month])", "[Time].[1997].[Q4].[12]"

      assert_axis_returns @olap, "ClosingPeriod()", "[Time].[1997].[Q4]"

      assert_axis_returns @olap,
        "ClosingPeriod([Store].[Store State], [Store].[All Stores].[Israel])",
        "",
        cube: "Sales Ragged"

      assert_mdx_raises(
        "SELECT {ClosingPeriod([Time].[Year], [Store].[All Stores].[Israel])} ON COLUMNS FROM [Sales Ragged]",
        "The <level> and <member> arguments to ClosingPeriod must be " \
        "from the same hierarchy. The level was from '[Time]' but " \
        "the member was from '[Store]'")
    end

    # Java: FunctionTest#testClosingPeriodBelow
    it "ClosingPeriod below returns null" do
      member = execute_singleton_axis(
        "ClosingPeriod([Quarter],[1997].[Q3].[8])")
      assert_nil member
    end
  end

  describe "OpeningPeriod" do
    # Java: FunctionTest#testOpeningPeriod
    it "OpeningPeriod with various arguments" do
      assert_axis_returns @olap,
        "OpeningPeriod([Time].[Month], [Time].[1997].[Q3])",
        "[Time].[1997].[Q3].[7]"

      assert_axis_returns @olap,
        "OpeningPeriod([Time].[Quarter], [Time].[1997])",
        "[Time].[1997].[Q1]"

      assert_axis_returns @olap,
        "OpeningPeriod([Time].[Year], [Time].[1997])", "[Time].[1997]"

      assert_axis_returns @olap,
        "OpeningPeriod([Time].[Month], [Time].[1997])",
        "[Time].[1997].[Q1].[1]"

      assert_axis_returns @olap,
        "OpeningPeriod([Product].[Product Name], [Product].[All Products].[Drink])",
        "[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Imported Beer]"

      assert_axis_returns @olap,
        "OpeningPeriod([Store].[Store City], [Store].[All Stores].[Israel])",
        "[Store].[Israel].[Israel].[Haifa]",
        cube: "Sales Ragged"

      assert_axis_returns @olap,
        "OpeningPeriod([Store].[Store State], [Store].[All Stores].[Israel])",
        "",
        cube: "Sales Ragged"

      # Default member is [Time].[1997].
      assert_axis_returns @olap,
        "OpeningPeriod([Time].[Month])", "[Time].[1997].[Q1].[1]"

      assert_axis_returns @olap, "OpeningPeriod()", "[Time].[1997].[Q1]"

      assert_mdx_raises(
        "SELECT {OpeningPeriod([Time].[Year], [Store].[All Stores].[Israel])} ON COLUMNS FROM [Sales Ragged]",
        "The <level> and <member> arguments to OpeningPeriod must be " \
        "from the same hierarchy. The level was from '[Time]' but " \
        "the member was from '[Store]'")

      assert_axis_throws(
        "OpeningPeriod([Store].[Store City])",
        "The <level> and <member> arguments to OpeningPeriod must be " \
        "from the same hierarchy. The level was from '[Store]' but " \
        "the member was from '[Time]'")
    end

    # Java: FunctionTest#testOpeningPeriodNull
    it "OpeningPeriod with NULL argument throws exception" do
      # This tests new NULL functionality exception throwing.
      # The Java test expected "Failed to parse query" but the actual root cause
      # message is more specific.
      assert_axis_throws(
        "OpeningPeriod([Time].[Month], NULL)",
        "Function does not support NULL member parameter")
    end
  end

  describe "LastPeriods" do
    # Java: FunctionTest#testLastPeriods
    it "LastPeriods with various arguments" do
      assert_axis_returns @olap,
        "LastPeriods(0, [Time].[1998])", ""

      assert_axis_returns @olap,
        "LastPeriods(1, [Time].[1998])", "[Time].[1998]"

      assert_axis_returns @olap,
        "LastPeriods(-1, [Time].[1998])", "[Time].[1998]"

      assert_axis_returns @olap,
        "LastPeriods(2, [Time].[1998])",
        "[Time].[1997]\n[Time].[1998]"

      assert_axis_returns @olap,
        "LastPeriods(-2, [Time].[1997])",
        "[Time].[1997]\n[Time].[1998]"

      assert_axis_returns @olap,
        "LastPeriods(5000, [Time].[1998])",
        "[Time].[1997]\n[Time].[1998]"

      assert_axis_returns @olap,
        "LastPeriods(-5000, [Time].[1997])",
        "[Time].[1997]\n[Time].[1998]"

      assert_axis_returns @olap,
        "LastPeriods(2, [Time].[1998].[Q2])",
        "[Time].[1998].[Q1]\n[Time].[1998].[Q2]"

      assert_axis_returns @olap,
        "LastPeriods(4, [Time].[1998].[Q2])",
        <<~EXPECTED.chomp
          [Time].[1997].[Q3]
          [Time].[1997].[Q4]
          [Time].[1998].[Q1]
          [Time].[1998].[Q2]
        EXPECTED

      assert_axis_returns @olap,
        "LastPeriods(-2, [Time].[1997].[Q2])",
        "[Time].[1997].[Q2]\n[Time].[1997].[Q3]"

      assert_axis_returns @olap,
        "LastPeriods(-4, [Time].[1997].[Q2])",
        <<~EXPECTED.chomp
          [Time].[1997].[Q2]
          [Time].[1997].[Q3]
          [Time].[1997].[Q4]
          [Time].[1998].[Q1]
        EXPECTED

      assert_axis_returns @olap,
        "LastPeriods(5000, [Time].[1998].[Q2])",
        <<~EXPECTED.chomp
          [Time].[1997].[Q1]
          [Time].[1997].[Q2]
          [Time].[1997].[Q3]
          [Time].[1997].[Q4]
          [Time].[1998].[Q1]
          [Time].[1998].[Q2]
        EXPECTED

      assert_axis_returns @olap,
        "LastPeriods(-5000, [Time].[1998].[Q2])",
        <<~EXPECTED.chomp
          [Time].[1998].[Q2]
          [Time].[1998].[Q3]
          [Time].[1998].[Q4]
        EXPECTED

      assert_axis_returns @olap,
        "LastPeriods(2, [Time].[1998].[Q2].[5])",
        "[Time].[1998].[Q2].[4]\n[Time].[1998].[Q2].[5]"

      assert_axis_returns @olap,
        "LastPeriods(12, [Time].[1998].[Q2].[5])",
        <<~EXPECTED.chomp
          [Time].[1997].[Q2].[6]
          [Time].[1997].[Q3].[7]
          [Time].[1997].[Q3].[8]
          [Time].[1997].[Q3].[9]
          [Time].[1997].[Q4].[10]
          [Time].[1997].[Q4].[11]
          [Time].[1997].[Q4].[12]
          [Time].[1998].[Q1].[1]
          [Time].[1998].[Q1].[2]
          [Time].[1998].[Q1].[3]
          [Time].[1998].[Q2].[4]
          [Time].[1998].[Q2].[5]
        EXPECTED

      assert_axis_returns @olap,
        "LastPeriods(-2, [Time].[1998].[Q2].[4])",
        "[Time].[1998].[Q2].[4]\n[Time].[1998].[Q2].[5]"

      assert_axis_returns @olap,
        "LastPeriods(-12, [Time].[1997].[Q2].[6])",
        <<~EXPECTED.chomp
          [Time].[1997].[Q2].[6]
          [Time].[1997].[Q3].[7]
          [Time].[1997].[Q3].[8]
          [Time].[1997].[Q3].[9]
          [Time].[1997].[Q4].[10]
          [Time].[1997].[Q4].[11]
          [Time].[1997].[Q4].[12]
          [Time].[1998].[Q1].[1]
          [Time].[1998].[Q1].[2]
          [Time].[1998].[Q1].[3]
          [Time].[1998].[Q2].[4]
          [Time].[1998].[Q2].[5]
        EXPECTED

      assert_axis_returns @olap,
        "LastPeriods(2, [Gender].[M])",
        "[Gender].[F]\n[Gender].[M]"

      assert_axis_returns @olap,
        "LastPeriods(-2, [Gender].[F])",
        "[Gender].[F]\n[Gender].[M]"

      assert_axis_returns @olap,
        "LastPeriods(2, [Gender])", "[Gender].[All Gender]"

      assert_axis_returns @olap,
        "LastPeriods(2, [Gender].Parent)", ""
    end
  end

  describe "ParallelPeriod" do
    # Java: FunctionTest#testParallelPeriod
    it "ParallelPeriod with various arguments" do
      assert_axis_returns @olap,
        "parallelperiod([Time].[Quarter], 1, [Time].[1998].[Q1])",
        "[Time].[1997].[Q4]"

      assert_axis_returns @olap,
        "parallelperiod([Time].[Quarter], -1, [Time].[1997].[Q1])",
        "[Time].[1997].[Q2]"

      assert_axis_returns @olap,
        "parallelperiod([Time].[Year], 1, [Time].[1998].[Q1])",
        "[Time].[1997].[Q1]"

      assert_axis_returns @olap,
        "parallelperiod([Time].[Year], 1, [Time].[1998].[Q1].[1])",
        "[Time].[1997].[Q1].[1]"

      # No args, therefore finds parallel period to [Time].[1997], which
      # would be [Time].[1996], except that that doesn't exist, so null.
      assert_axis_returns @olap, "ParallelPeriod()", ""

      # Parallel period to [Time].[1997], which would be [Time].[1996],
      # except that that doesn't exist, so null.
      assert_axis_returns @olap,
        "ParallelPeriod([Time].[Year], 1, [Time].[1997])", ""

      # one parameter, level 2 above member
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH MEMBER [Measures].[Foo] AS
         ' ParallelPeriod([Time].[Year]).UniqueName '
        SELECT {[Measures].[Foo]} ON COLUMNS
        FROM [Sales]
        WHERE [Time].[1997].[Q3].[8]
      MDX
        Axis #0:
        {[Time].[1997].[Q3].[8]}
        Axis #1:
        {[Measures].[Foo]}
        Row #0: [Time].[#null]
      RESULT

      # one parameter, level 1 above member
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH MEMBER [Measures].[Foo] AS
         ' ParallelPeriod([Time].[Quarter]).UniqueName '
        SELECT {[Measures].[Foo]} ON COLUMNS
        FROM [Sales]
        WHERE [Time].[1997].[Q3].[8]
      MDX
        Axis #0:
        {[Time].[1997].[Q3].[8]}
        Axis #1:
        {[Measures].[Foo]}
        Row #0: [Time].[1997].[Q2].[5]
      RESULT

      # one parameter, level same as member
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH MEMBER [Measures].[Foo] AS
         ' ParallelPeriod([Time].[Month]).UniqueName '
        SELECT {[Measures].[Foo]} ON COLUMNS
        FROM [Sales]
        WHERE [Time].[1997].[Q3].[8]
      MDX
        Axis #0:
        {[Time].[1997].[Q3].[8]}
        Axis #1:
        {[Measures].[Foo]}
        Row #0: [Time].[1997].[Q3].[7]
      RESULT

      # one parameter, level below member
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH MEMBER [Measures].[Foo] AS
         ' ParallelPeriod([Time].[Month]).UniqueName '
        SELECT {[Measures].[Foo]} ON COLUMNS
        FROM [Sales]
        WHERE [Time].[1997].[Q3]
      MDX
        Axis #0:
        {[Time].[1997].[Q3]}
        Axis #1:
        {[Measures].[Foo]}
        Row #0: [Time].[#null]
      RESULT
    end

    # Java: FunctionTest#testParallelPeriodDepends
    it "ParallelPeriod expression dependencies" do
      # TODO: assertMemberExprDependsOn not yet available
      skip "assertMemberExprDependsOn not yet available"
    end

    # Java: FunctionTest#testParallelPeriodLevelLag
    it "ParallelPeriod with level and lag" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member [Measures].[Prev Unit Sales] as
                '([Measures].[Unit Sales], parallelperiod([Time].[Quarter], 2))'
        select
            crossjoin({[Measures].[Unit Sales], [Measures].[Prev Unit Sales]}, {[Marital Status].[All Marital Status].children}) on columns,
            {[Time].[1997].[Q3]} on rows
        from
            [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales], [Marital Status].[M]}
        {[Measures].[Unit Sales], [Marital Status].[S]}
        {[Measures].[Prev Unit Sales], [Marital Status].[M]}
        {[Measures].[Prev Unit Sales], [Marital Status].[S]}
        Axis #2:
        {[Time].[1997].[Q3]}
        Row #0: 32,815
        Row #0: 33,033
        Row #0: 33,101
        Row #0: 33,190
      RESULT
    end

    # Java: FunctionTest#testParallelPeriodLevel
    it "ParallelPeriod with level only" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
            member [Measures].[Prev Unit Sales] as
                '([Measures].[Unit Sales], parallelperiod([Time].[Quarter]))'
        select
            crossjoin({[Measures].[Unit Sales], [Measures].[Prev Unit Sales]}, {[Marital Status].[All Marital Status].[M]}) on columns,
            {[Time].[1997].[Q3].[8]} on rows
        from
            [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales], [Marital Status].[M]}
        {[Measures].[Prev Unit Sales], [Marital Status].[M]}
        Axis #2:
        {[Time].[1997].[Q3].[8]}
        Row #0: 10,957
        Row #0: 10,280
      RESULT
    end
  end

  describe "Ytd" do
    # Java: FunctionTest#testYtd
    it "Ytd with various arguments" do
      assert_axis_returns @olap,
        "Ytd()",
        "[Time].[1997]"

      assert_axis_returns @olap,
        "Ytd([Time].[1997].[Q3])",
        <<~EXPECTED.chomp
          [Time].[1997].[Q1]
          [Time].[1997].[Q2]
          [Time].[1997].[Q3]
        EXPECTED

      assert_axis_returns @olap,
        "Ytd([Time].[1997].[Q2].[4])",
        <<~EXPECTED.chomp
          [Time].[1997].[Q1].[1]
          [Time].[1997].[Q1].[2]
          [Time].[1997].[Q1].[3]
          [Time].[1997].[Q2].[4]
        EXPECTED

      assert_axis_throws(
        "Ytd([Store])",
        "Argument to function 'Ytd' must belong to Time hierarchy")

      # TODO: assertSetExprDependsOn not yet available
    end
  end

  describe "Generate plus Xtd" do
    # Java: FunctionTest#testGeneratePlusXtd
    it "Generate with Ytd, Qtd, and Mtd" do
      # Testcase for bug MONDRIAN-458, "error deducing type of
      # Ytd/Qtd/Mtd functions within Generate"
      assert_axis_returns @olap,
        "generate(\n" \
        "  {[Time].[1997].[Q1].[2], [Time].[1997].[Q3].[7]},\n" \
        " {Ytd( [Time].[Time].currentMember)})",
        <<~EXPECTED.chomp
          [Time].[1997].[Q1].[1]
          [Time].[1997].[Q1].[2]
          [Time].[1997].[Q1].[3]
          [Time].[1997].[Q2].[4]
          [Time].[1997].[Q2].[5]
          [Time].[1997].[Q2].[6]
          [Time].[1997].[Q3].[7]
        EXPECTED

      assert_axis_returns @olap,
        "generate(\n" \
        "  {[Time].[1997].[Q1].[2], [Time].[1997].[Q3].[7]},\n" \
        " {Ytd( [Time].[Time].currentMember)}, ALL)",
        <<~EXPECTED.chomp
          [Time].[1997].[Q1].[1]
          [Time].[1997].[Q1].[2]
          [Time].[1997].[Q1].[1]
          [Time].[1997].[Q1].[2]
          [Time].[1997].[Q1].[3]
          [Time].[1997].[Q2].[4]
          [Time].[1997].[Q2].[5]
          [Time].[1997].[Q2].[6]
          [Time].[1997].[Q3].[7]
        EXPECTED

      assert_expression_returns @olap,
        "count(generate({[Time].[1997].[Q4].[11]}," \
        " {Qtd( [Time].[Time].currentMember)}))",
        "2"

      assert_expression_returns @olap,
        "count(generate({[Time].[1997].[Q4].[11]}," \
        " {Mtd( [Time].[Time].currentMember)}))",
        "1"
    end
  end

  describe "Qtd" do
    # Java: FunctionTest#testQtd
    it "Qtd with various arguments" do
      # zero args
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member [Measures].[Foo] as ' SetToStr(Qtd()) '
        select {[Measures].[Foo]} on columns
        from [Sales]
        where [Time].[1997].[Q2].[5]
      MDX
        Axis #0:
        {[Time].[1997].[Q2].[5]}
        Axis #1:
        {[Measures].[Foo]}
        Row #0: {[Time].[1997].[Q2].[4], [Time].[1997].[Q2].[5]}
      RESULT

      # one arg, a month
      assert_axis_returns @olap,
        "Qtd([Time].[1997].[Q2].[5])",
        "[Time].[1997].[Q2].[4]\n[Time].[1997].[Q2].[5]"

      # one arg, a quarter
      assert_axis_returns @olap,
        "Qtd([Time].[1997].[Q2])",
        "[Time].[1997].[Q2]"

      # one arg, a year
      assert_axis_returns @olap,
        "Qtd([Time].[1997])",
        ""

      assert_axis_throws(
        "Qtd([Store])",
        "Argument to function 'Qtd' must belong to Time hierarchy")
    end
  end

  describe "Mtd" do
    # Java: FunctionTest#testMtd
    it "Mtd with various arguments" do
      # zero args
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member [Measures].[Foo] as ' SetToStr(Mtd()) '
        select {[Measures].[Foo]} on columns
        from [Sales]
        where [Time].[1997].[Q2].[5]
      MDX
        Axis #0:
        {[Time].[1997].[Q2].[5]}
        Axis #1:
        {[Measures].[Foo]}
        Row #0: {[Time].[1997].[Q2].[5]}
      RESULT

      # one arg, a month
      assert_axis_returns @olap,
        "Mtd([Time].[1997].[Q2].[5])",
        "[Time].[1997].[Q2].[5]"

      # one arg, a quarter
      assert_axis_returns @olap,
        "Mtd([Time].[1997].[Q2])",
        ""

      # one arg, a year
      assert_axis_returns @olap,
        "Mtd([Time].[1997])",
        ""

      assert_axis_throws(
        "Mtd([Store])",
        "Argument to function 'Mtd' must belong to Time hierarchy")
    end
  end

  describe "PeriodsToDate" do
    # Java: FunctionTest#testPeriodsToDate
    it "PeriodsToDate with various arguments" do
      # TODO: assertSetExprDependsOn not yet available

      # two args
      assert_axis_returns @olap,
        "PeriodsToDate([Time].[Quarter], [Time].[1997].[Q2].[5])",
        "[Time].[1997].[Q2].[4]\n[Time].[1997].[Q2].[5]"

      # equivalent to above
      assert_axis_returns @olap,
        "TopCount(" \
        "  Descendants(" \
        "    Ancestor(" \
        "      [Time].[1997].[Q2].[5], [Time].[Quarter])," \
        "    [Time].[1997].[Q2].[5].Level)," \
        "  1).Item(0) : [Time].[1997].[Q2].[5]",
        "[Time].[1997].[Q2].[4]\n[Time].[1997].[Q2].[5]"

      # one arg
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member [Measures].[Foo] as ' SetToStr(PeriodsToDate([Time].[Quarter])) '
        select {[Measures].[Foo]} on columns
        from [Sales]
        where [Time].[1997].[Q2].[5]
      MDX
        Axis #0:
        {[Time].[1997].[Q2].[5]}
        Axis #1:
        {[Measures].[Foo]}
        Row #0: {[Time].[1997].[Q2].[4], [Time].[1997].[Q2].[5]}
      RESULT

      # zero args
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member [Measures].[Foo] as ' SetToStr(PeriodsToDate()) '
        select {[Measures].[Foo]} on columns
        from [Sales]
        where [Time].[1997].[Q2].[5]
      MDX
        Axis #0:
        {[Time].[1997].[Q2].[5]}
        Axis #1:
        {[Measures].[Foo]}
        Row #0: {[Time].[1997].[Q2].[4], [Time].[1997].[Q2].[5]}
      RESULT

      # zero args, evaluated at a member which is at the top level.
      # The default level is the level above the current member -- so
      # choosing a member at the highest level might trip up the
      # implementation.
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member [Measures].[Foo] as ' SetToStr(PeriodsToDate()) '
        select {[Measures].[Foo]} on columns
        from [Sales]
        where [Time].[1997]
      MDX
        Axis #0:
        {[Time].[1997]}
        Axis #1:
        {[Measures].[Foo]}
        Row #0: {}
      RESULT

      # Testcase for bug 1598379, which caused NPE because the args[0].type
      # knew its dimension but not its hierarchy.
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member [Measures].[Position] as
         'Sum(PeriodsToDate([Time].[Time].Levels(0), [Time].[Time].CurrentMember), [Measures].[Store Sales])'
        select {[Time].[1997],
         [Time].[1997].[Q1],
         [Time].[1997].[Q1].[1],
         [Time].[1997].[Q1].[2],
         [Time].[1997].[Q1].[3]} ON COLUMNS,
        {[Measures].[Store Sales], [Measures].[Position] } ON ROWS
        from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Time].[1997]}
        {[Time].[1997].[Q1]}
        {[Time].[1997].[Q1].[1]}
        {[Time].[1997].[Q1].[2]}
        {[Time].[1997].[Q1].[3]}
        Axis #2:
        {[Measures].[Store Sales]}
        {[Measures].[Position]}
        Row #0: 565,238.13
        Row #0: 139,628.35
        Row #0: 45,539.69
        Row #0: 44,058.79
        Row #0: 50,029.87
        Row #1: 565,238.13
        Row #1: 139,628.35
        Row #1: 45,539.69
        Row #1: 89,598.48
        Row #1: 139,628.35
      RESULT

      assert_query_returns @olap, <<~MDX, <<~RESULT
        select
        {[Measures].[Unit Sales]} on columns,
        periodstodate(
            [Product].[Product Category],
            [Product].[Food].[Baked Goods].[Bread].[Muffins]) on rows
        from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Product].[Food].[Baked Goods].[Bread].[Bagels]}
        {[Product].[Food].[Baked Goods].[Bread].[Muffins]}
        Row #0: 815
        Row #1: 3,497
      RESULT
    end
  end
end
