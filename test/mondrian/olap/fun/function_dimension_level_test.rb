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
describe "FunctionDimensionLevel" do
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

  describe "Dimension and Hierarchy navigation" do
    # Java: FunctionTest#testDimensionHierarchy
    it "Dimension.Name returns dimension name" do
      assert_expression_returns @olap, "[Time].Dimension.Name", "Time"
    end

    # Java: FunctionTest#testLevelDimension
    it "Level.Dimension.UniqueName returns dimension unique name" do
      assert_expression_returns @olap, "[Time].[Year].Dimension.UniqueName", "[Time]"
    end

    # Java: FunctionTest#testMemberDimension
    it "Member.Dimension.UniqueName returns dimension unique name" do
      assert_expression_returns @olap, "[Time].[1997].[Q2].Dimension.UniqueName", "[Time]"
    end

    # Java: FunctionTest#testTime
    it "hierarchy UniqueName for Time member" do
      assert_expression_returns @olap,
        "[Time].[1997].[Q1].[1].Hierarchy.UniqueName", "[Time]"
    end

    # Java: FunctionTest#testBasic9
    it "hierarchy UniqueName for Gender member" do
      assert_expression_returns @olap,
        "[Gender].[All Gender].[F].Hierarchy.UniqueName", "[Gender]"
    end

    # Java: FunctionTest#testFirstInLevel9
    it "hierarchy UniqueName for Education Level member" do
      assert_expression_returns @olap,
        "[Education Level].[All Education Levels].[Bachelors Degree].Hierarchy.UniqueName",
        "[Education Level]"
    end

    # Java: FunctionTest#testHierarchyAll
    it "hierarchy UniqueName for All member" do
      assert_expression_returns @olap,
        "[Gender].[All Gender].Hierarchy.UniqueName", "[Gender]"
    end
  end

  describe "Dimensions function" do
    # Java: FunctionTest#testDimensionsNumeric
    it "Dimensions(n) returns dimension by ordinal" do
      # TODO: assertExprDependsOn not yet available
      assert_expression_returns @olap, "Dimensions(2).Name", "Store Size in SQFT"
      # bug 1426134 -- Dimensions(0) throws 'Index '0' out of bounds'
      assert_expression_returns @olap, "Dimensions(0).Name", "Measures"
      assert_expression_raises @olap, "Dimensions(-1).Name", "Index '-1' out of bounds"
      assert_expression_raises @olap, "Dimensions(100).Name", "Index '100' out of bounds"
      # Since Dimensions returns a Hierarchy, can apply CurrentMember.
      assert_axis_returns @olap,
        "Dimensions(3).CurrentMember",
        "[Store Type].[All Store Types]"
    end

    # Java: FunctionTest#testDimensionsString
    it "Dimensions(string) returns dimension by name" do
      # TODO: assertExprDependsOn not yet available
      assert_expression_returns @olap, "Dimensions(\"Store\").UniqueName", "[Store]"
      # Since Dimensions returns a Hierarchy, can apply Children.
      assert_axis_returns @olap,
        "Dimensions(\"Store\").Children",
        <<~EXPECTED.chomp
          [Store].[Canada]
          [Store].[Mexico]
          [Store].[USA]
        EXPECTED
    end

    # Java: FunctionTest#testDimensionsDepends
    it "Dimensions used in Crossjoin expression" do
      # TODO: assertSetExprDependsOn not yet available
      expression =
        "Crossjoin(" \
        "{Dimensions(\"Measures\").CurrentMember.Hierarchy.CurrentMember}, " \
        "{Dimensions(\"Product\")})"
      assert_axis_returns @olap,
        expression, "{[Measures].[Unit Sales], [Product].[All Products]}"
    end
  end

  describe "Null member" do
    # Java: FunctionTest#testNullMember
    it "null member properties via Parent of All member" do
      # MSAS fails here, but Mondrian doesn't.
      assert_expression_returns @olap,
        "[Gender].[All Gender].Parent.Level.UniqueName",
        "[Gender].[(All)]"

      # MSAS fails here, but Mondrian doesn't.
      assert_expression_returns @olap,
        "[Gender].[All Gender].Parent.Hierarchy.UniqueName", "[Gender]"

      # MSAS fails here, but Mondrian doesn't.
      assert_expression_returns @olap,
        "[Gender].[All Gender].Parent.Dimension.UniqueName", "[Gender]"

      # MSAS succeeds too
      assert_expression_returns @olap,
        "[Gender].[All Gender].Parent.Children.Count", "0"

      # Default NullMemberRepresentation is "#null"
      # MSAS returns "" here.
      assert_expression_returns @olap,
        "[Gender].[All Gender].Parent.UniqueName", "[Gender].[#null]"

      # MSAS returns "" here.
      assert_expression_returns @olap,
        "[Gender].[All Gender].Parent.Name", "#null"
    end
  end

  describe "Null values" do
    # Java: FunctionTest#testNullValue
    it "NULL literal generates null cell value" do
      # Testcase is from bug 1440344.
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member [Measures].[X] as 'IIF([Measures].[Store Sales]>10000,[Measures].[Store Sales],Null)'
        select
        {[Measures].[X]} on columns,
        {[Product].[Product Department].members} on rows
        from Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[X]}
        Axis #2:
        {[Product].[Drink].[Alcoholic Beverages]}
        {[Product].[Drink].[Beverages]}
        {[Product].[Drink].[Dairy]}
        {[Product].[Food].[Baked Goods]}
        {[Product].[Food].[Baking Goods]}
        {[Product].[Food].[Breakfast Foods]}
        {[Product].[Food].[Canned Foods]}
        {[Product].[Food].[Canned Products]}
        {[Product].[Food].[Dairy]}
        {[Product].[Food].[Deli]}
        {[Product].[Food].[Eggs]}
        {[Product].[Food].[Frozen Foods]}
        {[Product].[Food].[Meat]}
        {[Product].[Food].[Produce]}
        {[Product].[Food].[Seafood]}
        {[Product].[Food].[Snack Foods]}
        {[Product].[Food].[Snacks]}
        {[Product].[Food].[Starchy Foods]}
        {[Product].[Non-Consumable].[Carousel]}
        {[Product].[Non-Consumable].[Checkout]}
        {[Product].[Non-Consumable].[Health and Hygiene]}
        {[Product].[Non-Consumable].[Household]}
        {[Product].[Non-Consumable].[Periodicals]}
        Row #0: 14,029.08
        Row #1: 27,748.53
        Row #2:
        Row #3: 16,455.43
        Row #4: 38,670.41
        Row #5:
        Row #6: 39,774.34
        Row #7:
        Row #8: 30,508.85
        Row #9: 25,318.93
        Row #10:
        Row #11: 55,207.50
        Row #12:
        Row #13: 82,248.42
        Row #14:
        Row #15: 67,609.82
        Row #16: 14,550.05
        Row #17: 11,756.07
        Row #18:
        Row #19:
        Row #20: 32,571.86
        Row #21: 60,469.89
        Row #22:
      RESULT
    end

    # Java: FunctionTest#testNullInMultiplication
    it "NULL in multiplication returns empty" do
      assert_expression_returns @olap, "NULL*1", ""
      assert_expression_returns @olap, "1*NULL", ""
      assert_expression_returns @olap, "NULL*NULL", ""
    end

    # Java: FunctionTest#testNullInAddition
    it "NULL in addition returns the non-null operand" do
      assert_expression_returns @olap, "1+NULL", "1"
      assert_expression_returns @olap, "NULL+1", "1"
    end

    # Java: FunctionTest#testNullInSubtraction
    it "NULL in subtraction returns the non-null operand" do
      assert_expression_returns @olap, "1-NULL", "1"
      assert_expression_returns @olap, "NULL-1", "-1"
    end
  end

  describe "Member.Level" do
    # Java: FunctionTest#testMemberLevel
    it "returns level unique name for a member" do
      assert_expression_returns @olap,
        "[Time].[1997].[Q1].[1].Level.UniqueName",
        "[Time].[Month]"
    end
  end

  describe "Levels function" do
    # Java: FunctionTest#testLevelsNumeric
    it "Levels(n) returns level by ordinal" do
      assert_expression_returns @olap, "[Time].[Time].Levels(2).Name", "Month"
      assert_expression_returns @olap, "[Time].[Time].Levels(0).Name", "Year"
      assert_expression_returns @olap, "[Product].Levels(0).Name", "(All)"
    end

    # Java: FunctionTest#testLevelsTooSmall
    it "Levels with negative index raises error" do
      assert_expression_raises @olap,
        "[Time].[Time].Levels(-1).Name", "Index '-1' out of bounds"
    end

    # Java: FunctionTest#testLevelsTooLarge
    it "Levels with too-large index raises error" do
      assert_expression_raises @olap,
        "[Time].[Time].Levels(8).Name", "Index '8' out of bounds"
    end

    # Java: FunctionTest#testHierarchyLevelsString
    it "Hierarchy.Levels(string) returns named level" do
      assert_expression_returns @olap,
        "[Time].[Time].Levels(\"Year\").UniqueName", "[Time].[Year]"
    end

    # Java: FunctionTest#testHierarchyLevelsStringFail
    it "Hierarchy.Levels with nonexistent name raises error" do
      assert_expression_raises @olap,
        "[Time].[Time].Levels(\"nonexistent\").UniqueName",
        "Level 'nonexistent' not found in hierarchy '[Time]'"
    end

    # Java: FunctionTest#testLevelsString
    it "Levels(string) function returns named level" do
      assert_expression_returns @olap,
        "Levels(\"[Time].[Year]\").UniqueName",
        "[Time].[Year]"
    end

    # Java: FunctionTest#testLevelsStringFail
    it "Levels function with nonexistent name raises error" do
      assert_expression_raises @olap,
        "Levels(\"nonexistent\").UniqueName",
        "Level 'nonexistent' not found"
    end
  end

  describe "ValidMeasure" do
    # Java: FunctionTest#testQueryWithoutValidMeasure
    it "query without ValidMeasure returns empty on virtual cube" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
        member measures.[without VM] as ' [measures].[unit sales] '
        select {measures.[without VM] } on 0,
        [Warehouse].[Country].members on 1 from [warehouse and sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[without VM]}
        Axis #2:
        {[Warehouse].[Canada]}
        {[Warehouse].[Mexico]}
        {[Warehouse].[USA]}
        Row #0:
        Row #1:
        Row #2:
      RESULT
    end

    # Java: FunctionTest#testValidMeasure
    it "ValidMeasure returns unit sales across warehouse dimension" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
        member measures.[with VM] as 'validmeasure([measures].[unit sales])'
        select { measures.[with VM]} on 0,
        [Warehouse].[Country].members on 1 from [warehouse and sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[with VM]}
        Axis #2:
        {[Warehouse].[Canada]}
        {[Warehouse].[Mexico]}
        {[Warehouse].[USA]}
        Row #0: 266,773
        Row #1: 266,773
        Row #2: 266,773
      RESULT
    end

    # Java: FunctionTest#testValidMeasureTupleHasAnotherMember
    it "ValidMeasure tuple with another member" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
        member measures.[with VM] as 'validmeasure(([measures].[unit sales],[customers].[all customers]))'
        select { measures.[with VM]} on 0,
        [Warehouse].[Country].members on 1 from [warehouse and sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[with VM]}
        Axis #2:
        {[Warehouse].[Canada]}
        {[Warehouse].[Mexico]}
        {[Warehouse].[USA]}
        Row #0: 266,773
        Row #1: 266,773
        Row #2: 266,773
      RESULT
    end

    # Java: FunctionTest#testValidMeasureDepends
    it "ValidMeasure dependencies" do
      # TODO: assertExprDependsOn not yet available
      skip "assertExprDependsOn not yet available"
    end

    # Java: FunctionTest#testValidMeasureNonVirtualCube
    it "ValidMeasure outside virtual cube is a no-op" do
      # Verify ValidMeasure used outside of a virtual cube
      # is effectively a no-op.
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member measures.vm as 'ValidMeasure(measures.[Store Sales])'
        select measures.[vm] on 0 from Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[vm]}
        Row #0: 565,238.13
      RESULT

      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member measures.vm as 'ValidMeasure((gender.f, measures.[Store Sales]))'
        select measures.[vm] on 0 from Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[vm]}
        Row #0: 280,226.21
      RESULT
    end

    # Java: FunctionTest#testValidMeasureCalculatedMemberMeasure
    it "ValidMeasure with calculated member raises error" do
      # MONDRIAN-2109: calculated members in ValidMeasure must produce
      # a proper error message.
      error = assert_raises(Mondrian::OLAP::Error) do
        @olap.execute <<~MDX
          with member measures.calc as 'measures.[Warehouse sales]'
          member measures.vm as 'ValidMeasure(measures.calc)'
          select from [warehouse and sales]
          where (measures.vm ,gender.f)
        MDX
      end
      expected_pattern = "The function ValidMeasure cannot be used with the measure " \
                         "'[Measures].[calc]' because it is a calculated member."
      assert error.root_cause_message.include?(expected_pattern),
        "Expected root cause containing '#{expected_pattern}', got: #{error.root_cause_message}"

      # Check the working version
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
        member measures.vm as 'ValidMeasure(measures.[warehouse sales])'
        select from [warehouse and sales] where (measures.vm, gender.f)
      MDX
        Axis #0:
        {[Measures].[vm], [Gender].[F]}
        196,770.888
      RESULT
    end
  end
end
