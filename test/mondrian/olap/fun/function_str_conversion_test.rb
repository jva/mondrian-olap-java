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
describe "StrConversion" do
  before(:all) do
    create_olap_connection
  end

  # Helper: assert that evaluating an expression produces an error cell
  # whose value message contains the given pattern. Mirrors Java's
  # assertExprThrows which wraps the expression in a calculated member,
  # executes the query, and checks if the cell is an error.
  def assert_expression_raises(olap, expression, pattern)
    escaped_expression = expression.gsub("'", "''")
    mdx = "WITH MEMBER [Measures].[Foo] AS '#{escaped_expression}' " \
          "SELECT {[Measures].[Foo]} ON COLUMNS FROM [Sales]"
    begin
      result = olap.execute(mdx)
      cell_value = result.values.flatten.first
      error_message = cell_value.to_s
      assert error_message.include?(pattern),
        "Expected error containing '#{pattern}', got cell value: #{error_message}"
    rescue Mondrian::OLAP::Error, Java::OrgOlap4j::OlapException, Java::MondrianOlap::MondrianException => e
      full_message = collect_cause_messages(e)
      assert full_message.include?(pattern),
        "Expected error containing '#{pattern}', got: #{full_message}"
    end
  end

  # Walk the exception cause chain and collect all messages into one string.
  def collect_cause_messages(exception)
    messages = []
    cause = exception
    while cause
      messages << cause.message.to_s if cause.message
      next_cause = cause.respond_to?(:cause) ? cause.cause : nil
      break if next_cause.nil? || next_cause == cause
      cause = next_cause
    end
    messages.join(" | ")
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
  # includes the given pattern.
  def assert_mdx_raises(mdx, pattern)
    error = assert_raises(Mondrian::OLAP::Error) { @olap.execute(mdx) }
    assert error.root_cause_message.include?(pattern),
      "Expected root cause containing '#{pattern}', got: #{error.root_cause_message}"
  end

  describe "Item" do
    # Java: FunctionTest#testItemMember
    it "Item returns member from set by index" do
      assert_expression_returns @olap,
        "Descendants([Time].[1997], [Time].[Month]).Item(1).Item(0).UniqueName",
        "[Time].[1997].[Q1].[2]"

      # Access beyond the list yields the Null member.
      assert_expression_returns @olap,
        "[Time].[1997].Children.Item(6).UniqueName", "[Time].[#null]"
      assert_expression_returns @olap,
        "[Time].[1997].Children.Item(-1).UniqueName", "[Time].[#null]"
    end

    # Java: FunctionTest#testItemTuple
    it "Item returns member from crossjoin tuple by index" do
      assert_expression_returns @olap,
        "CrossJoin([Gender].[All Gender].children, " \
        "[Time].[1997].[Q2].children).Item(0).Item(1).UniqueName",
        "[Time].[1997].[Q2].[4]"
    end
  end

  describe "StrToMember" do
    # Java: FunctionTest#testStrToMember
    it "converts string to member" do
      assert_expression_returns @olap,
        'StrToMember("[Time].[1997].[Q2].[4]").Name',
        "4"
    end

    # Java: FunctionTest#testStrToMemberUniqueName
    it "converts unique name string to member" do
      assert_expression_returns @olap,
        'StrToMember("[Store].[USA].[CA]").Name',
        "CA"
    end

    # Java: FunctionTest#testStrToMemberFullyQualifiedName
    it "converts fully qualified name string to member" do
      assert_expression_returns @olap,
        'StrToMember("[Store].[All Stores].[USA].[CA]").Name',
        "CA"
    end

    # Java: FunctionTest#testStrToMemberNull
    it "StrToMember, StrToSet, StrToTuple with null argument throw error" do
      # SSAS 2005 gives "#Error An MDX expression was expected. An empty
      # expression was specified."
      assert_expression_raises @olap,
        'StrToMember(null).Name',
        "An MDX expression was expected. An empty expression was specified"
      assert_expression_raises @olap,
        'StrToSet(null, [Gender]).Count',
        "An MDX expression was expected. An empty expression was specified"
      assert_expression_raises @olap,
        'StrToTuple(null, [Gender]).Name',
        "An MDX expression was expected. An empty expression was specified"
    end

    # Java: FunctionTest#testStrToMemberIgnoreInvalidMembers
    # Testcase for bug MONDRIAN-560, "StrToMember function doesn't use
    # IgnoreInvalidMembers option".
    it "StrToMember with IgnoreInvalidMembers drops invalid members" do
      with_properties(IgnoreInvalidMembersDuringQuery: true) do
        # [Product].[Drugs] is invalid, becomes null member, and is dropped
        # from list
        assert_query_returns @olap, <<~MDX, <<~RESULT
          select
            {[Product].[Food],
              StrToMember("[Product].[Drugs]")} on columns,
            {[Measures].[Unit Sales]} on rows
          from [Sales]
        MDX
          Axis #0:
          {}
          Axis #1:
          {[Product].[Food]}
          Axis #2:
          {[Measures].[Unit Sales]}
          Row #0: 191,940
        RESULT

        # Hierarchy is inferred from leading edge
        assert_expression_returns @olap,
          'StrToMember("[Marital Status].[Separated]").Hierarchy.Name',
          "Marital Status"

        # Null member is returned
        assert_expression_returns @olap,
          'StrToMember("[Marital Status].[Separated]").Name',
          "#null"

        # Use longest valid prefix, so get [Time.Weekly] rather than just [Time].
        assert_expression_returns @olap,
          'StrToMember("[Time.Weekly].[1996].[Q1]").Hierarchy.UniqueName',
          "[Time.Weekly]"

        # If hierarchy is invalid, throw an error even though
        # IgnoreInvalidMembersDuringQuery is set.
        assert_expression_raises @olap,
          'StrToMember("[Unknown Hierarchy].[Invalid].[Member]").Name',
          "MDX object '[Unknown Hierarchy].[Invalid].[Member]' not found in cube 'Sales'"
        assert_expression_raises @olap,
          'StrToMember("[Unknown Hierarchy].[Invalid]").Name',
          "MDX object '[Unknown Hierarchy].[Invalid]' not found in cube 'Sales'"
        assert_expression_raises @olap,
          'StrToMember("[Unknown Hierarchy]").Name',
          "MDX object '[Unknown Hierarchy]' not found in cube 'Sales'"

        assert_axis_throws(
          'StrToMember("")',
          "MDX object '' not found in cube 'Sales'")
      end

      with_properties(IgnoreInvalidMembersDuringQuery: false) do
        assert_mdx_raises(
          "select \n" \
          "  {[Product].[Food],\n" \
          "    StrToMember(\"[Product].[Drugs]\")} on columns,\n" \
          "  {[Measures].[Unit Sales]} on rows\n" \
          "from [Sales]",
          "Member '[Product].[Drugs]' not found")
        assert_expression_raises @olap,
          'StrToMember("[Marital Status].[Separated]").Hierarchy.Name',
          "Member '[Marital Status].[Separated]' not found"
      end
    end
  end

  describe "StrToTuple" do
    # Java: FunctionTest#testStrToTuple
    it "converts string to tuple" do
      # single dimension yields member
      assert_axis_returns @olap,
        '{StrToTuple("[Time].[1997].[Q2]", [Time])}',
        "[Time].[1997].[Q2]"

      # multiple dimensions yield tuple
      assert_axis_returns @olap,
        '{StrToTuple("([Gender].[F], [Time].[1997].[Q2])", [Gender], [Time])}',
        "{[Gender].[F], [Time].[1997].[Q2]}"
    end

    # Java: FunctionTest#testStrToTupleIgnoreInvalidMembers
    it "StrToTuple with invalid member returns empty when IgnoreInvalidMembers" do
      with_properties(IgnoreInvalidMembersDuringQuery: true) do
        # If any member is invalid, the whole tuple is null.
        assert_axis_returns @olap,
          'StrToTuple("([Gender].[M], [Marital Status].[Separated])",' \
          " [Gender], [Marital Status])",
          ""
      end
    end

    # Java: FunctionTest#testStrToTupleDuHierarchiesFails
    it "StrToTuple with duplicate hierarchies fails" do
      assert_axis_throws(
        '{StrToTuple("([Gender].[F], [Time].[1997].[Q2], [Gender].[M])", [Gender], [Time], [Gender])}',
        "Tuple contains more than one member of hierarchy '[Gender]'.")
    end

    # Java: FunctionTest#testStrToTupleDupHierInSameDimensions
    it "StrToTuple with duplicate hierarchy in same dimension fails" do
      assert_axis_throws(
        '{StrToTuple(' \
        '"([Gender].[F], ' \
        '[Time].[1997].[Q2], ' \
        '[Time.Weekly].[1997].[10])",' \
        " [Gender], " \
        "[Time.Weekly]" \
        ", [Gender])}",
        "Tuple contains more than one member of hierarchy '[Gender]'.")
    end

    # Java: FunctionTest#testStrToTupleDepends
    it "StrToTuple dependency analysis" do
      # TODO: assertExprDependsOn and assertMemberExprDependsOn not yet available
      skip "assertExprDependsOn not yet available"
    end
  end

  describe "StrToSet" do
    # Java: FunctionTest#testStrToSet
    it "converts string to set" do
      assert_axis_returns @olap,
        'StrToSet(' \
        ' "{[Gender].[F], [Gender].[M]}",' \
        " [Gender])",
        "[Gender].[F]\n" \
        "[Gender].[M]"

      assert_axis_throws(
        'StrToSet(' \
        ' "{[Gender].[F], [Time].[1997]}",' \
        " [Gender])",
        "member is of wrong hierarchy")

      # whitespace ok
      assert_axis_returns @olap,
        'StrToSet(' \
        ' "  {   [Gender] .  [F]  ,[Gender].[M] }  ",' \
        " [Gender])",
        "[Gender].[F]\n" \
        "[Gender].[M]"

      # tuples
      assert_axis_returns @olap,
        'StrToSet(' \
        '"' \
        "{" \
        " ([Gender].[F], [Time].[1997].[Q2]), " \
        " ([Gender].[M], [Time].[1997])" \
        "}" \
        '",' \
        " [Gender]," \
        " [Time])",
        "{[Gender].[F], [Time].[1997].[Q2]}\n" \
        "{[Gender].[M], [Time].[1997]}"

      # matches unique name
      assert_axis_returns @olap,
        'StrToSet(' \
        '"' \
        "{" \
        " [Store].[USA].[CA], " \
        " [Store].[All Stores].[USA].OR," \
        " [Store].[All Stores]. [USA] . [WA]" \
        "}" \
        '",' \
        " [Store])",
        "[Store].[USA].[CA]\n" \
        "[Store].[USA].[OR]\n" \
        "[Store].[USA].[WA]"
    end

    # Java: FunctionTest#testStrToSetDupDimensionsFails
    it "StrToSet with duplicate dimensions fails" do
      assert_axis_throws(
        'StrToSet(' \
        '"' \
        "{" \
        " ([Gender].[F], [Time].[1997].[Q2], [Gender].[F]), " \
        " ([Gender].[M], [Time].[1997], [Gender].[F])" \
        "}" \
        '",' \
        " [Gender]," \
        " [Time]," \
        " [Gender])",
        "Tuple contains more than one member of hierarchy '[Gender]'.")
    end

    # Java: FunctionTest#testStrToSetIgnoreInvalidMembers
    it "StrToSet with IgnoreInvalidMembers drops invalid members" do
      with_properties(IgnoreInvalidMembersDuringQuery: true) do
        assert_axis_returns @olap,
          'StrToSet(' \
          '"' \
          "{" \
          " [Product].[Food]," \
          " [Product].[Food].[You wouldn''t like]," \
          " [Product].[Drink].[You would like]," \
          " [Product].[Drink].[Dairy]" \
          "}" \
          '",' \
          " [Product])",
          "[Product].[Food]\n" \
          "[Product].[Drink].[Dairy]"

        assert_axis_returns @olap,
          'StrToSet(' \
          '"' \
          "{" \
          " ([Gender].[M], [Product].[Food])," \
          " ([Gender].[F], [Product].[Food].[You wouldn''t like])," \
          " ([Gender].[M], [Product].[Drink].[You would like])," \
          " ([Gender].[F], [Product].[Drink].[Dairy])" \
          "}" \
          '",' \
          " [Gender], [Product])",
          "{[Gender].[M], [Product].[Food]}\n" \
          "{[Gender].[F], [Product].[Drink].[Dairy]}"
      end
    end
  end

  describe "SetToStr" do
    # Java: FunctionTest#testSetToStr
    it "converts set to string" do
      assert_expression_returns @olap,
        "SetToStr([Time].[Time].children)",
        "{[Time].[1997].[Q1], [Time].[1997].[Q2], [Time].[1997].[Q3], [Time].[1997].[Q4]}"

      # Now, applied to tuples
      assert_expression_returns @olap,
        "SetToStr({CrossJoin([Marital Status].children, {[Gender].[M]})})",
        "{([Marital Status].[M], [Gender].[M]), ([Marital Status].[S], [Gender].[M])}"
    end
  end

  describe "TupleToStr" do
    # Java: FunctionTest#testTupleToStr
    it "converts tuple to string" do
      # Applied to a dimension (which becomes a member)
      assert_expression_returns @olap,
        "TupleToStr([Product])",
        "[Product].[All Products]"

      # Applied to a dimension — SsasCompatibleNaming is false by default,
      # so [Time] resolves to the default hierarchy [Time].[Time] and returns its all member.
      assert_expression_returns @olap,
        "TupleToStr([Time])",
        "[Time].[1997]"

      # Applied to a hierarchy
      assert_expression_returns @olap,
        "TupleToStr([Time].[Time])",
        "[Time].[1997]"

      # Applied to a member
      assert_expression_returns @olap,
        "TupleToStr([Store].[USA].[OR])",
        "[Store].[USA].[OR]"

      # Applied to a member (extra set of parens)
      assert_expression_returns @olap,
        "TupleToStr(([Store].[USA].[OR]))",
        "[Store].[USA].[OR]"

      # Now, applied to a tuple
      assert_expression_returns @olap,
        "TupleToStr(([Marital Status], [Gender].[M]))",
        "([Marital Status].[All Marital Status], [Gender].[M])"

      # Applied to a tuple containing a null member
      assert_expression_returns @olap,
        "TupleToStr(([Marital Status], [Gender].Parent))",
        ""

      # Applied to a null member
      assert_expression_returns @olap,
        "TupleToStr([Marital Status].Parent)",
        ""
    end
  end
end
