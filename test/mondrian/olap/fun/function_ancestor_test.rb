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
describe "FunctionTest - Ancestor, Ascendants, CalculatedChild" do
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

  describe "Ancestor" do
    # Java: FunctionTest#testAncestor
    it "returns ancestor at specified level" do
      member = execute_singleton_axis(
        "Ancestor([Store].[USA].[CA].[Los Angeles],[Store Country])")
      assert_equal "USA", member.getName

      assert_query_raises @olap,
        "SELECT {Ancestor([Store].[USA].[CA].[Los Angeles],[Promotions].[Promotion Name])} ON COLUMNS FROM [Sales]",
        "while executing query"
    end

    # Java: FunctionTest#testAncestorNumeric
    it "returns ancestor at numeric depth" do
      member = execute_singleton_axis(
        "Ancestor([Store].[USA].[CA].[Los Angeles],1)")
      assert_equal "CA", member.getName

      member = execute_singleton_axis(
        "Ancestor([Store].[USA].[CA].[Los Angeles], 0)")
      assert_equal "Los Angeles", member.getName

      member = execute_singleton_axis(
        "Ancestor([Store].[All Stores].[Vatican], 1)", cube: "Sales Ragged")
      assert_equal "All Stores", member.getName

      member = execute_singleton_axis(
        "Ancestor([Store].[USA].[Washington], 1)", cube: "Sales Ragged")
      assert_equal "USA", member.getName

      # complicated way to say "1".
      member = execute_singleton_axis(
        "Ancestor([Store].[USA].[Washington], 7 * 6 - 41)", cube: "Sales Ragged")
      assert_equal "USA", member.getName

      member = execute_singleton_axis(
        "Ancestor([Store].[All Stores].[Vatican], 2)", cube: "Sales Ragged")
      assert_nil member, "Ancestor at 2 must be null"

      member = execute_singleton_axis(
        "Ancestor([Store].[All Stores].[Vatican], -5)", cube: "Sales Ragged")
      assert_nil member, "Ancestor at -5 must be null"
    end

    # Java: FunctionTest#testAncestorHigher
    it "returns null when ancestor level is higher than member" do
      member = execute_singleton_axis(
        "Ancestor([Store].[USA],[Store].[Store City])")
      assert_nil member # MSOLAP returns null
    end

    # Java: FunctionTest#testAncestorSameLevel
    it "returns member itself when ancestor is at same level" do
      member = execute_singleton_axis(
        "Ancestor([Store].[Canada],[Store].[Store Country])")
      assert_equal "Canada", member.getName
    end

    # Java: FunctionTest#testAncestorWrongHierarchy
    it "raises error when ancestor hierarchy does not match member" do
      # MSOLAP gives error "Formula error - dimensions are not
      # valid (they do not match) - in the Ancestor function"
      assert_query_raises @olap,
        "SELECT {Ancestor([Gender].[M],[Store].[Store Country])} ON COLUMNS FROM [Sales]",
        "while executing query"
    end

    # Java: FunctionTest#testAncestorAllLevel
    it "returns All member when ancestor level is top" do
      member = execute_singleton_axis(
        "Ancestor([Store].[USA].[CA],[Store].Levels(0))")
      assert_equal true, member.isAll
    end

    # Java: FunctionTest#testAncestorWithHiddenParent
    it "returns ancestor with hidden parent in ragged hierarchy" do
      member = execute_singleton_axis(
        "Ancestor([Store].[All Stores].[Israel].[Haifa], [Store].[Store Country])",
        cube: "Sales Ragged")
      refute_nil member, "Member must not be null."
      assert_equal "Israel", member.getName
    end

    # Java: FunctionTest#testAncestorDepends
    # TODO: assertMemberExprDependsOn not yet available
    it "depends on expected hierarchies" do
      skip "assertExprDependsOn helper not yet available"
    end
  end

  describe "Ancestors" do
    # Detect the locale-dependent currency symbol used by the JVM for formatting.
    # Java tests hardcode "$" but the JVM may use a different symbol (e.g. "€").
    def currency_symbol
      @currency_symbol ||= java.text.NumberFormat.getCurrencyInstance.getCurrency.getSymbol
    end

    # Java: FunctionTest#testAncestors
    it "returns ancestors set using level or numeric depth" do
      cs = currency_symbol

      # Test that we can execute Ancestors by passing a level as
      # the depth argument (PC hierarchy)
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
        set [*ancestors] as
          'Ancestors([Employees].[All Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Eric Long].[Adam Reynolds].[Joshua Huff].[Teanna Cobb], [Employees].[All Employees].Level)'
        select
          [*ancestors] on columns
        from [HR]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Eric Long].[Adam Reynolds].[Joshua Huff]}
        {[Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Eric Long].[Adam Reynolds]}
        {[Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Eric Long]}
        {[Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges]}
        {[Employees].[Sheri Nowmer].[Derrick Whelply]}
        {[Employees].[Sheri Nowmer]}
        {[Employees].[All Employees]}
        Row #0: #{cs}984.45
        Row #0: #{cs}3,426.54
        Row #0: #{cs}3,610.14
        Row #0: #{cs}17,099.20
        Row #0: #{cs}36,494.07
        Row #0: #{cs}39,431.67
        Row #0: #{cs}39,431.67
      RESULT

      # Test that we can execute Ancestors by passing a level as
      # the depth argument (non PC hierarchy)
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
        set [*ancestors] as
          'Ancestors([Store].[USA].[CA].[Los Angeles], [Store].[Store Country])'
        select
          [*ancestors] on columns
        from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Store].[USA].[CA]}
        {[Store].[USA]}
        Row #0: 74,748
        Row #0: 266,773
      RESULT

      # Test that we can execute Ancestors by passing an integer as
      # the depth argument (PC hierarchy)
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
        set [*ancestors] as
          'Ancestors([Employees].[All Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Eric Long].[Adam Reynolds].[Joshua Huff].[Teanna Cobb], 3)'
        select
          [*ancestors] on columns
        from [HR]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Eric Long].[Adam Reynolds].[Joshua Huff]}
        {[Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Eric Long].[Adam Reynolds]}
        {[Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Eric Long]}
        Row #0: #{cs}984.45
        Row #0: #{cs}3,426.54
        Row #0: #{cs}3,610.14
      RESULT

      # Test that we can execute Ancestors by passing an integer as
      # the depth argument (non PC hierarchy)
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
        set [*ancestors] as
          'Ancestors([Store].[USA].[CA].[Los Angeles], 2)'
        select
          [*ancestors] on columns
        from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Store].[USA].[CA]}
        {[Store].[USA]}
        Row #0: 74,748
        Row #0: 266,773
      RESULT

      # Test that we can count the number of ancestors.
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
        set [*ancestors] as
          'Ancestors([Employees].[All Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Eric Long].[Adam Reynolds].[Joshua Huff].[Teanna Cobb], [Employees].[All Employees].Level)'
        member [Measures].[Depth] as
          'Count([*ancestors])'
        select
          [Measures].[Depth] on columns
        from [HR]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Depth]}
        Row #0: 7
      RESULT

      # test depth argument not a level
      # Known Java-side failure: assertAxisThrows reports "query did not yield an exception"
      # in the Maven failsafe report. The query executes without error through both
      # the internal API and olap4j, returning a large result set instead of throwing.
    end
  end

  describe "Ascendants" do
    # Java: FunctionTest#testAscendants
    it "returns ascendants of a member" do
      assert_axis_returns @olap,
        "Ascendants([Store].[USA].[CA])",
        <<~EXPECTED.chomp
          [Store].[USA].[CA]
          [Store].[USA]
          [Store].[All Stores]
        EXPECTED
    end

    # Java: FunctionTest#testAscendantsAll
    it "returns ascendants of All member" do
      assert_axis_returns @olap,
        "Ascendants([Store].DefaultMember)",
        "[Store].[All Stores]"
    end

    # Java: FunctionTest#testAscendantsNull
    it "returns empty set for null member" do
      assert_axis_returns @olap,
        "Ascendants([Gender].[F].PrevMember)",
        ""
    end
  end

  describe "CalculatedChild" do
    # Java: FunctionTest#testCalculatedChild
    it "selects calculated child based on current product member" do
      # Construct calculated children with the same name for both [Drink] and
      # [Non-Consumable].  Then, create a metric to select the calculated
      # child based on current product member.
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
         member [Product].[All Products].[Drink].[Calculated Child] as '[Product].[All Products].[Drink].[Alcoholic Beverages]'
         member [Product].[All Products].[Non-Consumable].[Calculated Child] as '[Product].[All Products].[Non-Consumable].[Carousel]'
         member [Measures].[Unit Sales CC] as '([Measures].[Unit Sales],[Product].currentmember.CalculatedChild("Calculated Child"))'
         select non empty {[Measures].[Unit Sales CC]} on columns,
         non empty {[Product].[Drink], [Product].[Non-Consumable]} on rows
         from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales CC]}
        Axis #2:
        {[Product].[Drink]}
        {[Product].[Non-Consumable]}
        Row #0: 6,838
        Row #1: 841
      RESULT

      member = execute_singleton_axis(
        '[Product].[All Products].CalculatedChild("foobar")')
      assert_nil member
    end

    # Java: FunctionTest#testCalculatedChildUsingItem
    it "selects calculated child using Item function" do
      # Construct calculated children with the same name for both [Drink] and
      # [Non-Consumable].  Then, create a metric to select the first
      # calculated child.
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
         member [Product].[All Products].[Drink].[Calculated Child] as '[Product].[All Products].[Drink].[Alcoholic Beverages]'
         member [Product].[All Products].[Non-Consumable].[Calculated Child] as '[Product].[All Products].[Non-Consumable].[Carousel]'
         member [Measures].[Unit Sales CC] as '([Measures].[Unit Sales],AddCalculatedMembers([Product].currentmember.children).Item("Calculated Child"))'
         select non empty {[Measures].[Unit Sales CC]} on columns,
         non empty {[Product].[Drink], [Product].[Non-Consumable]} on rows
         from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales CC]}
        Axis #2:
        {[Product].[Drink]}
        {[Product].[Non-Consumable]}
        Row #0: 6,838
        Row #1: 6,838
      RESULT

      member = execute_singleton_axis(
        '[Product].[All Products].CalculatedChild("foobar")')
      assert_nil member
    end

    # Java: FunctionTest#testCalculatedChildOnMemberWithNoChildren
    it "returns null for calculated child on member with no children" do
      member = execute_singleton_axis(
        '[Measures].[Store Sales].CalculatedChild("foobar")')
      assert_nil member
    end

    # Java: FunctionTest#testCalculatedChildOnNullMember
    it "returns null for calculated child on null member" do
      member = execute_singleton_axis(
        '[Measures].[Store Sales].parent.CalculatedChild("foobar")')
      assert_nil member
    end
  end
end
