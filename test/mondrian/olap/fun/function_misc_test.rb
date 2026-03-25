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
describe "FunctionMisc" do
  before(:all) do
    create_olap_connection
  end

  # Assert that executing MDX raises an error whose root cause message
  # contains the expected pattern. Java's assertQueryThrows / assertAxisThrows /
  # assertExprThrows all check the root cause, not the top-level wrapper.
  def assert_error_contains(olap, mdx, pattern)
    error = assert_raises(Mondrian::OLAP::Error) { olap.execute(mdx) }
    full_message = "#{error.message}\n#{error.root_cause_message}"
    assert full_message.include?(pattern),
      "Expected error containing '#{pattern}', got:\n  message: #{error.message}\n  root_cause: #{error.root_cause_message}"
  end

  # Evaluate a scalar expression that may contain single quotes.
  # Mirrors Java's TestContext.generateExpression which uses Util.singleQuoteString.
  def execute_expression(olap, expression, cube: "Sales")
    escaped = expression.gsub("'", "''")
    mdx = "WITH MEMBER [Measures].[_Expr] AS '#{escaped}' SELECT {[Measures].[_Expr]} ON 0 FROM [#{cube}]"
    olap.execute(mdx).formatted_values.flatten.first.to_s
  end

  # --- As (lines 3599-3983) ---

  # Java: FunctionTest#testAs
  it "AS operator used in Filter, sets, and error cases" do
    # Filter using alias
    assert_axis_returns @olap,
      "Filter([Customers].Children as t,\n" \
      "t.Current.Name = 'USA')",
      "[Customers].[USA]"

    # 'AS' and the ':' operator have similar precedence
    assert_query_returns @olap,
      "select\n" \
      "  filter(\n" \
      "    [Time].[1997].[Q1].[2] : [Time].[1997].[Q3].[9] as t," \
      "    mod(t.CurrentOrdinal, 2) = 0) on 0\n" \
      "from [Sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Time].[1997].[Q1].[2]}
        {[Time].[1997].[Q2].[4]}
        {[Time].[1997].[Q2].[6]}
        {[Time].[1997].[Q3].[8]}
        Row #0: 20,957
        Row #0: 20,179
        Row #0: 21,350
        Row #0: 21,697
      RESULT

    # AS member fails on SSAS
    assert_error_contains @olap,
      "select\n" \
      " {([Time].[1997].[Q1] as t).Children, \n" \
      "  t.Parent } on 0 \n" \
      "from [Sales]",
      "No function matches signature '<Set>.Children'"

    # Set of members. OK.
    assert_query_returns @olap,
      "select Measures.[Unit Sales] on 0, \n" \
      "  {[Time].[1997].Children as t, \n" \
      "   Descendants(t, [Time].[Month])} on 1 \n" \
      "from [Sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Time].[1997].[Q1]}
        {[Time].[1997].[Q2]}
        {[Time].[1997].[Q3]}
        {[Time].[1997].[Q4]}
        {[Time].[1997].[Q1].[1]}
        {[Time].[1997].[Q1].[2]}
        {[Time].[1997].[Q1].[3]}
        {[Time].[1997].[Q2].[4]}
        {[Time].[1997].[Q2].[5]}
        {[Time].[1997].[Q2].[6]}
        {[Time].[1997].[Q3].[7]}
        {[Time].[1997].[Q3].[8]}
        {[Time].[1997].[Q3].[9]}
        {[Time].[1997].[Q4].[10]}
        {[Time].[1997].[Q4].[11]}
        {[Time].[1997].[Q4].[12]}
        Row #0: 66,291
        Row #1: 62,610
        Row #2: 65,848
        Row #3: 72,024
        Row #4: 21,628
        Row #5: 20,957
        Row #6: 23,706
        Row #7: 20,179
        Row #8: 21,081
        Row #9: 21,350
        Row #10: 23,763
        Row #11: 21,697
        Row #12: 20,388
        Row #13: 19,958
        Row #14: 25,270
        Row #15: 26,796
      RESULT

    # Alias a member. Implicitly becomes set. OK.
    assert_query_returns @olap,
      "select Measures.[Unit Sales] on 0,\n" \
      "  {[Time].[1997] as t,\n" \
      "   Descendants(t, [Time].[Month])} on 1\n" \
      "from [Sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Time].[1997]}
        {[Time].[1997].[Q1].[1]}
        {[Time].[1997].[Q1].[2]}
        {[Time].[1997].[Q1].[3]}
        {[Time].[1997].[Q2].[4]}
        {[Time].[1997].[Q2].[5]}
        {[Time].[1997].[Q2].[6]}
        {[Time].[1997].[Q3].[7]}
        {[Time].[1997].[Q3].[8]}
        {[Time].[1997].[Q3].[9]}
        {[Time].[1997].[Q4].[10]}
        {[Time].[1997].[Q4].[11]}
        {[Time].[1997].[Q4].[12]}
        Row #0: 266,773
        Row #1: 21,628
        Row #2: 20,957
        Row #3: 23,706
        Row #4: 20,179
        Row #5: 21,081
        Row #6: 21,350
        Row #7: 23,763
        Row #8: 21,697
        Row #9: 20,388
        Row #10: 19,958
        Row #11: 25,270
        Row #12: 26,796
      RESULT

    # Alias a tuple. Implicitly becomes set.
    assert_error_contains @olap,
      "select Measures.[Unit Sales] on 0,\n" \
      "  {([Time].[1997], [Customers].[USA].[CA]) as t,\n" \
      "   Descendants(t, [Time].[Month])} on 1\n" \
      "from [Sales]",
      "Argument to Descendants function must be a member or set of members, not a set of tuples"
  end

  # Java: FunctionTest#testAs2
  it "AS operator with named set shadowing, multiple aliases, and error cases" do
    # Named set and alias with same name (t) and a second alias (t2).
    # Reference to t from within descendants resolves to alias, of type
    # [Time], because it is nearer.
    expected_result = <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales], [Gender].[F]}
      {[Measures].[Unit Sales], [Gender].[M]}
      Axis #2:
      {[Time].[1997].[Q1]}
      {[Time].[1997].[Q2]}
      {[Time].[1997].[Q3]}
      {[Time].[1997].[Q4]}
      {[Time].[1997].[Q1].[1]}
      {[Time].[1997].[Q2].[6]}
      {[Time].[1997].[Q4].[11]}
      Row #0: 32,910
      Row #0: 33,381
      Row #1: 30,992
      Row #1: 31,618
      Row #2: 32,599
      Row #2: 33,249
      Row #3: 35,057
      Row #3: 36,967
      Row #4: 10,932
      Row #4: 10,696
      Row #5: 10,466
      Row #5: 10,884
      Row #6: 12,320
      Row #6: 12,950
    RESULT

    assert_query_returns @olap,
      "with set t as [Gender].Children\n" \
      "select\n" \
      "  Measures.[Unit Sales] * t on 0,\n" \
      "  {\n" \
      "    [Time].[1997].Children as t,\n" \
      "    Filter(\n" \
      "      Descendants(t, [Time].[Month]) as t2,\n" \
      "      Mod(t2.CurrentOrdinal, 5) = 0)\n" \
      "  } on 1\n" \
      "from [Sales]",
      expected_result

    # Two aliases with same name. OK.
    assert_query_returns @olap,
      "select\n" \
      "  Measures.[Unit Sales] * [Gender].Children as t on 0,\n" \
      "  {[Time].[1997].Children as t,\n" \
      "    Filter(\n" \
      "      Descendants(t, [Time].[Month]) as t2,\n" \
      "      Mod(t2.CurrentOrdinal, 5) = 0)\n" \
      "  } on 1\n" \
      "from [Sales]",
      expected_result

    # Bug MONDRIAN-648 causes 'AS' to have lower precedence than '*'.
    # Skipped: Bug.BugMondrian648Fixed is false

    # Reference to hierarchy on other axis.
    assert_error_contains @olap,
      "select\n" \
      "  Measures.[Unit Sales] * ([Gender].Members as t) on 0,\n" \
      "  {t} on 1\n" \
      "from [Sales]",
      "MDX object 't' not found in cube 'Sales'"

    # As above, with parentheses. Tuple valued.
    assert_error_contains @olap,
      "select\n" \
      "  (Measures.[Unit Sales] * [Gender].Members) as t on 0,\n" \
      "  {t} on 1\n" \
      "from [Sales]",
      "MDX object 't' not found in cube 'Sales'"

    # Calculated set, CurrentMember
    assert_query_returns @olap,
      "select Measures.[Unit Sales] on 0,\n" \
      "  filter(\n" \
      "    (Time.Month.Members * Gender.Members) as s,\n" \
      "    (s.Current.Item(0).Parent, [Marital Status].[S], [Gender].[F]) > 17000) on 1\n" \
      "from [Sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Time].[1997].[Q4].[10], [Gender].[All Gender]}
        {[Time].[1997].[Q4].[10], [Gender].[F]}
        {[Time].[1997].[Q4].[10], [Gender].[M]}
        {[Time].[1997].[Q4].[11], [Gender].[All Gender]}
        {[Time].[1997].[Q4].[11], [Gender].[F]}
        {[Time].[1997].[Q4].[11], [Gender].[M]}
        {[Time].[1997].[Q4].[12], [Gender].[All Gender]}
        {[Time].[1997].[Q4].[12], [Gender].[F]}
        {[Time].[1997].[Q4].[12], [Gender].[M]}
        Row #0: 19,958
        Row #1: 9,506
        Row #2: 10,452
        Row #3: 25,270
        Row #4: 12,320
        Row #5: 12,950
        Row #6: 26,796
        Row #7: 13,231
        Row #8: 13,565
      RESULT

    # As above, but don't override [Gender] in filter condition.
    assert_query_returns @olap,
      "select Measures.[Unit Sales] on 0,\n" \
      "  filter(\n" \
      "    (Time.Month.Members * Gender.Members) as s,\n" \
      "    (s.Current.Item(0).Parent, [Marital Status].[S]) > 35000) on 1\n" \
      "from [Sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Time].[1997].[Q4].[10], [Gender].[All Gender]}
        {[Time].[1997].[Q4].[11], [Gender].[All Gender]}
        {[Time].[1997].[Q4].[12], [Gender].[All Gender]}
        Row #0: 19,958
        Row #1: 25,270
        Row #2: 26,796
      RESULT

    # Multiple definitions of alias within same axis
    assert_query_returns @olap,
      "select Measures.[Unit Sales] on 0,\n" \
      "  generate(\n" \
      "    [Marital Status].Children as s,\n" \
      "    filter(\n" \
      "      (Time.Month.Members * Gender.Members) as s,\n" \
      "      (s.Current.Item(0).Parent, [Marital Status].[S], [Gender].[F]) > 17000),\n" \
      "    ALL) on 1\n" \
      "from [Sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Time].[1997].[Q4].[10], [Gender].[All Gender]}
        {[Time].[1997].[Q4].[10], [Gender].[F]}
        {[Time].[1997].[Q4].[10], [Gender].[M]}
        {[Time].[1997].[Q4].[11], [Gender].[All Gender]}
        {[Time].[1997].[Q4].[11], [Gender].[F]}
        {[Time].[1997].[Q4].[11], [Gender].[M]}
        {[Time].[1997].[Q4].[12], [Gender].[All Gender]}
        {[Time].[1997].[Q4].[12], [Gender].[F]}
        {[Time].[1997].[Q4].[12], [Gender].[M]}
        {[Time].[1997].[Q4].[10], [Gender].[All Gender]}
        {[Time].[1997].[Q4].[10], [Gender].[F]}
        {[Time].[1997].[Q4].[10], [Gender].[M]}
        {[Time].[1997].[Q4].[11], [Gender].[All Gender]}
        {[Time].[1997].[Q4].[11], [Gender].[F]}
        {[Time].[1997].[Q4].[11], [Gender].[M]}
        {[Time].[1997].[Q4].[12], [Gender].[All Gender]}
        {[Time].[1997].[Q4].[12], [Gender].[F]}
        {[Time].[1997].[Q4].[12], [Gender].[M]}
        Row #0: 19,958
        Row #1: 9,506
        Row #2: 10,452
        Row #3: 25,270
        Row #4: 12,320
        Row #5: 12,950
        Row #6: 26,796
        Row #7: 13,231
        Row #8: 13,565
        Row #9: 19,958
        Row #10: 9,506
        Row #11: 10,452
        Row #12: 25,270
        Row #13: 12,320
        Row #14: 12,950
        Row #15: 26,796
        Row #16: 13,231
        Row #17: 13,565
      RESULT

    # Multiple definitions of alias within same axis. Reference from calc member.
    # On SSAS 2005, gives error, "The CURRENT function cannot be called in
    # current context because the 'x' set is not in scope".
    assert_error_contains @olap,
      "with member Measures.Foo as 'x.Current.Name'\n" \
      "select\n" \
      "  {Measures.[Unit Sales], Measures.Foo} on 0,\n" \
      "  generate(\n" \
      "    [Marital Status].\n" \
      "    Children as x,\n" \
      "    filter(\n" \
      "      Gender.Members as x,\n" \
      "      (x.Current, [Marital Status].[S]) > 50000),\n" \
      "    ALL) on 1\n" \
      "from [Sales]",
      "MDX object 'x' not found in cube 'Sales'"

    # As above, but set is not out of scope; it does not exist; but error
    # should be the same.
    assert_error_contains @olap,
      "with member Measures.Foo as 'z.Current.Name'\n" \
      "select\n" \
      "  {Measures.[Unit Sales], Measures.Foo} on 0,\n" \
      "  generate(\n" \
      "    [Marital Status].\n" \
      "    Children as s,\n" \
      "    filter(\n" \
      "      Gender.Members as s,\n" \
      "      (s.Current, [Marital Status].[S]) > 50000),\n" \
      "    ALL) on 1\n" \
      "from [Sales]",
      "MDX object 'z' not found in cube 'Sales'"

    # 'set AS string' is invalid
    assert_error_contains @olap,
      "select Measures.[Unit Sales] on 0,\n" \
      "  filter(\n" \
      "    (Time.Month.Members * Gender.Members) as 'foo',\n" \
      "    (s.Current.Item(0).Parent, [Marital Status].[S]) > 50000) on 1\n" \
      "from [Sales]",
      "Syntax error at line 3, column 46, token ''foo''"

    # 'set AS numeric' is invalid
    assert_error_contains @olap,
      "select Measures.[Unit Sales] on 0,\n" \
      "  filter(\n" \
      "    (Time.Month.Members * Gender.Members) as 1234,\n" \
      "    (s.Current.Item(0).Parent, [Marital Status].[S]) > 50000) on 1\n" \
      "from [Sales]",
      "Syntax error at line 3, column 46, token '1234'"

    # 'numeric AS identifier' is invalid
    assert_error_contains @olap,
      "select Measures.[Unit Sales] on 0,\n" \
      "  filter(\n" \
      "    123 * 456 as s,\n" \
      "    (s.Current.Item(0).Parent, [Marital Status].[S]) > 50000) on 1\n" \
      "from [Sales]",
      "No function matches signature '<Numeric Expression> AS <Set>'"
  end

  # --- SetItem/Tuple (lines 5576-5917) ---

  # Java: FunctionTest#testSetItemInt
  it "Set.Item(int) retrieves members and tuples by index" do
    assert_axis_returns @olap,
      "{[Customers].[All Customers].[USA].[OR].[Lebanon].[Mary Frances Christian]}.Item(0)",
      "[Customers].[USA].[OR].[Lebanon].[Mary Frances Christian]"

    assert_axis_returns @olap,
      "{[Customers].[All Customers].[USA]," \
      "[Customers].[All Customers].[USA].[WA]," \
      "[Customers].[All Customers].[USA].[CA]," \
      "[Customers].[All Customers].[USA].[OR].[Lebanon].[Mary Frances Christian]}.Item(2)",
      "[Customers].[USA].[CA]"

    assert_axis_returns @olap,
      "{[Customers].[All Customers].[USA]," \
      "[Customers].[All Customers].[USA].[WA]," \
      "[Customers].[All Customers].[USA].[CA]," \
      "[Customers].[All Customers].[USA].[OR].[Lebanon].[Mary Frances Christian]}.Item(100 / 50 - 1)",
      "[Customers].[USA].[WA]"

    assert_axis_returns @olap,
      "{([Time].[1997].[Q1].[1], [Customers].[All Customers].[USA])," \
      "([Time].[1997].[Q1].[2], [Customers].[All Customers].[USA].[WA])," \
      "([Time].[1997].[Q1].[3], [Customers].[All Customers].[USA].[CA])," \
      "([Time].[1997].[Q2].[4], [Customers].[All Customers].[USA].[OR].[Lebanon].[Mary Frances Christian])}" \
      ".Item(100 / 50 - 1)",
      "{[Time].[1997].[Q1].[2], [Customers].[USA].[WA]}"

    # given index out of bounds, item returns null
    assert_axis_returns @olap,
      "{[Customers].[All Customers].[USA]," \
      "[Customers].[All Customers].[USA].[WA]," \
      "[Customers].[All Customers].[USA].[CA]," \
      "[Customers].[All Customers].[USA].[OR].[Lebanon].[Mary Frances Christian]}.Item(-1)",
      ""

    # given index out of bounds, item returns null
    assert_axis_returns @olap,
      "{[Customers].[All Customers].[USA]," \
      "[Customers].[All Customers].[USA].[WA]," \
      "[Customers].[All Customers].[USA].[CA]," \
      "[Customers].[All Customers].[USA].[OR].[Lebanon].[Mary Frances Christian]}.Item(4)",
      ""
  end

  # Java: FunctionTest#testSetItemString
  it "Set.Item(String) retrieves members by name" do
    assert_axis_returns @olap,
      '{[Gender].[M], [Gender].[F]}.Item("M")',
      "[Gender].[M]"

    assert_axis_returns @olap,
      '{CrossJoin([Gender].Members, [Marital Status].Members)}.Item("M", "S")',
      "{[Gender].[M], [Marital Status].[S]}"

    # MSAS fails with "duplicate dimensions across (independent) axes".
    assert_axis_returns @olap,
      '{CrossJoin([Gender].Members, [Marital Status].Members)}.Item("M", "M")',
      "{[Gender].[M], [Marital Status].[M]}"

    # None found.
    assert_axis_returns @olap,
      '{[Gender].[M], [Gender].[F]}.Item("X")',
      ""

    assert_axis_returns @olap,
      '{CrossJoin([Gender].Members, [Marital Status].Members)}.Item("M", "F")',
      ""

    assert_axis_returns @olap,
      'CrossJoin([Gender].Members, [Marital Status].Members).Item("S", "M")',
      ""

    assert_error_contains @olap,
      'SELECT {CrossJoin([Gender].Members, [Marital Status].Members).Item("M")} ON 0 FROM [Sales]',
      "Argument count does not match set's cardinality 2"
  end

  # Java: FunctionTest#testTuple
  it "tuple expression evaluates correctly" do
    assert_expression_returns @olap,
      "([Gender].[M], " \
      "[Time].[Time].Children.Item(2), " \
      "[Measures].[Unit Sales])",
      "33,249"
  end

  # Java: FunctionTest#testTupleArgTypes
  it "tuple operator applied to arguments of various types" do
    # can coerce dimensions (if they have a unique hierarchy) and
    # hierarchies to members
    assert_expression_returns @olap,
      "([Gender], [Time].[Time])",
      "266,773"

    # can coerce hierarchy to member
    assert_expression_returns @olap,
      "([Gender].[M], [Time.Weekly])",
      "135,215"

    # cannot coerce level to member
    assert_error_contains @olap,
      "SELECT {([Gender].[M], [Store].[Store City])} ON 0 FROM [Sales]",
      "No function matches signature '(<Member>, <Level>)'"

    # coerce args (hierarchy, member, member, dimension)
    # Note: Java expected values use SSAS-style [Time].[Weekly] naming, but Mondrian
    # with SsasCompatibleNaming=false produces [Time.Weekly] naming.
    assert_axis_returns @olap,
      "{([Time.Weekly], [Measures].[Store Sales], [Marital Status].[M], [Promotion Media])}",
      "{[Time.Weekly].[All Time.Weeklys], [Measures].[Store Sales], [Marital Status].[M], [Promotion Media].[All Media]}"

    # usage of different hierarchies in the [Time] dimension
    assert_axis_returns @olap,
      "{([Time.Weekly], [Measures].[Store Sales], [Marital Status].[M], [Time].[Time])}",
      "{[Time.Weekly].[All Time.Weeklys], [Measures].[Store Sales], [Marital Status].[M], [Time].[1997]}"

    # two usages of the [Time].[Weekly] hierarchy
    assert_error_contains @olap,
      "SELECT {([Time.Weekly], [Measures].[Store Sales], [Marital Status].[M], [Time.Weekly])} ON 0 FROM [Sales]",
      "Tuple contains more than one member of hierarchy '[Time.Weekly]'."

    # cannot coerce integer to member
    assert_error_contains @olap,
      "SELECT {([Gender].[M], 123)} ON 0 FROM [Sales]",
      "No function matches signature '(<Member>, <Numeric Expression>)'"
  end

  # Java: FunctionTest#testTupleItem
  it "Tuple.Item(n) retrieves member at position" do
    assert_axis_returns @olap,
      "([Time].[1997].[Q1].[1], [Customers].[All Customers].[USA].[OR], [Gender].[All Gender].[M]).item(2)",
      "[Gender].[M]"

    assert_axis_returns @olap,
      "([Time].[1997].[Q1].[1], [Customers].[All Customers].[USA].[OR], [Gender].[All Gender].[M]).item(1)",
      "[Customers].[USA].[OR]"

    assert_axis_returns @olap,
      "{[Time].[1997].[Q1].[1]}.item(0)",
      "[Time].[1997].[Q1].[1]"

    assert_axis_returns @olap,
      "{[Time].[1997].[Q1].[1]}.Item(0).Item(0)",
      "[Time].[1997].[Q1].[1]"

    # given out of bounds index, item returns null
    assert_axis_returns @olap,
      "([Time].[1997].[Q1].[1], [Customers].[All Customers].[USA].[OR], [Gender].[All Gender].[M]).item(-1)",
      ""

    # given out of bounds index, item returns null
    assert_axis_returns @olap,
      "([Time].[1997].[Q1].[1], [Customers].[All Customers].[USA].[OR], [Gender].[All Gender].[M]).item(500)",
      ""

    # empty set
    assert_expression_returns @olap,
      "Filter([Gender].members, 1 = 0).Item(0)",
      ""

    # empty set of unknown type
    assert_expression_returns @olap,
      "{}.Item(3)",
      ""

    # past end of set
    assert_expression_returns @olap,
      "{[Gender].members}.Item(4)",
      ""

    # negative index
    assert_expression_returns @olap,
      "{[Gender].members}.Item(-50)",
      ""
  end

  # Java: FunctionTest#testTupleAppliedToUnknownHierarchy
  it "tuple applied to unknown hierarchy via Dimensions(0)" do
    # manifestation of bug 1735821
    assert_query_returns @olap,
      "with \n" \
      "member [Product].[Test] as '([Product].[Food],Dimensions(0).defaultMember)' \n" \
      "select \n" \
      "{[Product].[Test], [Product].[Food]} on columns, \n" \
      "{[Measures].[Store Sales]} on rows \n" \
      "from Sales",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Product].[Test]}
        {[Product].[Food]}
        Axis #2:
        {[Measures].[Store Sales]}
        Row #0: 191,940.00
        Row #0: 409,035.59
      RESULT
  end

  # Java: FunctionTest#testTupleDepends
  # TODO: Depends tests require TestContext.assertMemberExprDependsOn / assertExprDependsOn
  # which are not available in the JRuby test framework.
  it "tuple depends on expected hierarchies" do
    skip "depends tests require TestContext.assertMemberExprDependsOn"
  end

  # Java: FunctionTest#testItemNull
  it "Item on empty set returns null member with accessible properties" do
    # Mondrian represents null members as actual objects, so its behavior
    # is different from MSAS.

    # MSAS returns error here.
    assert_expression_returns @olap,
      "Filter([Gender].members, 1 = 0).Item(0).Dimension.Name",
      "Gender"

    # MSAS returns error here.
    assert_expression_returns @olap,
      "Filter([Gender].members, 1 = 0).Item(0).Parent",
      ""

    assert_expression_returns @olap,
      "(Filter([Store].members, 0 = 0).Item(0).Item(0)," \
      "Filter([Store].members, 0 = 0).Item(0).Item(0))",
      "266,773"

    # MSAS returns error here.
    assert_expression_returns @olap,
      "Filter([Gender].members, 1 = 0).Item(0).Name",
      "#null"
  end

  # Java: FunctionTest#testTupleNull
  it "tuple containing null members evaluates to null" do
    # if a tuple contains any null members, it evaluates to null
    assert_query_returns @olap,
      "select {[Measures].[Unit Sales]} on columns,\n" \
      " { ([Gender].[M], [Store]),\n" \
      "   ([Gender].[F], [Store].parent),\n" \
      "   ([Gender].parent, [Store])} on rows\n" \
      "from [Sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Gender].[M], [Store].[All Stores]}
        Row #0: 135,215
      RESULT

    # the set function eliminates tuples which are wholly or partially null
    assert_axis_returns @olap,
      "([Gender].parent, [Marital Status]),\n" \
      " ([Gender].[M], [Marital Status].parent),\n" \
      " ([Gender].parent, [Marital Status].parent),\n" \
      " ([Gender].[M], [Marital Status])",
      "{[Gender].[M], [Marital Status].[All Marital Status]}"

    # The tuple constructor returns a null tuple if one of its
    # arguments is null -- and the Item function returns null if the
    # tuple is null.
    assert_expression_returns @olap,
      "([Gender].parent, [Marital Status]).Item(0).Name",
      "#null"

    assert_expression_returns @olap,
      "([Gender].parent, [Marital Status]).Item(1).Name",
      "#null"
  end

  # Java: FunctionTest#testLevelMemberExpressions
  it "Level.Member expressions resolve correctly" do
    # Should return Beverly Hills in California.
    assert_axis_returns @olap,
      "[Store].[Store City].[Beverly Hills]",
      "[Store].[USA].[CA].[Beverly Hills]"

    # There are two months named "1" in the time dimension: one
    # for 1997 and one for 1998. <Level>.<Member> should return
    # the first one.
    assert_axis_returns @olap,
      "[Time].[Month].[1]",
      "[Time].[1997].[Q1].[1]"

    # Shouldn't be able to find a member named "Q1" on the month level.
    assert_error_contains @olap,
      "SELECT {[Time].[Month].[Q1]} ON 0 FROM [Sales]",
      "MDX object '[Time].[Month].[Q1]' not found in cube"
  end

  # --- Properties (lines 6066-6142) ---

  # Java: FunctionTest#testPropertiesExpr
  it "Properties function returns member property value" do
    assert_expression_returns @olap,
      '[Store].[USA].[CA].[Beverly Hills].[Store 6].Properties("Store Type")',
      "Gourmet Supermarket"
  end

  # Java: FunctionTest#testPropertiesOnDimension
  it "Properties function works on dimension and hierarchy implicitly converted to member" do
    # [Store] is a dimension. When called with a property like FirstChild,
    # it is implicitly converted to a member.
    assert_axis_returns @olap,
      "[Store].FirstChild",
      "[Store].[Canada]"

    # Dimension is implicitly converted to member.
    assert_equal "[Store].[All Stores]",
      execute_expression(@olap, "[Store].Properties('MEMBER_UNIQUE_NAME')")

    # Hierarchy is implicitly converted to member.
    assert_equal "[Store].[All Stores]",
      execute_expression(@olap, "[Store].[USA].Hierarchy.Properties('MEMBER_UNIQUE_NAME')")
  end

  # Java: FunctionTest#testPropertiesNonExistent
  it "Properties function with non-existent property throws error" do
    # Java's assertExprThrows checks cell.isError() - the query succeeds
    # but the cell value contains the error.
    expression = "[Store].[USA].[CA].[Beverly Hills].[Store 6].Properties('Foo')"
    escaped = expression.gsub("'", "''")
    result = @olap.execute(
      "WITH MEMBER [Measures].[_Expr] AS '#{escaped}' " \
      "SELECT {[Measures].[_Expr]} ON 0 FROM [Sales]"
    )
    cell = result.raw_cell_set.getCell(java.util.Arrays.asList(java.lang.Integer.new(0)))
    assert cell.isError, "Expected error cell"
    assert cell.getValue.to_s.include?("Property 'Foo' is not valid for"),
      "Expected error about property Foo, got: #{cell.getValue}"
  end

  # Java: FunctionTest#testPropertiesFilter
  it "Properties function used in Filter to find Supermarket stores" do
    result = @olap.execute(
      "SELECT { [Store Sales] } ON COLUMNS,\n" \
      " TOPCOUNT(Filter( [Store].[Store Name].Members,\n" \
      '                   [Store].CurrentMember.Properties("Store Type") = "Supermarket"),' \
      "\n           10, [Store Sales]) ON ROWS\n" \
      "FROM [Sales]"
    )
    axis = result.raw_cell_set.getAxes.get(1)
    assert_equal 8, axis.getPositions.size
  end

  # Java: FunctionTest#testPropertyInCalculatedMember
  it "property used in calculated member formula" do
    result = @olap.execute(
      "WITH MEMBER [Measures].[Store Sales per Sqft]\n" \
      "AS '[Measures].[Store Sales] / " \
      "  [Store].CurrentMember.Properties(\"Store Sqft\")'\n" \
      "SELECT \n" \
      "  {[Measures].[Unit Sales], [Measures].[Store Sales per Sqft]} ON COLUMNS,\n" \
      "  {[Store].[Store Name].members} ON ROWS\n" \
      "FROM Sales"
    )
    cell_set = result.raw_cell_set
    axis = cell_set.getAxes.get(1)
    member = axis.getPositions.get(18).getMembers.get(0)
    assert_equal "[Store].[USA].[WA].[Bellingham].[Store 2]", member.getUniqueName

    cell = cell_set.getCell(java.util.Arrays.asList(java.lang.Integer.new(0), java.lang.Integer.new(18)))
    assert_equal "2,237", cell.getFormattedValue

    cell = cell_set.getCell(java.util.Arrays.asList(java.lang.Integer.new(1), java.lang.Integer.new(18)))
    assert_equal ".17", cell.getFormattedValue

    member = axis.getPositions.get(3).getMembers.get(0)
    assert_equal "[Store].[Mexico].[DF].[San Andres].[Store 21]", member.getUniqueName

    cell = cell_set.getCell(java.util.Arrays.asList(java.lang.Integer.new(0), java.lang.Integer.new(3)))
    assert_equal "", cell.getFormattedValue

    cell = cell_set.getCell(java.util.Arrays.asList(java.lang.Integer.new(1), java.lang.Integer.new(3)))
    assert_equal "", cell.getFormattedValue
  end

  # --- LinReg (lines 10177-10566) ---

  # Java: FunctionTest#testLinRegPointQuarter
  it "LinRegPoint on quarterly data" do
    assert_query_returns @olap,
      "WITH MEMBER [Measures].[Test] as \n" \
      "  'LinRegPoint(\n" \
      "    Rank(Time.[Time].CurrentMember, Time.[Time].CurrentMember.Level.Members),\n" \
      "    Descendants([Time].[1997], [Time].[Quarter]), \n" \
      "[Measures].[Store Sales], \n" \
      "    Rank(Time.[Time].CurrentMember, Time.[Time].CurrentMember.Level.Members))' \n" \
      "SELECT \n" \
      "{[Measures].[Test],[Measures].[Store Sales]} ON ROWS, \n" \
      "{[Time].[1997].Children} ON COLUMNS \n" \
      "FROM Sales",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Time].[1997].[Q1]}
        {[Time].[1997].[Q2]}
        {[Time].[1997].[Q3]}
        {[Time].[1997].[Q4]}
        Axis #2:
        {[Measures].[Test]}
        {[Measures].[Store Sales]}
        Row #0: 134,299.22
        Row #0: 138,972.76
        Row #0: 143,646.30
        Row #0: 148,319.85
        Row #1: 139,628.35
        Row #1: 132,666.27
        Row #1: 140,271.89
        Row #1: 152,671.62
      RESULT
  end

  # Java: FunctionTest#testLinRegPointMonth
  it "LinRegPoint on monthly data" do
    assert_query_returns @olap,
      "WITH MEMBER \n" \
      "[Measures].[Test] as \n" \
      "  'LinRegPoint(\n" \
      "    Rank(Time.[Time].CurrentMember, Time.[Time].CurrentMember.Level.Members),\n" \
      "    Descendants([Time].[1997], [Time].[Month]), \n" \
      "    [Measures].[Store Sales], \n" \
      "    Rank(Time.[Time].CurrentMember, Time.[Time].CurrentMember.Level.Members)\n" \
      " )' \n" \
      "SELECT \n" \
      "  {[Measures].[Test],[Measures].[Store Sales]} ON ROWS, \n" \
      "  Descendants([Time].[1997], [Time].[Month]) ON COLUMNS \n" \
      "FROM Sales",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Time].[1997].[Q1].[1]}
        {[Time].[1997].[Q1].[2]}
        {[Time].[1997].[Q1].[3]}
        {[Time].[1997].[Q2].[4]}
        {[Time].[1997].[Q2].[5]}
        {[Time].[1997].[Q2].[6]}
        {[Time].[1997].[Q3].[7]}
        {[Time].[1997].[Q3].[8]}
        {[Time].[1997].[Q3].[9]}
        {[Time].[1997].[Q4].[10]}
        {[Time].[1997].[Q4].[11]}
        {[Time].[1997].[Q4].[12]}
        Axis #2:
        {[Measures].[Test]}
        {[Measures].[Store Sales]}
        Row #0: 43,824.36
        Row #0: 44,420.51
        Row #0: 45,016.66
        Row #0: 45,612.81
        Row #0: 46,208.95
        Row #0: 46,805.10
        Row #0: 47,401.25
        Row #0: 47,997.40
        Row #0: 48,593.55
        Row #0: 49,189.70
        Row #0: 49,785.85
        Row #0: 50,382.00
        Row #1: 45,539.69
        Row #1: 44,058.79
        Row #1: 50,029.87
        Row #1: 42,878.25
        Row #1: 44,456.29
        Row #1: 45,331.73
        Row #1: 50,246.88
        Row #1: 46,199.04
        Row #1: 43,825.97
        Row #1: 42,342.27
        Row #1: 53,363.71
        Row #1: 56,965.64
      RESULT
  end

  # Java: FunctionTest#testLinRegIntercept
  it "LinRegIntercept returns expected intercept value" do
    mdx = <<~MDX
      WITH MEMBER [Measures].[_Expr] AS 'LinRegIntercept([Time].[Month].members, [Measures].[Unit Sales], [Measures].[Store Sales])'
      SELECT {[Measures].[_Expr]} ON 0
      FROM [Sales]
    MDX
    actual = @olap.execute(mdx).formatted_values.flatten.first.to_f
    assert_in_delta(-126.65, actual, 0.50)

    # format does not add '$'
    # first expr constant
    mdx = <<~MDX
      WITH MEMBER [Measures].[_Expr] AS 'LinRegIntercept([Time].[Month].members, 7, [Measures].[Store Sales])'
      SELECT {[Measures].[_Expr]} ON 0
      FROM [Sales]
    MDX
    actual = @olap.execute(mdx).formatted_values.flatten.first.to_f
    assert_in_delta(7.00, actual, 0.01)
  end

  # Java: FunctionTest#testLinRegSlope
  it "LinRegSlope returns expected slope value" do
    mdx = <<~MDX
      WITH MEMBER [Measures].[_Expr] AS 'LinRegSlope([Time].[Month].members, [Measures].[Unit Sales], [Measures].[Store Sales])'
      SELECT {[Measures].[_Expr]} ON 0
      FROM [Sales]
    MDX
    actual = @olap.execute(mdx).formatted_values.flatten.first.to_f
    assert_in_delta(0.4746, actual, 0.50)

    # first expr constant
    mdx = <<~MDX
      WITH MEMBER [Measures].[_Expr] AS 'LinRegSlope([Time].[Month].members, 7, [Measures].[Store Sales])'
      SELECT {[Measures].[_Expr]} ON 0
      FROM [Sales]
    MDX
    actual = @olap.execute(mdx).formatted_values.flatten.first.to_f
    assert_in_delta(0.00, actual, 0.01)
  end

  # Java: FunctionTest#testLinRegPoint
  it "LinRegPoint with constant first expression returns constant" do
    # format does not add '$'
    mdx = <<~MDX
      WITH MEMBER [Measures].[_Expr] AS 'LinRegPoint([Measures].[Unit Sales], [Time].[Month].members, 7, [Measures].[Store Sales])'
      SELECT {[Measures].[_Expr]} ON 0
      FROM [Sales]
    MDX
    actual = @olap.execute(mdx).formatted_values.flatten.first.to_f
    assert_in_delta(7.00, actual, 0.01)
  end

  # --- Cast (lines 11385-11475) ---

  # Java: FunctionTest#testCast
  it "Cast converts between types" do
    # NOTE: Some of these tests fail with 'cannot convert ...', and they
    # probably shouldn't. Feel free to fix the conversion.

    # From double to integer. MONDRIAN-1631
    assert_expression_returns @olap, "Cast(1.4 As Integer)", "1"

    # From integer
    # To integer (trivial)
    assert_expression_returns @olap, "0 + Cast(1 + 2 AS Integer)", "3"
    # To String
    assert_equal "3.0", execute_expression(@olap, "'' || Cast(1 + 2 AS String)")
    # To Boolean
    assert_expression_returns @olap, "1=1 AND Cast(1 + 2 AS Boolean)", "true"
    assert_expression_returns @olap, "1=1 AND Cast(1 - 1 AS Boolean)", "false"

    # From boolean
    # To String
    assert_equal "false", execute_expression(@olap, "'' || Cast((1 = 1 AND 1 = 2) AS String)")

    # This case demonstrates the relative precedence of 'AS' in 'CAST'
    # and 'AS' for creating inline named sets. See also bug MONDRIAN-648.
    assert_equal "xxxfalse", execute_expression(@olap, "'xxx' || Cast(1 = 1 AND 1 = 2 AS String)")

    # To boolean (trivial)
    assert_expression_returns @olap,
      "1=1 AND Cast((1 = 1 AND 1 = 2) AS Boolean)",
      "false"

    assert_expression_returns @olap,
      "1=1 OR Cast(1 = 1 AND 1 = 2 AS Boolean)",
      "true"

    # From null: should not throw exceptions
    # To Integer: Expect to return NULL
    assert_expression_returns @olap, "0 * Cast(NULL AS Integer)", ""

    # To Numeric: Expect to return NULL
    assert_expression_returns @olap, "0 * Cast(NULL AS Numeric)", ""

    # To String: Expect to return "null"
    assert_equal "null", execute_expression(@olap, "'' || Cast(NULL AS String)")

    # To Boolean: Expect to return NULL, but since FunUtil.BooleanNull
    # does not implement three-valued boolean logic yet, this will return false
    assert_expression_returns @olap, "1=1 AND Cast(NULL AS Boolean)", "false"

    # Double is not allowed as a type
    assert_error_contains @olap,
      "WITH MEMBER [Measures].[_Expr] AS 'Cast(1 AS Double)' " \
      "SELECT {[Measures].[_Expr]} ON 0 FROM [Sales]",
      "Unknown type 'Double'; values are NUMERIC, STRING, BOOLEAN"

    # An integer constant is not allowed as a type
    assert_error_contains @olap,
      "WITH MEMBER [Measures].[_Expr] AS 'Cast(1 AS 5)' " \
      "SELECT {[Measures].[_Expr]} ON 0 FROM [Sales]",
      "Syntax error at line 1, column 11, token '5'"

    assert_equal "true", execute_expression(@olap, "Cast('tr' || 'ue' AS boolean)")
  end

  # Java: FunctionTest#testCastBug524
  it "Cast bug 524: VB functions with Cast to String" do
    assert_expression_returns @olap,
      "Cast(Int([Measures].[Store Sales] / 3600) as String)",
      "157"
  end

  # --- DumpFunctions (line 11476) ---

  # Java: FunctionTest#testDumpFunctions
  it "BuiltinFunTable has expected number of functions" do
    fun_info_list = Java::MondrianOlapFun::BuiltinFunTable.instance.getFunInfoList
    assert_equal 325, fun_info_list.size
  end

  # --- ComplexOrExpr (line 11540) ---

  # Java: FunctionTest#testComplexOrExpr
  it "complex OR expression with multiple aggregates in filter" do
    # make sure all aggregates referenced in the OR expression are
    # processed in a single load request by setting the eval depth to
    # a value smaller than the number of measures
    with_properties(MaxEvalDepth: 3) do
      assert_query_returns @olap,
        "with set [*NATIVE_CJ_SET] as '[Store].[Store Country].members' " \
        "set [*GENERATED_MEMBERS_Measures] as " \
        "    '{[Measures].[Unit Sales], [Measures].[Store Cost], " \
        "    [Measures].[Sales Count], [Measures].[Customer Count], " \
        "    [Measures].[Promotion Sales]}' " \
        "set [*GENERATED_MEMBERS] as " \
        "    'Generate([*NATIVE_CJ_SET], {[Store].CurrentMember})' " \
        "member [Store].[*SUBTOTAL_MEMBER_SEL~SUM] as 'Sum([*GENERATED_MEMBERS])' " \
        "select [*GENERATED_MEMBERS_Measures] ON COLUMNS, " \
        "NON EMPTY " \
        "    Filter(" \
        "        Generate(" \
        "        [*NATIVE_CJ_SET], " \
        "        {[Store].CurrentMember}), " \
        "        (((((NOT IsEmpty([Measures].[Unit Sales])) OR " \
        "            (NOT IsEmpty([Measures].[Store Cost]))) OR " \
        "            (NOT IsEmpty([Measures].[Sales Count]))) OR " \
        "            (NOT IsEmpty([Measures].[Customer Count]))) OR " \
        "            (NOT IsEmpty([Measures].[Promotion Sales])))) " \
        "on rows " \
        "from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Unit Sales]}
          {[Measures].[Store Cost]}
          {[Measures].[Sales Count]}
          {[Measures].[Customer Count]}
          {[Measures].[Promotion Sales]}
          Axis #2:
          {[Store].[USA]}
          Row #0: 266,773
          Row #0: 225,627.23
          Row #0: 86,837
          Row #0: 5,581
          Row #0: 151,211.21
        RESULT
    end
  end

  # --- Cache/VBA/Excel (lines 11966-12042) ---

  # Java: FunctionTest#testCache
  it "Cache function works with various data types" do
    # test various data types: integer, string, member, set, tuple
    assert_expression_returns @olap, "Cache(1 + 2)", "3"
    assert_equal "foobar", execute_expression(@olap, "Cache('foo' || 'bar')")

    assert_axis_returns @olap,
      "[Gender].Children",
      "[Gender].[F]\n" \
      "[Gender].[M]"

    assert_axis_returns @olap,
      "([Gender].[M], [Marital Status].[S].PrevMember)",
      "{[Gender].[M], [Marital Status].[M]}"

    # inside another expression
    assert_axis_returns @olap,
      "Order(Cache([Gender].Children), Cache(([Measures].[Unit Sales], [Time].[1997].[Q1])), BDESC)",
      "[Gender].[M]\n" \
      "[Gender].[F]"

    # doesn't work with multiple args
    assert_error_contains @olap,
      "WITH MEMBER [Measures].[_Expr] AS 'Cache(1, 2)' " \
      "SELECT {[Measures].[_Expr]} ON 0 FROM [Sales]",
      "No function matches signature 'Cache(<Numeric Expression>, <Numeric Expression>)'"
  end

  # Java: FunctionTest#testVbaBasic
  it "VBA Exp function works correctly" do
    # Exp is a simple function: one arg.
    assert_expression_returns @olap, "exp(0)", "1"

    # exp(1) should return E. Use raw cell value for numeric precision.
    result = @olap.execute(
      "WITH MEMBER [Measures].[_Expr] AS 'exp(1)' SELECT {[Measures].[_Expr]} ON 0 FROM [Sales]"
    )
    cell = result.raw_cell_set.getCell(java.util.Arrays.asList(java.lang.Integer.new(0)))
    assert_in_delta(Math::E, cell.getValue.to_f, 0.00000001)

    result = @olap.execute(
      "WITH MEMBER [Measures].[_Expr] AS 'exp(-2)' SELECT {[Measures].[_Expr]} ON 0 FROM [Sales]"
    )
    cell = result.raw_cell_set.getCell(java.util.Arrays.asList(java.lang.Integer.new(0)))
    assert_in_delta(1.0 / (Math::E * Math::E), cell.getValue.to_f, 0.00000001)

    # If any arg is null, result is null.
    assert_expression_returns @olap, "exp(cast(null as numeric))", ""
  end

  # Java: FunctionTest#testVbaOverloading
  it "VBA Replace function with variable number of args" do
    assert_equal "azaz", execute_expression(@olap, "replace('xyzxyz', 'xy', 'a')")
    assert_equal "xyzaz", execute_expression(@olap, "replace('xyzxyz', 'xy', 'a', 2)")
    assert_equal "azxyz", execute_expression(@olap, "replace('xyzxyz', 'xy', 'a', 1, 1)")
  end

  # Java: FunctionTest#testVbaExceptions
  it "VBA function Right with negative length throws exception" do
    # Java's assertExprThrows checks cell.isError() - the query succeeds
    # but the cell value contains the error.
    expression = 'right("abc", -4)'
    escaped = expression.gsub("'", "''")
    result = @olap.execute(
      "WITH MEMBER [Measures].[_Expr] AS '#{escaped}' " \
      "SELECT {[Measures].[_Expr]} ON 0 FROM [Sales]"
    )
    cell = result.raw_cell_set.getCell(java.util.Arrays.asList(java.lang.Integer.new(0)))
    assert cell.isError, "Expected error cell"
    assert cell.getValue.to_s.include?("StringIndexOutOfBoundsException"),
      "Expected StringIndexOutOfBoundsException, got: #{cell.getValue}"
  end

  # Java: FunctionTest#testVbaDateTime
  it "VBA date functions DateSerial and Year" do
    # function which returns date
    assert_equal "Saturday, April 29, 2006",
      execute_expression(@olap, 'Format(DateSerial(2006, 4, 29), "Long Date")')

    # function with date parameter
    assert_expression_returns @olap,
      "Year(DateSerial(2006, 4, 29))",
      "2,006"
  end

  # Java: FunctionTest#testExcelPi
  it "Excel Pi function returns 3" do
    # The PI function is defined in the Excel class.
    assert_expression_returns @olap, "Pi()", "3"
  end

  # Java: FunctionTest#testExcelPower
  it "Excel Power function" do
    mdx = <<~MDX
      WITH MEMBER [Measures].[_Expr] AS 'Power(8, 0.333333)'
      SELECT {[Measures].[_Expr]} ON 0
      FROM [Sales]
    MDX
    actual = @olap.execute(mdx).formatted_values.flatten.first.to_f
    assert_in_delta(2.0, actual, 0.01)

    # Power(-2, 0.5) returns NaN
    result = @olap.execute(
      "WITH MEMBER [Measures].[_Expr] AS 'Power(-2, 0.5)' SELECT {[Measures].[_Expr]} ON 0 FROM [Sales]"
    )
    cell = result.raw_cell_set.getCell(java.util.Arrays.asList(java.lang.Integer.new(0)))
    assert cell.getValue.to_f.nan?, "Expected NaN for Power(-2, 0.5)"
  end

  # --- Misc bugs/features (lines 12043-12139) ---

  # Java: FunctionTest#testBug1881739
  it "LEFT with LEN as length argument (bug 1881739)" do
    # the reason for this is that in AbstractExpCompiler in the compileInteger
    # method we are casting an IntegerCalc into a DoubleCalc and there is no
    # check for IntegerCalc in the NumericType conditional path.
    assert_equal "TEST", execute_expression(@olap, 'LEFT("TEST", LEN("TEST"))')
  end

  # Java: FunctionTest#testCubeTimeDimensionFails
  it "time-dependent functions fail on cube without time dimension" do
    assert_error_contains @olap,
      "select LastPeriods(1) on columns from [Store]",
      "'LastPeriods', no time dimension"
    assert_error_contains @olap,
      "select OpeningPeriod() on columns from [Store]",
      "'OpeningPeriod', no time dimension"
    assert_error_contains @olap,
      "select OpeningPeriod([Store Type]) on columns from [Store]",
      "'OpeningPeriod', no time dimension"
    assert_error_contains @olap,
      "select ClosingPeriod() on columns from [Store]",
      "'ClosingPeriod', no time dimension"
    assert_error_contains @olap,
      "select ClosingPeriod([Store Type]) on columns from [Store]",
      "'ClosingPeriod', no time dimension"
    assert_error_contains @olap,
      "select ParallelPeriod() on columns from [Store]",
      "'ParallelPeriod', no time dimension"
    assert_error_contains @olap,
      "select PeriodsToDate() on columns from [Store]",
      "'PeriodsToDate', no time dimension"
    assert_error_contains @olap,
      "select Mtd() on columns from [Store]",
      "'Mtd', no time dimension"
  end

  # Java: FunctionTest#testFilterEmpty
  it "Filter on empty set returns empty" do
    # Unlike "Descendants(<set>, ...)", we do not need to know the precise
    # type of the set, therefore it is OK if the set is empty.
    assert_axis_returns @olap,
      "Filter({}, 1=0)",
      ""
    assert_axis_returns @olap,
      "Filter({[Time].[Time].Children}, 1=0)",
      ""
  end

  # Java: FunctionTest#testFilterCalcSlicer
  it "Filter with calculated slicer using Aggregate" do
    assert_query_returns @olap,
      "with member [Time].[Time].[Date Range] as \n" \
      "'Aggregate({[Time].[1997].[Q1]:[Time].[1997].[Q3]})'\n" \
      "select\n" \
      "{[Measures].[Unit Sales],[Measures].[Store Cost],\n" \
      "[Measures].[Store Sales]} ON columns,\n" \
      "NON EMPTY Filter ([Store].[Store State].members,\n" \
      "[Measures].[Store Cost] > 75000) ON rows\n" \
      "from [Sales] where [Time].[Date Range]",
      <<~RESULT
        Axis #0:
        {[Time].[Date Range]}
        Axis #1:
        {[Measures].[Unit Sales]}
        {[Measures].[Store Cost]}
        {[Measures].[Store Sales]}
        Axis #2:
        {[Store].[USA].[WA]}
        Row #0: 90,131
        Row #0: 76,151.59
        Row #0: 190,776.88
      RESULT

    assert_query_returns @olap,
      "with member [Time].[Time].[Date Range] as \n" \
      "'Aggregate({[Time].[1997].[Q1]:[Time].[1997].[Q3]})'\n" \
      "select\n" \
      "{[Measures].[Unit Sales],[Measures].[Store Cost],\n" \
      "[Measures].[Store Sales]} ON columns,\n" \
      "NON EMPTY Order (Filter ([Store].[Store State].members,\n" \
      "[Measures].[Store Cost] > 100),[Measures].[Store Cost], DESC) ON rows\n" \
      "from [Sales] where [Time].[Date Range]",
      <<~RESULT
        Axis #0:
        {[Time].[Date Range]}
        Axis #1:
        {[Measures].[Unit Sales]}
        {[Measures].[Store Cost]}
        {[Measures].[Store Sales]}
        Axis #2:
        {[Store].[USA].[WA]}
        {[Store].[USA].[CA]}
        {[Store].[USA].[OR]}
        Row #0: 90,131
        Row #0: 76,151.59
        Row #0: 190,776.88
        Row #1: 53,312
        Row #1: 45,435.93
        Row #1: 113,966.00
        Row #2: 51,306
        Row #2: 43,033.82
        Row #2: 107,823.63
      RESULT
  end

  # --- Other misc (lines 12427-12760) ---

  # Java: FunctionTest#testComplexQuery
  it "complex query with Distinct, Head, Tail" do
    expected = <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Gender].[All Gender]}
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 266,773
      Row #1: 131,558
      Row #2: 135,215
    RESULT

    # hand written case
    assert_query_returns @olap,
      "select\n" \
      "   [Measures].[Unit Sales] on 0,\n" \
      "   Distinct({\n" \
      "     [Gender],\n" \
      "     Tail(\n" \
      "       Head({\n" \
      "         [Gender],\n" \
      "         [Gender].[F],\n" \
      "         [Gender].[M]},\n" \
      "         2),\n" \
      "       1),\n" \
      "     Tail(\n" \
      "       Head({\n" \
      "         [Gender],\n" \
      "         [Gender].[F],\n" \
      "         [Gender].[M]},\n" \
      "         2),\n" \
      "       1),\n" \
      "     [Gender].[M]}) on 1\n" \
      "from [Sales]",
      expected

    # generated equivalent using recursive method
    buf = "select\n   [Measures].[Unit Sales] on 0,\n"
    buf += generate_complex("   ", 0, 7, 3)
    buf += " on 1\nfrom [Sales]"
    assert_query_returns @olap, buf, expected
  end

  # Java: FunctionTest#testDateParameter
  it "Order function with Now() date expression (MONDRIAN-1050)" do
    assert_query_returns @olap,
      "SELECT" \
      " {[Measures].[Unit Sales]} ON COLUMNS," \
      " Order([Gender].Members," \
      " Now(), ASC) ON ROWS" \
      " FROM [Sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Gender].[All Gender]}
        {[Gender].[F]}
        {[Gender].[M]}
        Row #0: 266,773
        Row #1: 131,558
        Row #2: 135,215
      RESULT
  end

  # Java: FunctionTest#testHierarchizeExcept
  it "Hierarchize with Except maintains sort order (MONDRIAN-1043)" do
    expected = <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      {[Measures].[Store Sales]}
      Axis #2:
      {[Customers].[USA].[CA].[Altadena]}
      {[Customers].[USA].[CA].[Arcadia]}
      {[Customers].[USA].[CA].[Bellflower]}
      {[Customers].[USA].[CA].[Berkeley]}
      {[Customers].[USA].[CA].[Beverly Hills]}
      {[Customers].[USA].[CA].[Burbank]}
      {[Customers].[USA].[CA].[Burlingame]}
      {[Customers].[USA].[CA].[Chula Vista]}
      {[Customers].[USA].[CA].[Colma]}
      {[Customers].[USA].[CA].[Concord]}
      {[Customers].[USA].[CA].[Coronado]}
      {[Customers].[USA].[CA].[Daly City]}
      {[Customers].[USA].[CA].[Downey]}
      {[Customers].[USA].[CA].[El Cajon]}
      {[Customers].[USA].[CA].[Fremont]}
      {[Customers].[USA].[CA].[Glendale]}
      {[Customers].[USA].[CA].[Grossmont]}
      {[Customers].[USA].[CA].[Imperial Beach]}
      {[Customers].[USA].[CA].[La Jolla]}
      {[Customers].[USA].[CA].[La Mesa]}
      {[Customers].[USA].[CA].[Lakewood]}
      {[Customers].[USA].[CA].[Lemon Grove]}
      {[Customers].[USA].[CA].[Lincoln Acres]}
      {[Customers].[USA].[CA].[Long Beach]}
      {[Customers].[USA].[CA].[Los Angeles]}
      {[Customers].[USA].[CA].[Mill Valley]}
      {[Customers].[USA].[CA].[National City]}
      {[Customers].[USA].[CA].[Newport Beach]}
      {[Customers].[USA].[CA].[Novato]}
      {[Customers].[USA].[CA].[Oakland]}
      {[Customers].[USA].[CA].[Palo Alto]}
      {[Customers].[USA].[CA].[Pomona]}
      {[Customers].[USA].[CA].[Redwood City]}
      {[Customers].[USA].[CA].[Richmond]}
      {[Customers].[USA].[CA].[San Carlos]}
      {[Customers].[USA].[CA].[San Diego]}
      {[Customers].[USA].[CA].[San Francisco]}
      {[Customers].[USA].[CA].[San Gabriel]}
      {[Customers].[USA].[CA].[San Jose]}
      {[Customers].[USA].[CA].[Santa Cruz]}
      {[Customers].[USA].[CA].[Santa Monica]}
      {[Customers].[USA].[CA].[Spring Valley]}
      {[Customers].[USA].[CA].[Torrance]}
      {[Customers].[USA].[CA].[West Covina]}
      {[Customers].[USA].[CA].[Woodland Hills]}
      {[Customers].[USA].[OR]}
      {[Customers].[USA].[WA]}
      Row #0: 2,574
      Row #0: 5,585.59
      Row #1: 2,440
      Row #1: 5,136.59
      Row #2: 3,106
      Row #2: 6,633.97
      Row #3: 136
      Row #3: 320.17
      Row #4: 2,907
      Row #4: 6,194.37
      Row #5: 3,086
      Row #5: 6,577.33
      Row #6: 198
      Row #6: 407.38
      Row #7: 2,999
      Row #7: 6,284.30
      Row #8: 129
      Row #8: 287.78
      Row #9: 105
      Row #9: 219.77
      Row #10: 2,391
      Row #10: 5,051.15
      Row #11: 129
      Row #11: 271.60
      Row #12: 3,440
      Row #12: 7,367.06
      Row #13: 2,543
      Row #13: 5,460.42
      Row #14: 163
      Row #14: 350.22
      Row #15: 3,284
      Row #15: 7,082.91
      Row #16: 2,131
      Row #16: 4,458.60
      Row #17: 1,616
      Row #17: 3,409.34
      Row #18: 1,938
      Row #18: 4,081.37
      Row #19: 1,834
      Row #19: 3,908.26
      Row #20: 2,487
      Row #20: 5,174.12
      Row #21: 2,651
      Row #21: 5,636.82
      Row #22: 2,176
      Row #22: 4,691.94
      Row #23: 2,973
      Row #23: 6,422.37
      Row #24: 2,009
      Row #24: 4,312.99
      Row #25: 58
      Row #25: 109.36
      Row #26: 2,031
      Row #26: 4,237.46
      Row #27: 3,098
      Row #27: 6,696.06
      Row #28: 163
      Row #28: 335.98
      Row #29: 70
      Row #29: 145.90
      Row #30: 133
      Row #30: 272.08
      Row #31: 2,712
      Row #31: 5,595.62
      Row #32: 144
      Row #32: 312.43
      Row #33: 110
      Row #33: 212.45
      Row #34: 145
      Row #34: 289.80
      Row #35: 1,535
      Row #35: 3,348.69
      Row #36: 88
      Row #36: 195.28
      Row #37: 2,631
      Row #37: 5,663.60
      Row #38: 161
      Row #38: 343.20
      Row #39: 185
      Row #39: 367.78
      Row #40: 2,660
      Row #40: 5,739.63
      Row #41: 1,790
      Row #41: 3,862.79
      Row #42: 2,570
      Row #42: 5,405.02
      Row #43: 2,503
      Row #43: 5,302.08
      Row #44: 2,516
      Row #44: 5,406.21
      Row #45: 67,659
      Row #45: 142,277.07
      Row #46: 124,366
      Row #46: 263,793.22
    RESULT

    mdx_queries = [
      "SELECT {[Measures].[Unit Sales], [Measures].[Store Sales]} ON COLUMNS, " \
      "Hierarchize(Except({[Customers].[USA].Children, [Customers].[USA].[CA].Children}, " \
      "[Customers].[USA].[CA])) ON ROWS FROM [Sales]",
      "SELECT {[Measures].[Unit Sales], [Measures].[Store Sales]} ON COLUMNS, " \
      "Except(Hierarchize({[Customers].[USA].Children, [Customers].[USA].[CA].Children}), " \
      "[Customers].[USA].[CA]) ON ROWS FROM [Sales] "
    ]
    mdx_queries.each do |mdx|
      assert_query_returns @olap, mdx, expected
    end
  end

  # Java: FunctionTest#testMondrian_1187
  it "TOPCOUNT with DISTINCT produces same results with and without alias (MONDRIAN-1187)" do
    query_without_alias =
      "WITH\nSET [Top Count] AS\n" \
      "{\nTOPCOUNT(\nDISTINCT([Customers].[Name].Members),\n" \
      "5,\n[Measures].[Unit Sales]\n)\n}\n" \
      "SELECT\n[Top Count] * [Measures].[Unit Sales] on 0\n" \
      "FROM [Sales]\n" \
      "WHERE [Time].[1997].[Q1].[1] : [Time].[1997].[Q3].[8]"

    query_with_alias =
      "SELECT\n" \
      "TOPCOUNT( DISTINCT( [Customers].[Name].Members), 5, [Measures].[Unit Sales]) * [Measures].[Unit Sales] on 0\n" \
      "FROM [Sales]\n" \
      "WHERE [Time].[1997].[Q1].[1]:[Time].[1997].[Q3].[8]"

    result_without_alias = format_result(@olap.execute(query_without_alias))
    result_with_alias = format_result(@olap.execute(query_with_alias))
    assert_like result_without_alias, result_with_alias
  end

  private

  # Recursive routine to generate a complex MDX expression.
  # Mirrors Java's FunctionTest.generateComplex.
  def generate_complex(indent, depth, depth_limit, breadth)
    buf = "#{indent}Distinct({\n"
    buf += "#{indent}  [Gender],\n"
    breadth.times do
      if depth < depth_limit
        buf += "#{indent}  Tail(\n"
        buf += "#{indent}    Head({\n"
        buf += generate_complex("#{indent}      ", depth + 1, depth_limit, breadth)
        buf += "},\n"
        buf += "#{indent}      2),\n"
        buf += "#{indent}    1),\n"
      else
        buf += "#{indent}  [Gender].[F],\n"
      end
    end
    buf += "#{indent}  [Gender].[M]})"
    buf
  end
end
