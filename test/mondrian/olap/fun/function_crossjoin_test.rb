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
describe "Crossjoin" do
  before(:all) do
    create_olap_connection
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
  # contains the given pattern. Mirrors Java's assertAxisThrows/assertQueryThrows
  # which check the full exception chain.
  def assert_query_raises_with_cause(olap, mdx, pattern)
    error = assert_raises(Mondrian::OLAP::Error) { olap.execute(mdx) }
    full_message = full_error_message(error)
    assert full_message.include?(pattern),
      "Expected error containing '#{pattern}', got: #{full_message}"
  end

  # Helper: execute MDX via Mondrian's internal API and format the result.
  # Use this instead of assert_query_returns when the olap4j code path
  # cannot handle certain MDX features (e.g. DIMENSION PROPERTIES with
  # custom property names).
  def assert_internal_query_returns(olap, mdx, expected)
    connection = olap.raw_mondrian_connection
    query = connection.parseQuery(mdx)
    result = connection.execute(query)
    string_writer = Java::JavaIo::StringWriter.new
    print_writer = Java::JavaIo::PrintWriter.new(string_writer)
    result.print(print_writer)
    print_writer.flush
    actual = string_writer.toString
    # Normalize currency symbols: the internal formatter uses the JVM
    # locale's currency symbol (e.g. Euro on some systems) while
    # Java tests expect US dollar. Replace any currency symbol with $.
    actual_normalized = actual.gsub(/[€£¥]/, '$')
    assert_like expected, actual_normalized
  end

  describe "Except with crossjoin" do
    # Java: FunctionTest#testExceptEmpty
    it "Except returns empty when left is empty" do
      # If left is empty, result is empty.
      assert_axis_returns @olap,
        "Except(Filter([Gender].Members, 1=0), {[Gender].[M]})",
        ""
    end

    # Java: FunctionTest#testExceptEmpty
    it "Except returns left when right is empty" do
      # If right is empty, result is left.
      assert_axis_returns @olap,
        "Except({[Gender].[M]}, Filter([Gender].Members, 1=0))",
        "[Gender].[M]"
    end

    # Java: FunctionTest#testExceptCrossjoin
    it "Except successfully removes crossjoined tuples from axis results" do
      # Tests that Except() successfully removes crossjoined tuples
      # from the axis results. Previously, this would fail by returning
      # all tuples in the first argument to Except. bug 1439627
      assert_axis_returns @olap,
        "Except(CROSSJOIN({[Promotion Media].[All Media]},\n" \
        "                  [Product].[All Products].Children),\n" \
        "       CROSSJOIN({[Promotion Media].[All Media]},\n" \
        "                  {[Product].[All Products].[Drink]}))",
        "{[Promotion Media].[All Media], [Product].[Food]}\n" \
        "{[Promotion Media].[All Media], [Product].[Non-Consumable]}"
    end
  end

  describe "Extract" do
    # Java: FunctionTest#testExtract
    it "extracts a single hierarchy from a crossjoin" do
      assert_axis_returns @olap,
        "Extract(\n" \
        "Crossjoin({[Gender].[F], [Gender].[M]},\n" \
        "          {[Marital Status].Members}),\n" \
        "[Gender])",
        "[Gender].[F]\n" \
        "[Gender].[M]"
    end

    # Java: FunctionTest#testExtract
    it "Extract with no dimensions is not valid" do
      assert_query_raises_with_cause @olap,
        "SELECT {Extract(Crossjoin({[Gender].[F], [Gender].[M]}, {[Marital Status].Members}))} ON 0 FROM [Sales]",
        "No function matches signature 'Extract(<Set>)'"
    end

    # Java: FunctionTest#testExtract
    it "Extract applied to non-constant dimension should fail" do
      assert_query_raises_with_cause @olap,
        "SELECT {Extract(Crossjoin([Gender].Members, [Store].Children), [Store].Hierarchy.Dimension)} ON 0 FROM [Sales]",
        "not a constant hierarchy: [Store].Hierarchy.Dimension"
    end

    # Java: FunctionTest#testExtract
    it "Extract applied to non-constant hierarchy should fail" do
      assert_query_raises_with_cause @olap,
        "SELECT {Extract(Crossjoin([Gender].Members, [Store].Children), [Store].Hierarchy)} ON 0 FROM [Sales]",
        "not a constant hierarchy: [Store].Hierarchy"
    end

    # Java: FunctionTest#testExtract
    it "Extract applied to set of members removes duplicates" do
      # Extract applied to set of members is OK (if silly). Duplicates are
      # removed, as always.
      assert_axis_returns @olap,
        "Extract({[Gender].[M], [Gender].Members}, [Gender])",
        "[Gender].[M]\n" \
        "[Gender].[All Gender]\n" \
        "[Gender].[F]"
    end

    # Java: FunctionTest#testExtract
    it "Extract of hierarchy not in set fails" do
      assert_query_raises_with_cause @olap,
        "SELECT {Extract(Crossjoin([Gender].Members, [Store].Children), [Marital Status])} ON 0 FROM [Sales]",
        "hierarchy [Marital Status] is not a hierarchy of the expression Crossjoin([Gender].Members, [Store].Children)"
    end

    # Java: FunctionTest#testExtract
    it "Extract applied to empty set returns empty set" do
      assert_axis_returns @olap,
        "Extract(Crossjoin({[Gender].Parent}, [Store].Children), [Store])",
        ""
    end

    # Java: FunctionTest#testExtract
    it "Extract applied to asymmetric set extracts Gender" do
      assert_axis_returns @olap,
        "Extract(\n" \
        "{([Gender].[M], [Marital Status].[M]),\n" \
        " ([Gender].[F], [Marital Status].[M]),\n" \
        " ([Gender].[M], [Marital Status].[S])},\n" \
        "[Gender])",
        "[Gender].[M]\n" \
        "[Gender].[F]"
    end

    # Java: FunctionTest#testExtract
    it "Extract applied to asymmetric set extracts Marital Status" do
      assert_axis_returns @olap,
        "Extract(\n" \
        "{([Gender].[M], [Marital Status].[M]),\n" \
        " ([Gender].[F], [Marital Status].[M]),\n" \
        " ([Gender].[M], [Marital Status].[S])},\n" \
        "[Marital Status])",
        "[Marital Status].[M]\n" \
        "[Marital Status].[S]"
    end

    # Java: FunctionTest#testExtract
    it "Extract more than one hierarchy" do
      assert_axis_returns @olap,
        "Extract(\n" \
        "[Gender].Children * [Marital Status].Children * [Time].[1997].Children * [Store].[USA].Children,\n" \
        "[Time], [Marital Status])",
        "{[Time].[1997].[Q1], [Marital Status].[M]}\n" \
        "{[Time].[1997].[Q2], [Marital Status].[M]}\n" \
        "{[Time].[1997].[Q3], [Marital Status].[M]}\n" \
        "{[Time].[1997].[Q4], [Marital Status].[M]}\n" \
        "{[Time].[1997].[Q1], [Marital Status].[S]}\n" \
        "{[Time].[1997].[Q2], [Marital Status].[S]}\n" \
        "{[Time].[1997].[Q3], [Marital Status].[S]}\n" \
        "{[Time].[1997].[Q4], [Marital Status].[S]}"
    end

    # Java: FunctionTest#testExtract
    it "Extract duplicate hierarchies fails" do
      assert_query_raises_with_cause @olap,
        "SELECT {Extract(\n" \
        "{([Gender].[M], [Marital Status].[M]),\n" \
        " ([Gender].[F], [Marital Status].[M]),\n" \
        " ([Gender].[M], [Marital Status].[S])},\n" \
        "[Gender], [Gender])} ON 0 FROM [Sales]",
        "hierarchy [Gender] is extracted more than once"
    end
  end

  describe "TopPercent crossjoin" do
    # Java: FunctionTest#testTopPercentCrossjoin
    it "TopPercent operates on axis of crossjoined tuples" do
      # Tests that TopPercent() operates successfully on an axis of
      # crossjoined tuples. Previously, this would fail with a
      # ClassCastException in FunUtil.java. bug 1440306
      assert_axis_returns @olap,
        "{TopPercent(Crossjoin([Product].[Product Department].members,\n" \
        "[Time].[1997].children),10,[Measures].[Store Sales])}",
        "{[Product].[Food].[Produce], [Time].[1997].[Q4]}\n" \
        "{[Product].[Food].[Produce], [Time].[1997].[Q1]}\n" \
        "{[Product].[Food].[Produce], [Time].[1997].[Q3]}"
    end
  end

  describe "Crossjoin" do
    # Java: FunctionTest#testCrossjoinNested
    it "nested crossjoin produces all combinations" do
      assert_axis_returns @olap,
        "CrossJoin(\n" \
        "  CrossJoin(\n" \
        "    [Gender].members,\n" \
        "    [Marital Status].members),\n" \
        " {[Store], [Store].children})",
        "{[Gender].[All Gender], [Marital Status].[All Marital Status], [Store].[All Stores]}\n" \
        "{[Gender].[All Gender], [Marital Status].[All Marital Status], [Store].[Canada]}\n" \
        "{[Gender].[All Gender], [Marital Status].[All Marital Status], [Store].[Mexico]}\n" \
        "{[Gender].[All Gender], [Marital Status].[All Marital Status], [Store].[USA]}\n" \
        "{[Gender].[All Gender], [Marital Status].[M], [Store].[All Stores]}\n" \
        "{[Gender].[All Gender], [Marital Status].[M], [Store].[Canada]}\n" \
        "{[Gender].[All Gender], [Marital Status].[M], [Store].[Mexico]}\n" \
        "{[Gender].[All Gender], [Marital Status].[M], [Store].[USA]}\n" \
        "{[Gender].[All Gender], [Marital Status].[S], [Store].[All Stores]}\n" \
        "{[Gender].[All Gender], [Marital Status].[S], [Store].[Canada]}\n" \
        "{[Gender].[All Gender], [Marital Status].[S], [Store].[Mexico]}\n" \
        "{[Gender].[All Gender], [Marital Status].[S], [Store].[USA]}\n" \
        "{[Gender].[F], [Marital Status].[All Marital Status], [Store].[All Stores]}\n" \
        "{[Gender].[F], [Marital Status].[All Marital Status], [Store].[Canada]}\n" \
        "{[Gender].[F], [Marital Status].[All Marital Status], [Store].[Mexico]}\n" \
        "{[Gender].[F], [Marital Status].[All Marital Status], [Store].[USA]}\n" \
        "{[Gender].[F], [Marital Status].[M], [Store].[All Stores]}\n" \
        "{[Gender].[F], [Marital Status].[M], [Store].[Canada]}\n" \
        "{[Gender].[F], [Marital Status].[M], [Store].[Mexico]}\n" \
        "{[Gender].[F], [Marital Status].[M], [Store].[USA]}\n" \
        "{[Gender].[F], [Marital Status].[S], [Store].[All Stores]}\n" \
        "{[Gender].[F], [Marital Status].[S], [Store].[Canada]}\n" \
        "{[Gender].[F], [Marital Status].[S], [Store].[Mexico]}\n" \
        "{[Gender].[F], [Marital Status].[S], [Store].[USA]}\n" \
        "{[Gender].[M], [Marital Status].[All Marital Status], [Store].[All Stores]}\n" \
        "{[Gender].[M], [Marital Status].[All Marital Status], [Store].[Canada]}\n" \
        "{[Gender].[M], [Marital Status].[All Marital Status], [Store].[Mexico]}\n" \
        "{[Gender].[M], [Marital Status].[All Marital Status], [Store].[USA]}\n" \
        "{[Gender].[M], [Marital Status].[M], [Store].[All Stores]}\n" \
        "{[Gender].[M], [Marital Status].[M], [Store].[Canada]}\n" \
        "{[Gender].[M], [Marital Status].[M], [Store].[Mexico]}\n" \
        "{[Gender].[M], [Marital Status].[M], [Store].[USA]}\n" \
        "{[Gender].[M], [Marital Status].[S], [Store].[All Stores]}\n" \
        "{[Gender].[M], [Marital Status].[S], [Store].[Canada]}\n" \
        "{[Gender].[M], [Marital Status].[S], [Store].[Mexico]}\n" \
        "{[Gender].[M], [Marital Status].[S], [Store].[USA]}"
    end

    # Java: FunctionTest#testCrossjoinSingletonTuples
    it "crossjoin of singleton tuples" do
      assert_axis_returns @olap,
        "CrossJoin({([Gender].[M])}, {([Marital Status].[S])})",
        "{[Gender].[M], [Marital Status].[S]}"
    end

    # Java: FunctionTest#testCrossjoinSingletonTuplesNested
    it "crossjoin of singleton tuples nested" do
      assert_axis_returns @olap,
        "CrossJoin({([Gender].[M])}, CrossJoin({([Marital Status].[S])}, [Store].children))",
        "{[Gender].[M], [Marital Status].[S], [Store].[Canada]}\n" \
        "{[Gender].[M], [Marital Status].[S], [Store].[Mexico]}\n" \
        "{[Gender].[M], [Marital Status].[S], [Store].[USA]}"
    end

    # Java: FunctionTest#testCrossjoinAsterisk
    it "crossjoin using asterisk operator" do
      assert_axis_returns @olap,
        "{[Gender].[M]} * {[Marital Status].[S]}",
        "{[Gender].[M], [Marital Status].[S]}"
    end

    # Java: FunctionTest#testCrossjoinAsteriskTuple
    it "crossjoin using asterisk with tuple" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        select {[Measures].[Unit Sales]} ON COLUMNS, NON EMPTY [Store].[All Stores] * ([Product].[All Products], [Gender]) * [Customers].[All Customers] ON ROWS from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Store].[All Stores], [Product].[All Products], [Gender].[All Gender], [Customers].[All Customers]}
        Row #0: 266,773
      RESULT
    end

    # Java: FunctionTest#testCrossjoinAsteriskAssoc
    it "crossjoin asterisk is associative and orderable" do
      assert_axis_returns @olap,
        "Order({[Gender].Children} * {[Marital Status].Children} * {[Time].[1997].[Q2].Children}," \
        "[Measures].[Unit Sales])",
        "{[Gender].[F], [Marital Status].[M], [Time].[1997].[Q2].[4]}\n" \
        "{[Gender].[F], [Marital Status].[M], [Time].[1997].[Q2].[6]}\n" \
        "{[Gender].[F], [Marital Status].[M], [Time].[1997].[Q2].[5]}\n" \
        "{[Gender].[F], [Marital Status].[S], [Time].[1997].[Q2].[4]}\n" \
        "{[Gender].[F], [Marital Status].[S], [Time].[1997].[Q2].[5]}\n" \
        "{[Gender].[F], [Marital Status].[S], [Time].[1997].[Q2].[6]}\n" \
        "{[Gender].[M], [Marital Status].[M], [Time].[1997].[Q2].[4]}\n" \
        "{[Gender].[M], [Marital Status].[M], [Time].[1997].[Q2].[5]}\n" \
        "{[Gender].[M], [Marital Status].[M], [Time].[1997].[Q2].[6]}\n" \
        "{[Gender].[M], [Marital Status].[S], [Time].[1997].[Q2].[6]}\n" \
        "{[Gender].[M], [Marital Status].[S], [Time].[1997].[Q2].[4]}\n" \
        "{[Gender].[M], [Marital Status].[S], [Time].[1997].[Q2].[5]}"
    end

    # Java: FunctionTest#testCrossjoinAsteriskInsideBraces
    it "crossjoin asterisk inside braces" do
      assert_axis_returns @olap,
        "{[Gender].[M] * [Marital Status].[S] * [Time].[1997].[Q2].Children}",
        "{[Gender].[M], [Marital Status].[S], [Time].[1997].[Q2].[4]}\n" \
        "{[Gender].[M], [Marital Status].[S], [Time].[1997].[Q2].[5]}\n" \
        "{[Gender].[M], [Marital Status].[S], [Time].[1997].[Q2].[6]}"
    end

    # Java: FunctionTest#testCrossJoinAsteriskQuery
    it "crossjoin asterisk in full query with HR cube" do
      # Uses the internal Mondrian API because the olap4j code path
      # cannot resolve DIMENSION PROPERTIES with custom property names.
      assert_internal_query_returns @olap, <<~MDX, <<~RESULT
        SELECT {[Measures].members * [1997].children} ON COLUMNS,
         {[Store].[USA].children * [Position].[All Position].children} DIMENSION PROPERTIES [Store].[Store SQFT] ON ROWS
        FROM [HR]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Org Salary], [Time].[1997].[Q1]}
        {[Measures].[Org Salary], [Time].[1997].[Q2]}
        {[Measures].[Org Salary], [Time].[1997].[Q3]}
        {[Measures].[Org Salary], [Time].[1997].[Q4]}
        {[Measures].[Count], [Time].[1997].[Q1]}
        {[Measures].[Count], [Time].[1997].[Q2]}
        {[Measures].[Count], [Time].[1997].[Q3]}
        {[Measures].[Count], [Time].[1997].[Q4]}
        {[Measures].[Number of Employees], [Time].[1997].[Q1]}
        {[Measures].[Number of Employees], [Time].[1997].[Q2]}
        {[Measures].[Number of Employees], [Time].[1997].[Q3]}
        {[Measures].[Number of Employees], [Time].[1997].[Q4]}
        Axis #2:
        {[Store].[USA].[CA], [Position].[Middle Management]}
        {[Store].[USA].[CA], [Position].[Senior Management]}
        {[Store].[USA].[CA], [Position].[Store Full Time Staf]}
        {[Store].[USA].[CA], [Position].[Store Management]}
        {[Store].[USA].[CA], [Position].[Store Temp Staff]}
        {[Store].[USA].[OR], [Position].[Middle Management]}
        {[Store].[USA].[OR], [Position].[Senior Management]}
        {[Store].[USA].[OR], [Position].[Store Full Time Staf]}
        {[Store].[USA].[OR], [Position].[Store Management]}
        {[Store].[USA].[OR], [Position].[Store Temp Staff]}
        {[Store].[USA].[WA], [Position].[Middle Management]}
        {[Store].[USA].[WA], [Position].[Senior Management]}
        {[Store].[USA].[WA], [Position].[Store Full Time Staf]}
        {[Store].[USA].[WA], [Position].[Store Management]}
        {[Store].[USA].[WA], [Position].[Store Temp Staff]}
        Row #0: $275.40
        Row #0: $275.40
        Row #0: $275.40
        Row #0: $275.40
        Row #0: 27
        Row #0: 27
        Row #0: 27
        Row #0: 27
        Row #0: 9
        Row #0: 9
        Row #0: 9
        Row #0: 9
        Row #1: $837.00
        Row #1: $837.00
        Row #1: $837.00
        Row #1: $837.00
        Row #1: 24
        Row #1: 24
        Row #1: 24
        Row #1: 24
        Row #1: 8
        Row #1: 8
        Row #1: 8
        Row #1: 8
        Row #2: $1,728.45
        Row #2: $1,727.02
        Row #2: $1,727.72
        Row #2: $1,726.55
        Row #2: 357
        Row #2: 357
        Row #2: 357
        Row #2: 357
        Row #2: 119
        Row #2: 119
        Row #2: 119
        Row #2: 119
        Row #3: $473.04
        Row #3: $473.04
        Row #3: $473.04
        Row #3: $473.04
        Row #3: 51
        Row #3: 51
        Row #3: 51
        Row #3: 51
        Row #3: 17
        Row #3: 17
        Row #3: 17
        Row #3: 17
        Row #4: $401.35
        Row #4: $405.73
        Row #4: $400.61
        Row #4: $402.31
        Row #4: 120
        Row #4: 120
        Row #4: 120
        Row #4: 120
        Row #4: 40
        Row #4: 40
        Row #4: 40
        Row #4: 40
        Row #5:
        Row #5:
        Row #5:
        Row #5:
        Row #5:
        Row #5:
        Row #5:
        Row #5:
        Row #5:
        Row #5:
        Row #5:
        Row #5:
        Row #6:
        Row #6:
        Row #6:
        Row #6:
        Row #6:
        Row #6:
        Row #6:
        Row #6:
        Row #6:
        Row #6:
        Row #6:
        Row #6:
        Row #7: $1,343.62
        Row #7: $1,342.61
        Row #7: $1,342.57
        Row #7: $1,343.65
        Row #7: 279
        Row #7: 279
        Row #7: 279
        Row #7: 279
        Row #7: 93
        Row #7: 93
        Row #7: 93
        Row #7: 93
        Row #8: $286.74
        Row #8: $286.74
        Row #8: $286.74
        Row #8: $286.74
        Row #8: 30
        Row #8: 30
        Row #8: 30
        Row #8: 30
        Row #8: 10
        Row #8: 10
        Row #8: 10
        Row #8: 10
        Row #9: $333.20
        Row #9: $332.65
        Row #9: $331.28
        Row #9: $332.43
        Row #9: 99
        Row #9: 99
        Row #9: 99
        Row #9: 99
        Row #9: 33
        Row #9: 33
        Row #9: 33
        Row #9: 33
        Row #10:
        Row #10:
        Row #10:
        Row #10:
        Row #10:
        Row #10:
        Row #10:
        Row #10:
        Row #10:
        Row #10:
        Row #10:
        Row #10:
        Row #11:
        Row #11:
        Row #11:
        Row #11:
        Row #11:
        Row #11:
        Row #11:
        Row #11:
        Row #11:
        Row #11:
        Row #11:
        Row #11:
        Row #12: $2,768.60
        Row #12: $2,769.18
        Row #12: $2,766.78
        Row #12: $2,769.50
        Row #12: 579
        Row #12: 579
        Row #12: 579
        Row #12: 579
        Row #12: 193
        Row #12: 193
        Row #12: 193
        Row #12: 193
        Row #13: $736.29
        Row #13: $736.29
        Row #13: $736.29
        Row #13: $736.29
        Row #13: 81
        Row #13: 81
        Row #13: 81
        Row #13: 81
        Row #13: 27
        Row #13: 27
        Row #13: 27
        Row #13: 27
        Row #14: $674.70
        Row #14: $674.54
        Row #14: $676.26
        Row #14: $676.48
        Row #14: 201
        Row #14: 201
        Row #14: 201
        Row #14: 201
        Row #14: 67
        Row #14: 67
        Row #14: 67
        Row #14: 67
      RESULT
    end

    # Java: FunctionTest#testCrossjoinResolve
    it "crossjoin with self-referencing calculated member resolves without StackOverflow" do
      # Testcase for bug 1889745, "StackOverflowError while resolving
      # crossjoin". The problem occurs when a calculated member that
      # references itself is referenced in a crossjoin.
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
        member [Measures].[Filtered Unit Sales] as
         'IIf((([Measures].[Unit Sales] > 50000.0)
              OR ([Product].CurrentMember.Level.UniqueName <>
                  "[Product].[Product Family]")),
              IIf(((Count([Product].CurrentMember.Children) = 0.0)),
                  [Measures].[Unit Sales],
                  Sum([Product].CurrentMember.Children,
                      [Measures].[Filtered Unit Sales])),
              NULL)'
        select NON EMPTY {crossjoin({[Measures].[Filtered Unit Sales]},
        {[Gender].[M], [Gender].[F]})} ON COLUMNS,
        NON EMPTY {[Product].[All Products]} ON ROWS
        from [Sales]
        where [Time].[1997]
      MDX
        Axis #0:
        {[Time].[1997]}
        Axis #1:
        {[Measures].[Filtered Unit Sales], [Gender].[M]}
        {[Measures].[Filtered Unit Sales], [Gender].[F]}
        Axis #2:
        {[Product].[All Products]}
        Row #0: 97,126
        Row #0: 94,814
      RESULT
    end

    # Java: FunctionTest#testCrossjoinOrder
    it "crossjoin with ORDER does not throw immutable list exception" do
      # Test case for bug 1911832, "Exception converting immutable list
      # to array in JDK 1.5".
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH
        SET [S1] AS 'CROSSJOIN({[Time].[1997]}, {[Gender].[Gender].MEMBERS})'
        SELECT CROSSJOIN(ORDER([S1], [Measures].[Unit Sales], BDESC),
        {[Measures].[Unit Sales]}) ON AXIS(0)
        FROM [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Time].[1997], [Gender].[M], [Measures].[Unit Sales]}
        {[Time].[1997], [Gender].[F], [Measures].[Unit Sales]}
        Row #0: 135,215
        Row #0: 131,558
      RESULT
    end

    # Java: FunctionTest#testCrossjoinDupHierarchyFails
    it "crossjoin with duplicate hierarchy fails" do
      assert_query_raises_with_cause @olap,
        "select [Measures].[Unit Sales] ON COLUMNS,\n" \
        " CrossJoin({[Time].[Quarter].[Q1]}, {[Time].[Month].[5]}) ON ROWS\n" \
        "from [Sales]",
        "Tuple contains more than one member of hierarchy '[Time]'."
    end

    # Java: FunctionTest#testCrossjoinDupHierarchyFails
    it "crossjoin with duplicate hierarchy fails with Item" do
      # now with Item, for kicks
      assert_query_raises_with_cause @olap,
        "select [Measures].[Unit Sales] ON COLUMNS,\n" \
        " CrossJoin({[Time].[Quarter].[Q1]}, {[Time].[Month].[5]}).Item(0) ON ROWS\n" \
        "from [Sales]",
        "Tuple contains more than one member of hierarchy '[Time]'."
    end

    # Java: FunctionTest#testCrossjoinDupHierarchyFails
    it "explicit tuple with duplicate hierarchy fails" do
      # same query using explicit tuple
      assert_query_raises_with_cause @olap,
        "select [Measures].[Unit Sales] ON COLUMNS,\n" \
        " ([Time].[Quarter].[Q1], [Time].[Month].[5]) ON ROWS\n" \
        "from [Sales]",
        "Tuple contains more than one member of hierarchy '[Time]'."
    end

    # Java: FunctionTest#testCrossjoinDupDimensionOk
    it "crossjoin with different hierarchies in same dimension is OK" do
      # Tests cases of different hierarchies in the same dimension.
      # (Compare to testCrossjoinDupHierarchyFails). Not an error.
      # Note: SsasCompatibleNaming defaults to false, so [Time.Weekly] format
      # is used instead of SSAS-style [Time].[Weekly].
      expected = <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Time].[1997].[Q1], [Time.Weekly].[1997].[10]}
        Row #0: 4,395
      RESULT

      assert_query_returns @olap,
        "select [Measures].[Unit Sales] ON COLUMNS,\n" \
        " CrossJoin({[Time].[Quarter].[Q1]}, {[Time.Weekly].[1997].[10]}) ON ROWS\n" \
        "from [Sales]",
        expected

      # now with Item, for kicks
      assert_query_returns @olap,
        "select [Measures].[Unit Sales] ON COLUMNS,\n" \
        " CrossJoin({[Time].[Quarter].[Q1]}, {[Time.Weekly].[1997].[10]}).Item(0) ON ROWS\n" \
        "from [Sales]",
        expected

      # same query using explicit tuple
      assert_query_returns @olap,
        "select [Measures].[Unit Sales] ON COLUMNS,\n" \
        " ([Time].[Quarter].[Q1], [Time.Weekly].[1997].[10]) ON ROWS\n" \
        "from [Sales]",
        expected
    end
  end
end
