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
describe "IIf, Case, CoalesceEmpty, and IsEmpty functions" do
  before(:all) do
    create_olap_connection
  end

  # Helper: assert a boolean MDX expression returns the expected boolean.
  # Mirrors Java's assertBooleanExprReturns which wraps with Iif.
  def assert_boolean_expression_returns(olap, expression, expected)
    iif_expression = "Iif (#{expression},\"true\",\"false\")"
    assert_expression_returns olap, iif_expression, expected ? "true" : "false"
  end

  # Helper: walk the Java exception cause chain and collect all messages.
  # Useful for checking deeply nested error messages from Mondrian.
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

  # Helper: assert that executing MDX raises an error whose cause chain
  # contains the given pattern. Mirrors Java's assertAxisThrows which
  # checks the full exception chain.
  def assert_query_raises_with_cause(olap, mdx, pattern)
    error = assert_raises(Mondrian::OLAP::Error) { olap.execute(mdx) }
    full_message = full_error_message(error)
    assert full_message.include?(pattern),
      "Expected error containing '#{pattern}', got: #{full_message}"
  end

  # Helper: execute MDX using the internal Mondrian API and return mondrian.olap.Result.
  # Needed for checkDataResults-style assertions that inspect cell values numerically.
  def execute_internal_query(olap, mdx)
    connection = olap.raw_mondrian_connection
    query = connection.parseQuery(mdx)
    connection.execute(query)
  end

  # Helper: check cell data from a mondrian.olap.Result against expected Double values.
  # Mirrors Java's checkDataResults.
  def check_data_results(expected, result, tolerance)
    expected.each_with_index do |row_values, row|
      row_values.each_with_index do |expected_value, col|
        cell = result.getCell([col, row].to_java(:int))
        if expected_value.nil?
          assert cell.isNull, "Expected null value at (#{row}, #{col})"
        else
          refute cell.isNull, "Cell at (#{row}, #{col}) was null, but was expecting #{expected_value}"
          value = cell.getValue
          actual_value = value.respond_to?(:doubleValue) ? value.doubleValue : value.to_f
          assert_in_delta expected_value, actual_value, tolerance,
            "Incorrect value returned at (#{row}, #{col})"
        end
      end
    end
  end

  describe "IsEmpty" do
    # Java: FunctionTest#testIsEmptyQuery
    it "returns replacement value when cell is empty using IsEmpty function" do
      expected_result = <<~RESULT
        Axis #0:
        {[Time].[1997].[Q4].[12], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Portsmouth].[Portsmouth Imported Beer], [Measures].[Foo]}
        Axis #1:
        {[Store].[USA].[WA].[Bellingham]}
        {[Store].[USA].[WA].[Bremerton]}
        {[Store].[USA].[WA].[Seattle]}
        {[Store].[USA].[WA].[Spokane]}
        {[Store].[USA].[WA].[Tacoma]}
        {[Store].[USA].[WA].[Walla Walla]}
        {[Store].[USA].[WA].[Yakima]}
        Row #0: 5
        Row #0: 5
        Row #0: 2
        Row #0: 5
        Row #0: 11
        Row #0: 5
        Row #0: 4
      RESULT

      # Using IsEmpty() function
      assert_query_returns @olap, <<~MDX, expected_result
        WITH MEMBER [Measures].[Foo] AS 'Iif(IsEmpty([Measures].[Unit Sales]), 5, [Measures].[Unit Sales])'
        SELECT {[Store].[USA].[WA].children} on columns
        FROM Sales
        WHERE ([Time].[1997].[Q4].[12],
         [Product].[All Products].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Portsmouth].[Portsmouth Imported Beer],
         [Measures].[Foo])
      MDX

      # Using IS EMPTY syntax
      assert_query_returns @olap, <<~MDX, expected_result
        WITH MEMBER [Measures].[Foo] AS 'Iif([Measures].[Unit Sales] IS EMPTY, 5, [Measures].[Unit Sales])'
        SELECT {[Store].[USA].[WA].children} on columns
        FROM Sales
        WHERE ([Time].[1997].[Q4].[12],
         [Product].[All Products].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Portsmouth].[Portsmouth Imported Beer],
         [Measures].[Foo])
      MDX

      # IS EMPTY with CAST expression — 1998 has no data so Unit Sales is empty, Bar is non-empty
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH MEMBER [Measures].[Foo] AS 'Iif([Measures].[Bar] IS EMPTY, 1, [Measures].[Bar])'
        MEMBER [Measures].[Bar] AS 'CAST("42" AS INTEGER)'
        SELECT {[Measures].[Unit Sales], [Measures].[Foo]} on columns
        FROM Sales
        WHERE ([Time].[1998].[Q4].[12])
      MDX
        Axis #0:
        {[Time].[1998].[Q4].[12]}
        Axis #1:
        {[Measures].[Unit Sales]}
        {[Measures].[Foo]}
        Row #0:
        Row #0: 42
      RESULT
    end

    # Java: FunctionTest#testIsEmptyWithAggregate
    it "isEmpty with Aggregate returns false for non-empty aggregate" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH MEMBER [gender].[foo] AS 'isEmpty(Aggregate({[Gender].m}))'
        SELECT {Gender.foo} on 0 from sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Gender].[foo]}
        Row #0: false
      RESULT
    end

    # Java: FunctionTest#testIsEmpty
    it "IS NULL checks for null member references" do
      assert_boolean_expression_returns @olap, "[Gender].[All Gender].Parent IS NULL", true

      # Any functions that return a member from parameters that
      # include a member and that member is NULL also give a NULL.
      # Not a runtime exception.
      assert_boolean_expression_returns @olap,
        "[Gender].CurrentMember.Parent.NextMember IS NULL", true

      # Bug.BugMondrian207Fixed is false — the rest of the Java test is
      # unreachable (guarded by `if (!Bug.BugMondrian207Fixed) return`).
    end

    # Java: FunctionTest#testIsEmptyWithNull
    it "isEmpty with null returns true" do
      assert_expression_returns @olap,
        'iif (isempty(null), "is empty", "not is empty")',
        "is empty"
      assert_expression_returns @olap,
        "iif (isempty(null), 1, 2)",
        "1"
    end
  end

  describe "IIf" do
    # Java: FunctionTest#testIIf
    it "returns string based on numeric comparison" do
      assert_expression_returns @olap,
        'IIf(([Measures].[Unit Sales],[Product].[Drink].[Alcoholic Beverages].[Beer and Wine]) > 100, "Yes","No")',
        "Yes"
    end

    # Java: FunctionTest#testIIfWithNullAndNumber
    it "returns empty string for null and number for non-null branch" do
      assert_expression_returns @olap,
        "IIf(([Measures].[Unit Sales],[Product].[Drink].[Alcoholic Beverages].[Beer and Wine]) > 100, null,20)",
        ""
      assert_expression_returns @olap,
        "IIf(([Measures].[Unit Sales],[Product].[Drink].[Alcoholic Beverages].[Beer and Wine]) > 100, 20,null)",
        "20"
    end

    # Java: FunctionTest#testIIfWithStringAndNull
    it "returns empty string for null and string for non-null branch" do
      assert_expression_returns @olap,
        'IIf(([Measures].[Unit Sales],[Product].[Drink].[Alcoholic Beverages].[Beer and Wine]) > 100, null,"foo")',
        ""
      assert_expression_returns @olap,
        'IIf(([Measures].[Unit Sales],[Product].[Drink].[Alcoholic Beverages].[Beer and Wine]) > 100, "foo",null)',
        "foo"
    end

    # Java: FunctionTest#testIIfMember
    it "returns member based on condition" do
      assert_axis_returns @olap,
        "IIf(1 > 2,[Store].[USA],[Store].[Canada].[BC])",
        "[Store].[Canada].[BC]"
    end

    # Java: FunctionTest#testIIfLevel
    it "returns level name based on condition" do
      assert_expression_returns @olap,
        "IIf(1 > 2, [Store].[Store Country],[Store].[Store City]).Name",
        "Store City"
    end

    # Java: FunctionTest#testIIfHierarchy
    it "returns hierarchy name based on condition" do
      assert_expression_returns @olap,
        "IIf(1 > 2, [Time], [Store]).Name",
        "Store"

      # Call Iif(<Logical>, <Dimension>, <Hierarchy>). Argument #3, the
      # hierarchy [Time.Weekly] is implicitly converted to
      # the dimension [Time] to match argument #2 which is a dimension.
      assert_expression_returns @olap,
        "IIf(1 > 2, [Time], [Time.Weekly]).Name",
        "Time"
    end

    # Java: FunctionTest#testIIfDimension
    it "returns dimension name based on condition" do
      assert_expression_returns @olap,
        "IIf(1 > 2, [Store], [Time]).Name",
        "Time"
    end

    # Java: FunctionTest#testIIfSet
    it "returns set based on condition" do
      assert_axis_returns @olap,
        "IIf(1 > 2, {[Store].[USA], [Store].[USA].[CA]}, {[Store].[Mexico], [Store].[USA].[OR]})",
        "[Store].[Mexico]\n[Store].[USA].[OR]"
    end

    # MONDRIAN-2408 - Consumer wants ITERABLE or ANY in CrossJoinFunDef.compileCall(ResolvedFunCall, ExpCompiler)
    # Java: FunctionTest#testIIfSetType_InCrossJoin
    it "IIf returning set works inside CROSSJOIN" do
      assert_axis_returns @olap,
        "CROSSJOIN([Store Type].[Deluxe Supermarket],IIf(1 = 1, {[Store].[USA], [Store].[USA].[CA]}, {[Store].[Mexico], [Store].[USA].[OR]}))",
        "{[Store Type].[Deluxe Supermarket], [Store].[USA]}\n{[Store Type].[Deluxe Supermarket], [Store].[USA].[CA]}"
    end

    # MONDRIAN-2408 - Consumer wants (immutable) LIST in CrossJoinFunDef.compileCall(ResolvedFunCall, ExpCompiler)
    # Java: FunctionTest#testIIfSetType_InCrossJoinAndAvg
    it "IIf returning set works inside CROSSJOIN with Avg" do
      assert_expression_returns @olap,
        "Avg(CROSSJOIN([Store Type].[Deluxe Supermarket],IIf(1 = 1, {[Store].[USA].[OR], [Store].[USA].[WA]}, {[Store].[Mexico], [Store].[USA].[CA]})), [Measures].[Store Sales])",
        "81,031.12"
    end
  end

  describe "IIf with boolean and numeric parameters" do
    # Java: FunctionTest#testIifFWithBooleanBooleanAndNumericParameterForReturningTruePart
    it "returns true part when condition is true and false part is numeric" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        SELECT Filter(Store.allmembers, iif(measures.profit < 400000,[store].currentMember.NAME = "USA", 0)) on 0 FROM SALES
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Store].[USA]}
        Row #0: 266,773
      RESULT
    end

    # Java: FunctionTest#testIifWithBooleanBooleanAndNumericParameterForReturningFalsePart
    it "returns false part (numeric 1) when condition is false" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        SELECT Filter([Store].[USA].[CA].[Beverly Hills].children, iif(measures.profit > 400000,[store].currentMember.NAME = "USA", 1)) on 0 FROM SALES
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Store].[USA].[CA].[Beverly Hills].[Store 6]}
        Row #0: 21,333
      RESULT
    end

    # Java: FunctionTest#testIIFWithBooleanBooleanAndNumericParameterForReturningZero
    it "returns empty axis when false part is 0 and no members match" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        SELECT Filter(Store.allmembers, iif(measures.profit > 400000,[store].currentMember.NAME = "USA", 0)) on 0 FROM SALES
      MDX
        Axis #0:
        {}
        Axis #1:
      RESULT
    end
  end

  describe "CoalesceEmpty" do
    # Java: FunctionTest#testCoalesceEmptyDepends
    it "depends on expected hierarchies" do
      # TODO: assertExprDependsOn not yet available
      skip "assertExprDependsOn not yet available"
    end

    # Java: FunctionTest#testCoalesceEmpty
    it "returns first non-empty value from multiple expressions" do
      # [DF] is all null and [WA] has numbers for 1997 but not for 1998.
      result = execute_internal_query @olap, <<~MDX
        with
            member Measures.[Coal1] as 'coalesceempty(([Time].[1997], Measures.[Store Sales]), ([Time].[1998], Measures.[Store Sales]))'
            member Measures.[Coal2] as 'coalesceempty(([Time].[1997], Measures.[Unit Sales]), ([Time].[1998], Measures.[Unit Sales]))'
        select
            {Measures.[Coal1], Measures.[Coal2]} on columns,
            {[Store].[All Stores].[Mexico].[DF], [Store].[All Stores].[USA].[WA]} on rows
        from
            [Sales]
      MDX

      check_data_results(
        [
          [nil, nil],
          [263_793.22, 124_366.0]
        ],
        result, 0.001
      )

      result = execute_internal_query @olap, <<~MDX
        with
            member Measures.[Sales Per Customer] as 'Measures.[Sales Count] / Measures.[Customer Count]'
            member Measures.[Coal] as 'coalesceempty(([Measures].[Sales Per Customer], [Store].[All Stores].[Mexico].[DF]),
                Measures.[Sales Per Customer])'
        select
            {Measures.[Sales Per Customer], Measures.[Coal]} on columns,
            {[Store].[All Stores].[Mexico].[DF], [Store].[All Stores].[USA].[WA]} on rows
        from
            [Sales]
        where
            ([Time].[1997].[Q2])
      MDX

      check_data_results(
        [
          [nil, nil],
          [8.963, 8.963]
        ],
        result, 0.001
      )

      result = execute_internal_query @olap, <<~MDX
        with
            member Measures.[Sales Per Customer] as 'Measures.[Sales Count] / Measures.[Customer Count]'
            member Measures.[Coal] as 'coalesceempty(([Measures].[Sales Per Customer], [Store].[All Stores].[Mexico].[DF]),
                ([Measures].[Sales Per Customer], [Store].[All Stores].[Mexico].[DF]),
                ([Measures].[Sales Per Customer], [Store].[All Stores].[Mexico].[DF]),
                ([Measures].[Sales Per Customer], [Store].[All Stores].[Mexico].[DF]),
                ([Measures].[Sales Per Customer], [Store].[All Stores].[Mexico].[DF]),
                ([Measures].[Sales Per Customer], [Store].[All Stores].[Mexico].[DF]),
                ([Measures].[Sales Per Customer], [Store].[All Stores].[Mexico].[DF]),
                ([Measures].[Sales Per Customer], [Store].[All Stores].[Mexico].[DF]),
                Measures.[Sales Per Customer])'
        select
            {Measures.[Sales Per Customer], Measures.[Coal]} on columns,
            {[Store].[All Stores].[Mexico].[DF], [Store].[All Stores].[USA].[WA]} on rows
        from
            [Sales]
        where
            ([Time].[1997].[Q2])
      MDX

      check_data_results(
        [
          [nil, nil],
          [8.963, 8.963]
        ],
        result, 0.001
      )
    end

    # Java: FunctionTest#testBrokenContextBug
    it "coalesceempty does not break evaluation context" do
      result = execute_internal_query @olap, <<~MDX
        with
            member Measures.[Sales Per Customer] as 'Measures.[Sales Count] / Measures.[Customer Count]'
            member Measures.[Coal] as 'coalesceempty(([Measures].[Sales Per Customer], [Store].[All Stores].[Mexico].[DF]),
                Measures.[Sales Per Customer])'
        select
            {Measures.[Coal]} on columns,
            {[Store].[All Stores].[USA].[WA]} on rows
        from
            [Sales]
        where
            ([Time].[1997].[Q2])
      MDX

      check_data_results([[8.963]], result, 0.001)
    end
  end

  describe "Case" do
    # Java: FunctionTest#testCaseTestMatch
    it "CASE WHEN matches second condition" do
      assert_expression_returns @olap,
        'CASE WHEN 1=0 THEN "first" WHEN 1=1 THEN "second" WHEN 1=2 THEN "third" ELSE "fourth" END',
        "second"
    end

    # Java: FunctionTest#testCaseTestMatchElse
    it "CASE WHEN falls through to ELSE" do
      assert_expression_returns @olap,
        'CASE WHEN 1=0 THEN "first" ELSE "fourth" END',
        "fourth"
    end

    # Java: FunctionTest#testCaseTestMatchNoElse
    it "CASE WHEN with no ELSE returns empty" do
      assert_expression_returns @olap,
        'CASE WHEN 1=0 THEN "first" END',
        ""
    end

    # Testcase for bug 1799391, "Case Test function throws class cast exception"
    # Java: FunctionTest#testCaseTestReturnsMemberBug1799391
    it "CASE WHEN returning a member does not throw class cast exception" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH
         MEMBER [Product].[CaseTest] AS
         'CASE
         WHEN [Gender].CurrentMember IS [Gender].[M] THEN [Gender].[F]
         ELSE [Gender].[F]
         END'

        SELECT {[Product].[CaseTest]} ON 0, {[Gender].[M]} ON 1 FROM Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Product].[CaseTest]}
        Axis #2:
        {[Gender].[M]}
        Row #0: 131,558
      RESULT

      assert_axis_returns @olap,
        "CASE WHEN 1+1 = 2 THEN [Gender].[F] ELSE [Gender].[F].Parent END",
        "[Gender].[F]"

      # try case match for good measure
      assert_axis_returns @olap,
        "CASE 1 WHEN 2 THEN [Gender].[F] ELSE [Gender].[F].Parent END",
        "[Gender].[All Gender]"
    end

    # Java: FunctionTest#testCaseMatch
    it "CASE value match returns second branch" do
      assert_expression_returns @olap,
        'CASE 2 WHEN 1 THEN "first" WHEN 2 THEN "second" WHEN 3 THEN "third" ELSE "fourth" END',
        "second"
    end

    # Java: FunctionTest#testCaseMatchElse
    it "CASE value match falls through to ELSE" do
      assert_expression_returns @olap,
        'CASE 7 WHEN 1 THEN "first" ELSE "fourth" END',
        "fourth"
    end

    # Java: FunctionTest#testCaseMatchNoElse
    it "CASE value match with no ELSE returns empty" do
      assert_expression_returns @olap,
        'CASE 8 WHEN 0 THEN "first" END',
        ""
    end

    # Java: FunctionTest#testCaseTypeMismatch
    it "CASE with type mismatches raises error" do
      # type mismatch between case and else
      assert_query_raises_with_cause @olap,
        "SELECT {CASE 1 WHEN 1 THEN 2 ELSE \"foo\" END} on columns from Sales",
        "No function matches signature"

      # type mismatch between case and case
      assert_query_raises_with_cause @olap,
        "SELECT {CASE 1 WHEN 1 THEN 2 WHEN 2 THEN \"foo\" ELSE 3 END} on columns from Sales",
        "No function matches signature"

      # type mismatch between value and case
      assert_query_raises_with_cause @olap,
        "SELECT {CASE 1 WHEN \"foo\" THEN 2 ELSE 3 END} on columns from Sales",
        "No function matches signature"

      # non-boolean condition
      assert_query_raises_with_cause @olap,
        "SELECT {CASE WHEN 1 = 2 THEN 3 WHEN 4 THEN 5 ELSE 6 END} on columns from Sales",
        "No function matches signature"
    end

    # Testcase for bug MONDRIAN-853, "When using CASE WHEN in a CalculatedMember
    # values are not returned the way expected".
    # Java: FunctionTest#testCaseTuple
    it "CASE WHEN with tuple expression evaluates to scalar" do
      # The case in the bug, simplified. With the bug, returns a member array.
      # Type deduction should realize that the result is a scalar, therefore a
      # tuple (represented by a member array) needs to be evaluated to a scalar.

      # The `case value when` variant is guarded by `if (false)` in the Java test,
      # meaning it is a known broken case. Only the "case when" variant works.

      # "case when" variant always worked
      assert_expression_returns @olap,
        "case when 1=0 then 1.5 else ([Gender].[M], [Measures].[Unit Sales]) end",
        "135,215"
    end
  end
end
