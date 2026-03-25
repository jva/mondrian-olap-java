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
describe "Members, CurrentMember, DefaultMember and NamedSet ordinals" do
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

  # Assert that executing MDX raises an error whose root cause message
  # includes the given pattern. Mirrors Java's assertQueryThrows.
  def assert_mdx_raises(mdx, pattern)
    error = assert_raises(Mondrian::OLAP::Error) { @olap.execute(mdx) }
    assert error.root_cause_message.include?(pattern),
      "Expected root cause containing '#{pattern}', got: #{error.root_cause_message}"
  end

  describe "Members" do
    # Java: FunctionTest#testMembers
    it "returns members for level, all level, and measures dimension" do
      # <Level>.members
      assert_axis_returns @olap,
        "{[Customers].[Country].Members}",
        <<~EXPECTED.chomp
          [Customers].[Canada]
          [Customers].[Mexico]
          [Customers].[USA]
        EXPECTED

      # <Level>.members applied to 'all' level
      assert_axis_returns @olap,
        "{[Customers].[(All)].Members}",
        "[Customers].[All Customers]"

      # <Level>.members applied to measures dimension
      # Note -- no cube-level calculated members are present
      assert_axis_returns @olap,
        "{[Measures].[MeasuresLevel].Members}",
        <<~EXPECTED.chomp
          [Measures].[Unit Sales]
          [Measures].[Store Cost]
          [Measures].[Store Sales]
          [Measures].[Sales Count]
          [Measures].[Customer Count]
          [Measures].[Promotion Sales]
        EXPECTED

      # <Dimension>.members applied to Measures
      assert_axis_returns @olap,
        "{[Measures].Members}",
        <<~EXPECTED.chomp
          [Measures].[Unit Sales]
          [Measures].[Store Cost]
          [Measures].[Store Sales]
          [Measures].[Sales Count]
          [Measures].[Customer Count]
          [Measures].[Promotion Sales]
        EXPECTED

      # <Dimension>.members applied to a query with calc measures
      # Again, no calc measures are returned
      assert_query_returns @olap,
        "with member [Measures].[Xxx] AS ' [Measures].[Unit Sales] ' " \
        "select {[Measures].members} on columns from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Unit Sales]}
          {[Measures].[Store Cost]}
          {[Measures].[Store Sales]}
          {[Measures].[Sales Count]}
          {[Measures].[Customer Count]}
          {[Measures].[Promotion Sales]}
          Row #0: 266,773
          Row #0: 225,627.23
          Row #0: 565,238.13
          Row #0: 86,837
          Row #0: 5,581
          Row #0: 151,211.21
        RESULT

      # <Level>.members applied to a query with calc measures
      # Again, no calc measures are returned
      assert_query_returns @olap,
        "with member [Measures].[Xxx] AS ' [Measures].[Unit Sales] ' " \
        "select {[Measures].[Measures].members} on columns from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Unit Sales]}
          {[Measures].[Store Cost]}
          {[Measures].[Store Sales]}
          {[Measures].[Sales Count]}
          {[Measures].[Customer Count]}
          {[Measures].[Promotion Sales]}
          Row #0: 266,773
          Row #0: 225,627.23
          Row #0: 565,238.13
          Row #0: 86,837
          Row #0: 5,581
          Row #0: 151,211.21
        RESULT
    end

    # Java: FunctionTest#testHierarchyMembers
    # Java expected values use SSAS-style [Time].[Weekly] naming via upgradeActual.
    # In non-SSAS mode, Mondrian outputs [Time.Weekly] hierarchy names.
    it "returns hierarchy members for Time.Weekly" do
      assert_axis_returns @olap,
        "Head({[Time.Weekly].Members}, 10)",
        <<~EXPECTED.chomp
          [Time.Weekly].[All Time.Weeklys]
          [Time.Weekly].[1997]
          [Time.Weekly].[1997].[1]
          [Time.Weekly].[1997].[1].[15]
          [Time.Weekly].[1997].[1].[16]
          [Time.Weekly].[1997].[1].[17]
          [Time.Weekly].[1997].[1].[18]
          [Time.Weekly].[1997].[1].[19]
          [Time.Weekly].[1997].[1].[20]
          [Time.Weekly].[1997].[2]
        EXPECTED

      assert_axis_returns @olap,
        "Tail({[Time.Weekly].Members}, 5)",
        <<~EXPECTED.chomp
          [Time.Weekly].[1998].[51].[5]
          [Time.Weekly].[1998].[51].[29]
          [Time.Weekly].[1998].[51].[30]
          [Time.Weekly].[1998].[52]
          [Time.Weekly].[1998].[52].[6]
        EXPECTED
    end
  end

  describe "AllMembers" do
    # Java: FunctionTest#testAllMembers
    it "returns all members including calculated members" do
      # <Level>.allmembers
      assert_axis_returns @olap,
        "{[Customers].[Country].allmembers}",
        <<~EXPECTED.chomp
          [Customers].[Canada]
          [Customers].[Mexico]
          [Customers].[USA]
        EXPECTED

      # <Level>.allmembers applied to 'all' level
      assert_axis_returns @olap,
        "{[Customers].[(All)].allmembers}",
        "[Customers].[All Customers]"

      # <Level>.allmembers applied to measures dimension
      # Note -- cube-level calculated members ARE present
      assert_axis_returns @olap,
        "{[Measures].[MeasuresLevel].allmembers}",
        <<~EXPECTED.chomp
          [Measures].[Unit Sales]
          [Measures].[Store Cost]
          [Measures].[Store Sales]
          [Measures].[Sales Count]
          [Measures].[Customer Count]
          [Measures].[Promotion Sales]
          [Measures].[Profit]
          [Measures].[Profit Growth]
          [Measures].[Profit last Period]
        EXPECTED

      # <Dimension>.allmembers applied to Measures
      assert_axis_returns @olap,
        "{[Measures].allmembers}",
        <<~EXPECTED.chomp
          [Measures].[Unit Sales]
          [Measures].[Store Cost]
          [Measures].[Store Sales]
          [Measures].[Sales Count]
          [Measures].[Customer Count]
          [Measures].[Promotion Sales]
          [Measures].[Profit]
          [Measures].[Profit Growth]
          [Measures].[Profit last Period]
        EXPECTED

      # <Dimension>.allmembers applied to a query with calc measures
      # Calc measures are returned
      assert_query_returns @olap,
        "with member [Measures].[Xxx] AS ' [Measures].[Unit Sales] ' " \
        "select {[Measures].allmembers} on columns from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Unit Sales]}
          {[Measures].[Store Cost]}
          {[Measures].[Store Sales]}
          {[Measures].[Sales Count]}
          {[Measures].[Customer Count]}
          {[Measures].[Promotion Sales]}
          {[Measures].[Profit]}
          {[Measures].[Profit Growth]}
          {[Measures].[Profit last Period]}
          {[Measures].[Xxx]}
          Row #0: 266,773
          Row #0: 225,627.23
          Row #0: 565,238.13
          Row #0: 86,837
          Row #0: 5,581
          Row #0: 151,211.21
          Row #0: $339,610.90
          Row #0: 0.0%
          Row #0: $339,610.90
          Row #0: 266,773
        RESULT

      # Calc measure members from schema and from query
      assert_query_returns @olap,
        "WITH MEMBER [Measures].[Unit to Sales ratio] as " \
        "'[Measures].[Unit Sales] / [Measures].[Store Sales]', FORMAT_STRING='0.0%' " \
        "SELECT {[Measures].AllMembers} ON COLUMNS," \
        "non empty({[Store].[Store State].Members}) ON ROWS " \
        "FROM Sales " \
        "WHERE ([1997].[Q1])",
        <<~RESULT
          Axis #0:
          {[Time].[1997].[Q1]}
          Axis #1:
          {[Measures].[Unit Sales]}
          {[Measures].[Store Cost]}
          {[Measures].[Store Sales]}
          {[Measures].[Sales Count]}
          {[Measures].[Customer Count]}
          {[Measures].[Promotion Sales]}
          {[Measures].[Profit]}
          {[Measures].[Profit Growth]}
          {[Measures].[Profit last Period]}
          {[Measures].[Unit to Sales ratio]}
          Axis #2:
          {[Store].[USA].[CA]}
          {[Store].[USA].[OR]}
          {[Store].[USA].[WA]}
          Row #0: 16,890
          Row #0: 14,431.09
          Row #0: 36,175.20
          Row #0: 5,498
          Row #0: 1,110
          Row #0: 14,447.16
          Row #0: $21,744.11
          Row #0: 0.0%
          Row #0: $21,744.11
          Row #0: 46.7%
          Row #1: 19,287
          Row #1: 16,081.07
          Row #1: 40,170.29
          Row #1: 6,184
          Row #1: 767
          Row #1: 10,829.64
          Row #1: $24,089.22
          Row #1: 0.0%
          Row #1: $24,089.22
          Row #1: 48.0%
          Row #2: 30,114
          Row #2: 25,240.08
          Row #2: 63,282.86
          Row #2: 9,906
          Row #2: 1,104
          Row #2: 18,459.60
          Row #2: $38,042.78
          Row #2: 0.0%
          Row #2: $38,042.78
          Row #2: 47.6%
        RESULT

      # Calc member in query and schema not seen via AllMembers
      assert_query_returns @olap,
        "WITH MEMBER [Measures].[Unit to Sales ratio] as '[Measures].[Unit Sales] / [Measures].[Store Sales]', " \
        "FORMAT_STRING='0.0%' " \
        "SELECT {[Measures].AllMembers} ON COLUMNS," \
        "non empty({[Store].[Store State].Members}) ON ROWS " \
        "FROM Sales " \
        "WHERE ([1997].[Q1])",
        <<~RESULT
          Axis #0:
          {[Time].[1997].[Q1]}
          Axis #1:
          {[Measures].[Unit Sales]}
          {[Measures].[Store Cost]}
          {[Measures].[Store Sales]}
          {[Measures].[Sales Count]}
          {[Measures].[Customer Count]}
          {[Measures].[Promotion Sales]}
          {[Measures].[Profit]}
          {[Measures].[Profit Growth]}
          {[Measures].[Profit last Period]}
          {[Measures].[Unit to Sales ratio]}
          Axis #2:
          {[Store].[USA].[CA]}
          {[Store].[USA].[OR]}
          {[Store].[USA].[WA]}
          Row #0: 16,890
          Row #0: 14,431.09
          Row #0: 36,175.20
          Row #0: 5,498
          Row #0: 1,110
          Row #0: 14,447.16
          Row #0: $21,744.11
          Row #0: 0.0%
          Row #0: $21,744.11
          Row #0: 46.7%
          Row #1: 19,287
          Row #1: 16,081.07
          Row #1: 40,170.29
          Row #1: 6,184
          Row #1: 767
          Row #1: 10,829.64
          Row #1: $24,089.22
          Row #1: 0.0%
          Row #1: $24,089.22
          Row #1: 48.0%
          Row #2: 30,114
          Row #2: 25,240.08
          Row #2: 63,282.86
          Row #2: 9,906
          Row #2: 1,104
          Row #2: 18,459.60
          Row #2: $38,042.78
          Row #2: 0.0%
          Row #2: $38,042.78
          Row #2: 47.6%
        RESULT

      # Calc member in query not seen via .Members
      assert_query_returns @olap,
        "WITH MEMBER [Measures].[Unit to Sales ratio] as '[Measures].[Unit Sales] / [Measures].[Store Sales]', " \
        "FORMAT_STRING='0.0%' " \
        "SELECT {[Measures].Members} ON COLUMNS," \
        "non empty({[Store].[Store State].Members}) ON ROWS " \
        "FROM Sales " \
        "WHERE ([1997].[Q1])",
        <<~RESULT
          Axis #0:
          {[Time].[1997].[Q1]}
          Axis #1:
          {[Measures].[Unit Sales]}
          {[Measures].[Store Cost]}
          {[Measures].[Store Sales]}
          {[Measures].[Sales Count]}
          {[Measures].[Customer Count]}
          {[Measures].[Promotion Sales]}
          Axis #2:
          {[Store].[USA].[CA]}
          {[Store].[USA].[OR]}
          {[Store].[USA].[WA]}
          Row #0: 16,890
          Row #0: 14,431.09
          Row #0: 36,175.20
          Row #0: 5,498
          Row #0: 1,110
          Row #0: 14,447.16
          Row #1: 19,287
          Row #1: 16,081.07
          Row #1: 40,170.29
          Row #1: 6,184
          Row #1: 767
          Row #1: 10,829.64
          Row #2: 30,114
          Row #2: 25,240.08
          Row #2: 63,282.86
          Row #2: 9,906
          Row #2: 1,104
          Row #2: 18,459.60
        RESULT

      # Calc member in dimension based on level
      assert_query_returns @olap,
        "WITH MEMBER [Store].[USA].[CA plus OR] AS 'AGGREGATE({[Store].[USA].[CA], [Store].[USA].[OR]})' " \
        "SELECT {[Measures].[Unit Sales], [Measures].[Store Sales]} ON COLUMNS," \
        "non empty({[Store].[Store State].AllMembers}) ON ROWS " \
        "FROM Sales " \
        "WHERE ([1997].[Q1])",
        <<~RESULT
          Axis #0:
          {[Time].[1997].[Q1]}
          Axis #1:
          {[Measures].[Unit Sales]}
          {[Measures].[Store Sales]}
          Axis #2:
          {[Store].[USA].[CA]}
          {[Store].[USA].[OR]}
          {[Store].[USA].[WA]}
          {[Store].[USA].[CA plus OR]}
          Row #0: 16,890
          Row #0: 36,175.20
          Row #1: 19,287
          Row #1: 40,170.29
          Row #2: 30,114
          Row #2: 63,282.86
          Row #3: 36,177
          Row #3: 76,345.49
        RESULT

      # Calc member in dimension based on level not seen
      assert_query_returns @olap,
        "WITH MEMBER [Store].[USA].[CA plus OR] AS 'AGGREGATE({[Store].[USA].[CA], [Store].[USA].[OR]})' " \
        "SELECT {[Measures].[Unit Sales], [Measures].[Store Sales]} ON COLUMNS," \
        "non empty({[Store].[Store Country].AllMembers}) ON ROWS " \
        "FROM Sales " \
        "WHERE ([1997].[Q1])",
        <<~RESULT
          Axis #0:
          {[Time].[1997].[Q1]}
          Axis #1:
          {[Measures].[Unit Sales]}
          {[Measures].[Store Sales]}
          Axis #2:
          {[Store].[USA]}
          Row #0: 66,291
          Row #0: 139,628.35
        RESULT
    end
  end

  describe "AddCalculatedMembers" do
    # Java: FunctionTest#testAddCalculatedMembers
    it "includes calculated members from dimension and measures" do
      # Calc member in dimension based on level included
      assert_query_returns @olap,
        "WITH MEMBER [Store].[USA].[CA plus OR] AS 'AGGREGATE({[Store].[USA].[CA], [Store].[USA].[OR]})' " \
        "SELECT {[Measures].[Unit Sales], [Measures].[Store Sales]} ON COLUMNS," \
        "AddCalculatedMembers([Store].[USA].Children) ON ROWS " \
        "FROM Sales " \
        "WHERE ([1997].[Q1])",
        <<~RESULT
          Axis #0:
          {[Time].[1997].[Q1]}
          Axis #1:
          {[Measures].[Unit Sales]}
          {[Measures].[Store Sales]}
          Axis #2:
          {[Store].[USA].[CA]}
          {[Store].[USA].[OR]}
          {[Store].[USA].[WA]}
          {[Store].[USA].[CA plus OR]}
          Row #0: 16,890
          Row #0: 36,175.20
          Row #1: 19,287
          Row #1: 40,170.29
          Row #2: 30,114
          Row #2: 63,282.86
          Row #3: 36,177
          Row #3: 76,345.49
        RESULT

      # Calc member in dimension based on level included
      # Calc members in measures in schema included
      assert_query_returns @olap,
        "WITH MEMBER [Store].[USA].[CA plus OR] AS 'AGGREGATE({[Store].[USA].[CA], [Store].[USA].[OR]})' " \
        "SELECT AddCalculatedMembers({[Measures].[Unit Sales], [Measures].[Store Sales]}) ON COLUMNS," \
        "AddCalculatedMembers([Store].[USA].Children) ON ROWS " \
        "FROM Sales " \
        "WHERE ([1997].[Q1])",
        <<~RESULT
          Axis #0:
          {[Time].[1997].[Q1]}
          Axis #1:
          {[Measures].[Unit Sales]}
          {[Measures].[Store Sales]}
          {[Measures].[Profit]}
          {[Measures].[Profit last Period]}
          {[Measures].[Profit Growth]}
          Axis #2:
          {[Store].[USA].[CA]}
          {[Store].[USA].[OR]}
          {[Store].[USA].[WA]}
          {[Store].[USA].[CA plus OR]}
          Row #0: 16,890
          Row #0: 36,175.20
          Row #0: $21,744.11
          Row #0: $21,744.11
          Row #0: 0.0%
          Row #1: 19,287
          Row #1: 40,170.29
          Row #1: $24,089.22
          Row #1: $24,089.22
          Row #1: 0.0%
          Row #2: 30,114
          Row #2: 63,282.86
          Row #2: $38,042.78
          Row #2: $38,042.78
          Row #2: 0.0%
          Row #3: 36,177
          Row #3: 76,345.49
          Row #3: $45,833.33
          Row #3: $45,833.33
          Row #3: 0.0%
        RESULT

      # Two dimensions
      assert_query_returns @olap,
        "SELECT AddCalculatedMembers({[Measures].[Unit Sales], [Measures].[Store Sales]}) ON COLUMNS," \
        "{([Store].[USA].[CA], [Gender].[F])} ON ROWS " \
        "FROM Sales " \
        "WHERE ([1997].[Q1])",
        <<~RESULT
          Axis #0:
          {[Time].[1997].[Q1]}
          Axis #1:
          {[Measures].[Unit Sales]}
          {[Measures].[Store Sales]}
          {[Measures].[Profit]}
          {[Measures].[Profit last Period]}
          {[Measures].[Profit Growth]}
          Axis #2:
          {[Store].[USA].[CA], [Gender].[F]}
          Row #0: 8,218
          Row #0: 17,928.37
          Row #0: $10,771.98
          Row #0: $10,771.98
          Row #0: 0.0%
        RESULT

      # Should throw more than one dimension error
      assert_axis_throws(
        "AddCalculatedMembers({([Store].[USA].[CA], [Gender].[F])})",
        "Only single dimension members allowed in set for AddCalculatedMembers")
    end
  end

  describe "StripCalculatedMembers" do
    # Java: FunctionTest#testStripCalculatedMembers
    it "strips calculated members from a set" do
      assert_axis_returns @olap,
        "StripCalculatedMembers({[Measures].AllMembers})",
        <<~EXPECTED.chomp
          [Measures].[Unit Sales]
          [Measures].[Store Cost]
          [Measures].[Store Sales]
          [Measures].[Sales Count]
          [Measures].[Customer Count]
          [Measures].[Promotion Sales]
        EXPECTED

      # applied to empty set
      assert_axis_returns @olap,
        "StripCalculatedMembers({[Gender].Parent})",
        ""

      # Calc members in dimension based on level stripped
      # Actual members in measures left alone
      assert_query_returns @olap,
        "WITH MEMBER [Store].[USA].[CA plus OR] AS " \
        "'AGGREGATE({[Store].[USA].[CA], [Store].[USA].[OR]})' " \
        "SELECT StripCalculatedMembers({[Measures].[Unit Sales], " \
        "[Measures].[Store Sales]}) ON COLUMNS," \
        "StripCalculatedMembers(" \
        "AddCalculatedMembers([Store].[USA].Children)) ON ROWS " \
        "FROM Sales " \
        "WHERE ([1997].[Q1])",
        <<~RESULT
          Axis #0:
          {[Time].[1997].[Q1]}
          Axis #1:
          {[Measures].[Unit Sales]}
          {[Measures].[Store Sales]}
          Axis #2:
          {[Store].[USA].[CA]}
          {[Store].[USA].[OR]}
          {[Store].[USA].[WA]}
          Row #0: 16,890
          Row #0: 36,175.20
          Row #1: 19,287
          Row #1: 40,170.29
          Row #2: 30,114
          Row #2: 63,282.86
        RESULT
    end
  end

  describe "CurrentMember" do
    # Java: FunctionTest#testCurrentMember
    it "returns current member for dimension, hierarchy, and level" do
      # <Dimension>.CurrentMember
      assert_axis_returns @olap, "[Gender].CurrentMember", "[Gender].[All Gender]"

      # <Hierarchy>.CurrentMember
      assert_axis_returns @olap, "[Gender].Hierarchy.CurrentMember", "[Gender].[All Gender]"

      # <Level>.CurrentMember
      # MSAS doesn't allow this, but Mondrian does: it implicitly casts
      # level to hierarchy.
      assert_axis_returns @olap, "[Store Name].CurrentMember", "[Store].[All Stores]"
    end

    # Java: FunctionTest#testCurrentMemberDepends
    # TODO: dependency tests require assertMemberExprDependsOn / assertExprDependsOn
    # which are not available in the JRuby test helpers.
    it "depends on correct hierarchies" do
      skip "Dependency assertion helpers not available in JRuby tests"
    end

    # Java: FunctionTest#testCurrentMemberFromSlicer
    it "returns current member set in the slicer" do
      result = @olap.execute(
        "with member [Measures].[Foo] as '[Gender].CurrentMember.Name'\n" \
        "select {[Measures].[Foo]} on columns\n" \
        "from Sales where ([Gender].[F])")
      cell_value = result.raw_cell_set.getCell(
        java.util.Arrays.asList(java.lang.Integer.new(0))).getValue
      assert_equal "F", cell_value
    end

    # Java: FunctionTest#testCurrentMemberFromDefaultMember
    it "returns current member from the default member" do
      result = @olap.execute(
        "with member [Measures].[Foo] as '[Time].[Time].CurrentMember.Name'\n" \
        "select {[Measures].[Foo]} on columns\n" \
        "from Sales")
      cell_value = result.raw_cell_set.getCell(
        java.util.Arrays.asList(java.lang.Integer.new(0))).getValue
      assert_equal "1997", cell_value
    end

    # Java: FunctionTest#testCurrentMemberMultiHierarchy
    it "distinguishes between hierarchies in multi-hierarchy dimension" do
      # SsasCompatibleNaming is false by default, so hierarchy name is "Time.Weekly"
      hierarchy_name = "Time.Weekly"
      query_string =
        "with member [Measures].[Foo] as\n" \
        " 'IIf(([Time].[Time].CurrentMember.Hierarchy.Name = \"" +
        hierarchy_name +
        "\"), \n" \
        "[Measures].[Unit Sales], \n" \
        "- [Measures].[Unit Sales])'\n" \
        "select {[Measures].[Unit Sales], [Measures].[Foo]} ON COLUMNS,\n" \
        "  {[Product].[Food].[Dairy]} ON ROWS\n" \
        "from [Sales]"

      # Time hierarchy context via slicer
      result = @olap.execute(query_string + " where [Time].[1997]")
      cell_value = result.raw_cell_set.getCell(
        java.util.Arrays.asList(java.lang.Integer.new(1), java.lang.Integer.new(0))).getFormattedValue
      assert_equal "-12,885", cell_value

      # As above, but context provided on rows axis as opposed to slicer
      query_string_1 =
        "with member [Measures].[Foo] as\n" \
        " 'IIf(([Time].[Time].CurrentMember.Hierarchy.Name = \"" +
        hierarchy_name +
        "\"), \n" \
        "[Measures].[Unit Sales], \n" \
        "- [Measures].[Unit Sales])'\n" \
        "select {[Measures].[Unit Sales], [Measures].[Foo]} ON COLUMNS,"

      query_string_2 =
        "from [Sales]\n" \
        "  where [Product].[Food].[Dairy] "

      result = @olap.execute(query_string_1 + " {[Time].[1997]} ON ROWS " + query_string_2)
      cell_value = result.raw_cell_set.getCell(
        java.util.Arrays.asList(java.lang.Integer.new(1), java.lang.Integer.new(0))).getFormattedValue
      assert_equal "-12,885", cell_value

      # Weekly hierarchy context via slicer
      result = @olap.execute(query_string + " where [Time.Weekly].[1997]")
      cell_value = result.raw_cell_set.getCell(
        java.util.Arrays.asList(java.lang.Integer.new(1), java.lang.Integer.new(0))).getFormattedValue
      assert_equal "-12,885", cell_value

      # Weekly hierarchy context via rows axis
      result = @olap.execute(query_string_1 + " {[Time.Weekly].[1997]} ON ROWS " + query_string_2)
      cell_value = result.raw_cell_set.getCell(
        java.util.Arrays.asList(java.lang.Integer.new(1), java.lang.Integer.new(0))).getFormattedValue
      assert_equal "-12,885", cell_value
    end

    # Java: FunctionTest#testCurrentMemberFromAxis
    it "returns current member from axis context" do
      result = @olap.execute(
        "with member [Measures].[Foo] as " \
        "'[Gender].CurrentMember.Name || [Marital Status].CurrentMember.Name'\n" \
        "select {[Measures].[Foo]} on columns,\n" \
        " CrossJoin({[Gender].children}, {[Marital Status].children}) on rows\n" \
        "from Sales")
      cell_value = result.raw_cell_set.getCell(
        java.util.Arrays.asList(java.lang.Integer.new(0), java.lang.Integer.new(0))).getValue
      assert_equal "FM", cell_value
    end

    # Java: FunctionTest#testCurrentMemberInCalcMember
    # When evaluating a calculated member, MSOLAP regards that calculated
    # member as the current member of that dimension, so it cycles in this case.
    # But Mondrian uses the previous current member, before the calculated
    # member was expanded.
    it "returns previous current member inside calculated member" do
      result = @olap.execute(
        "with member [Measures].[Foo] as '[Measures].CurrentMember.Name'\n" \
        "select {[Measures].[Foo]} on columns\n" \
        "from Sales")
      cell_value = result.raw_cell_set.getCell(
        java.util.Arrays.asList(java.lang.Integer.new(0))).getValue
      assert_equal "Unit Sales", cell_value
    end
  end

  describe "DefaultMember" do
    # Java: FunctionTest#testDefaultMember
    it "returns default member for hierarchies with and without all member" do
      # [Time] has no default member and no all, so the default member is
      # the first member of the first level.
      result = @olap.execute(
        "select {[Time].[Time].DefaultMember} on columns\n" \
        "from Sales")
      member = result.raw_cell_set.getAxes.get(0).getPositions.get(0).getMembers.get(0)
      assert_equal "1997", member.getName

      # [Time].[Weekly] has an all member and no explicit default.
      # In non-SSAS mode, the all member name is "All Time.Weeklys"
      result = @olap.execute(
        "select {[Time.Weekly].DefaultMember} on columns\n" \
        "from Sales")
      member = result.raw_cell_set.getAxes.get(0).getPositions.get(0).getMembers.get(0)
      assert_equal "All Time.Weeklys", member.getName

      # Schema with explicit defaultMember on a hierarchy
      # In non-SSAS mode, the member unique name uses [Time2.Weekly]
      member_uname = "[Time2.Weekly].[1997].[23]"
      dimension_xml = <<~XML
        <Dimension name="Time2" type="TimeDimension" foreignKey="time_id">
          <Hierarchy hasAll="false" primaryKey="time_id">
            <Table name="time_by_day"/>
            <Level name="Year" column="the_year" type="Numeric" uniqueMembers="true"
                levelType="TimeYears"/>
            <Level name="Quarter" column="quarter" uniqueMembers="false"
                levelType="TimeQuarters"/>
            <Level name="Month" column="month_of_year" uniqueMembers="false" type="Numeric"
                levelType="TimeMonths"/>
          </Hierarchy>
          <Hierarchy hasAll="true" name="Weekly" primaryKey="time_id"
                defaultMember="#{member_uname}">
            <Table name="time_by_day"/>
            <Level name="Year" column="the_year" type="Numeric" uniqueMembers="true"
                levelType="TimeYears"/>
            <Level name="Week" column="week_of_year" type="Numeric" uniqueMembers="false"
                levelType="TimeWeeks"/>
            <Level name="Day" column="day_of_month" uniqueMembers="false" type="Numeric"
                levelType="TimeDays"/>
          </Hierarchy>
        </Dimension>
      XML

      olap = connection_with_modified_cube("Sales", dimensions: dimension_xml)
      begin
        # In this variant of the schema, Time2.Weekly has an explicit default member.
        result = olap.execute(
          "select {[Time2.Weekly].DefaultMember} on columns\n" \
          "from Sales")
        member = result.raw_cell_set.getAxes.get(0).getPositions.get(0).getMembers.get(0)
        assert_equal "23", member.getName
      ensure
        olap.close
      end
    end

    # Java: FunctionTest#testDimensionDefaultMember
    it "returns default member for Measures dimension" do
      result = @olap.execute(
        "SELECT {[Measures].DefaultMember} ON COLUMNS FROM [Sales]")
      member = result.raw_cell_set.getAxes.get(0).getPositions.get(0).getMembers.get(0)
      assert_equal "Unit Sales", member.getName
    end
  end

  describe "NamedSet ordinals" do
    # Java: FunctionTest#testNamedSetCurrentOrdinalWithOrder
    it "CurrentOrdinal works with Order function" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with set [Time Regular] as [Time].[Time].Members
         set [Time Reversed] as Order([Time Regular], [Time Regular].CurrentOrdinal, BDESC)
        select [Time Reversed] on 0
        from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Time].[1998].[Q4].[12]}
        {[Time].[1998].[Q4].[11]}
        {[Time].[1998].[Q4].[10]}
        {[Time].[1998].[Q4]}
        {[Time].[1998].[Q3].[9]}
        {[Time].[1998].[Q3].[8]}
        {[Time].[1998].[Q3].[7]}
        {[Time].[1998].[Q3]}
        {[Time].[1998].[Q2].[6]}
        {[Time].[1998].[Q2].[5]}
        {[Time].[1998].[Q2].[4]}
        {[Time].[1998].[Q2]}
        {[Time].[1998].[Q1].[3]}
        {[Time].[1998].[Q1].[2]}
        {[Time].[1998].[Q1].[1]}
        {[Time].[1998].[Q1]}
        {[Time].[1998]}
        {[Time].[1997].[Q4].[12]}
        {[Time].[1997].[Q4].[11]}
        {[Time].[1997].[Q4].[10]}
        {[Time].[1997].[Q4]}
        {[Time].[1997].[Q3].[9]}
        {[Time].[1997].[Q3].[8]}
        {[Time].[1997].[Q3].[7]}
        {[Time].[1997].[Q3]}
        {[Time].[1997].[Q2].[6]}
        {[Time].[1997].[Q2].[5]}
        {[Time].[1997].[Q2].[4]}
        {[Time].[1997].[Q2]}
        {[Time].[1997].[Q1].[3]}
        {[Time].[1997].[Q1].[2]}
        {[Time].[1997].[Q1].[1]}
        {[Time].[1997].[Q1]}
        {[Time].[1997]}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: 26,796
        Row #0: 25,270
        Row #0: 19,958
        Row #0: 72,024
        Row #0: 20,388
        Row #0: 21,697
        Row #0: 23,763
        Row #0: 65,848
        Row #0: 21,350
        Row #0: 21,081
        Row #0: 20,179
        Row #0: 62,610
        Row #0: 23,706
        Row #0: 20,957
        Row #0: 21,628
        Row #0: 66,291
        Row #0: 266,773
      RESULT
    end

    # Java: FunctionTest#testNamedSetCurrentOrdinalWithGenerate
    it "CurrentOrdinal works with Generate function" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with set [Time Regular] as [Time].[Time].Members
        set [Every Other Time] as
          Generate(
            [Time Regular],
            {[Time].[Time].Members.Item(
              [Time Regular].CurrentOrdinal * 2)})
        select [Every Other Time] on 0
        from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Time].[1997]}
        {[Time].[1997].[Q1].[1]}
        {[Time].[1997].[Q1].[3]}
        {[Time].[1997].[Q2].[4]}
        {[Time].[1997].[Q2].[6]}
        {[Time].[1997].[Q3].[7]}
        {[Time].[1997].[Q3].[9]}
        {[Time].[1997].[Q4].[10]}
        {[Time].[1997].[Q4].[12]}
        {[Time].[1998].[Q1]}
        {[Time].[1998].[Q1].[2]}
        {[Time].[1998].[Q2]}
        {[Time].[1998].[Q2].[5]}
        {[Time].[1998].[Q3]}
        {[Time].[1998].[Q3].[8]}
        {[Time].[1998].[Q4]}
        {[Time].[1998].[Q4].[11]}
        Row #0: 266,773
        Row #0: 21,628
        Row #0: 23,706
        Row #0: 20,179
        Row #0: 21,350
        Row #0: 23,763
        Row #0: 20,388
        Row #0: 19,958
        Row #0: 26,796
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
        Row #0: #{' '}
      RESULT
    end

    # Java: FunctionTest#testNamedSetCurrentOrdinalWithFilter
    it "CurrentOrdinal works with Filter function" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with set [Time Regular] as [Time].[Time].Members
         set [Time Subset] as Filter([Time Regular], [Time Regular].CurrentOrdinal = 3 or [Time Regular].CurrentOrdinal = 5)
        select [Time Subset] on 0
        from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Time].[1997].[Q1].[2]}
        {[Time].[1997].[Q2]}
        Row #0: 20,957
        Row #0: 62,610
      RESULT
    end

    # Java: FunctionTest#testNamedSetCurrentOrdinalWithCrossjoin
    # TODO: empty test in Java source
    it "CurrentOrdinal with Crossjoin" do
      skip "Empty test in Java source (TODO)"
    end

    # Java: FunctionTest#testNamedSetCurrentOrdinalWithNonNamedSetFails
    it "CurrentOrdinal fails on non-named set expressions" do
      # a named set wrapped in {...} is not a named set, so CurrentOrdinal fails
      assert_mdx_raises(
        "with set [Time Members] as [Time].Members\n" \
        "member [Measures].[Foo] as ' {[Time Members]}.CurrentOrdinal '\n" \
        "select {[Measures].[Unit Sales], [Measures].[Foo]} on 0,\n" \
        " {[Product].Children} on 1\n" \
        "from [Sales]",
        "Not a named set")

      # as above for Current function
      assert_mdx_raises(
        "with set [Time Members] as [Time].Members\n" \
        "member [Measures].[Foo] as ' {[Time Members]}.Current.Name '\n" \
        "select {[Measures].[Unit Sales], [Measures].[Foo]} on 0,\n" \
        " {[Product].Children} on 1\n" \
        "from [Sales]",
        "Not a named set")

      # a set expression is not a named set, so CurrentOrdinal fails
      assert_mdx_raises(
        "with member [Measures].[Foo] as\n" \
        " ' Head([Time].Members, 5).CurrentOrdinal '\n" \
        "select {[Measures].[Unit Sales], [Measures].[Foo]} on 0,\n" \
        " {[Product].Children} on 1\n" \
        "from [Sales]",
        "Not a named set")

      # as above for Current function
      assert_mdx_raises(
        "with member [Measures].[Foo] as\n" \
        " ' Crossjoin([Time].Members, [Gender].Members).Current.Name '\n" \
        "select {[Measures].[Unit Sales], [Measures].[Foo]} on 0,\n" \
        " {[Product].Children} on 1\n" \
        "from [Sales]",
        "Not a named set")
    end
  end
end
