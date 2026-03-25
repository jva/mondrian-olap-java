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
describe "FunctionOperators" do
  before(:all) do
    create_olap_connection
  end

  # The NullNumericExpr from the Java test — a tuple that evaluates to NULL.
  NULL_NUMERIC_EXPR =
    "([Measures].[Unit Sales], " \
    "[Customers].[All Customers].[USA].[CA].[Bellflower], " \
    "[Product].[All Products].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Imported Beer])"

  # Helper: assert a boolean MDX expression returns the expected boolean.
  # Mirrors Java's assertBooleanExprReturns which wraps with Iif.
  def assert_boolean_expression_returns(olap, expression, expected)
    iif_expression = "Iif (#{expression},\"true\",\"false\")"
    assert_expression_returns olap, iif_expression, expected ? "true" : "false"
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
      # The cell value might be an error string or nil
      error_message = cell_value.to_s
      assert error_message.include?(pattern),
        "Expected error containing '#{pattern}', got cell value: #{error_message}"
    rescue Mondrian::OLAP::Error, Java::OrgOlap4j::OlapException, Java::MondrianOlap::MondrianException => e
      # Walk the cause chain to find the root cause message
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

  # Helper: assert that an expression produces a numeric result within delta of expected.
  def assert_expression_returns_numeric(olap, expression, expected, delta)
    mdx = <<~MDX
      WITH MEMBER [Measures].[_Expr] AS '#{expression}'
      SELECT {[Measures].[_Expr]} ON 0
      FROM [Sales]
    MDX
    result = olap.execute(mdx)
    actual = result.values.flatten.first
    assert_in_delta expected, actual.to_f, delta
  end

  describe "arithmetic operators" do
    # Java: FunctionTest#testPlus
    it "plus operator adds numbers and handles null" do
      assert_expression_returns @olap, "1+2", "3"
      assert_expression_returns @olap, "5 + #{NULL_NUMERIC_EXPR}", "5" # 5 + null --> 5
      assert_expression_returns @olap, "#{NULL_NUMERIC_EXPR} + #{NULL_NUMERIC_EXPR}", ""
      assert_expression_returns @olap, "#{NULL_NUMERIC_EXPR} + 0", "0"
    end

    # Java: FunctionTest#testMinus
    it "minus operator subtracts numbers and handles null" do
      assert_expression_returns @olap, "1-3", "-2"
      assert_expression_returns @olap, "5 - #{NULL_NUMERIC_EXPR}", "5" # 5 - null --> 5
      assert_expression_returns @olap, "#{NULL_NUMERIC_EXPR} - - 2", "2"
      assert_expression_returns @olap, "#{NULL_NUMERIC_EXPR} - #{NULL_NUMERIC_EXPR}", ""
    end

    # Java: FunctionTest#testMinus_bug1234759
    it "minus operator with calculated member (bug 1234759)" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH MEMBER [Customers].[USAMinusMexico]
        AS '([Customers].[All Customers].[USA] - [Customers].[All Customers].[Mexico])'
        SELECT {[Measures].[Unit Sales]} ON COLUMNS,
        {[Customers].[All Customers].[USA], [Customers].[All Customers].[Mexico],
        [Customers].[USAMinusMexico]} ON ROWS
        FROM [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Customers].[USA]}
        {[Customers].[Mexico]}
        {[Customers].[USAMinusMexico]}
        Row #0: 266,773
        Row #1:
        Row #2: 266,773
      RESULT
    end

    # Java: FunctionTest#testMinusAssociativity
    it "minus is left-associative" do
      # right-associative would give 11-(7-5) = 9, which is wrong
      assert_expression_returns @olap, "11-7-5", "-1"
    end

    # Java: FunctionTest#testMultiply
    it "multiply operator multiplies numbers and handles null" do
      assert_expression_returns @olap, "4*7", "28"
      assert_expression_returns @olap, "5 * #{NULL_NUMERIC_EXPR}", "" # 5 * null --> null
      assert_expression_returns @olap, "#{NULL_NUMERIC_EXPR} * - 2", ""
      assert_expression_returns @olap, "#{NULL_NUMERIC_EXPR} - #{NULL_NUMERIC_EXPR}", ""
    end

    # Java: FunctionTest#testMultiplyPrecedence
    it "multiply has higher precedence than add" do
      assert_expression_returns @olap, "3 + 4 * 5 + 6", "29"
      assert_expression_returns @olap, "5 * 24 / 4 * 2", "60"
      assert_expression_returns @olap, "48 / 4 / 2", "6"
    end

    # Bug 774807 caused expressions to be mistaken for the crossjoin operator.
    # Java: FunctionTest#testMultiplyBug774807
    it "multiply is not confused with crossjoin operator (bug 774807)" do
      desired_result = <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Store].[All Stores]}
        Axis #2:
        {[Measures].[Store Sales]}
        {[Measures].[A]}
        Row #0: 565,238.13
        Row #1: 319,494,143,605.90
      RESULT
      assert_query_returns @olap, <<~MDX, desired_result
        WITH MEMBER [Measures].[A] AS
         '([Measures].[Store Sales] * [Measures].[Store Sales])'
        SELECT {[Store]} ON COLUMNS,
         {[Measures].[Store Sales], [Measures].[A]} ON ROWS
        FROM Sales
      MDX
      # as above, no parentheses
      assert_query_returns @olap, <<~MDX, desired_result
        WITH MEMBER [Measures].[A] AS
         '[Measures].[Store Sales] * [Measures].[Store Sales]'
        SELECT {[Store]} ON COLUMNS,
         {[Measures].[Store Sales], [Measures].[A]} ON ROWS
        FROM Sales
      MDX
      # as above, plus 0
      assert_query_returns @olap, <<~MDX, desired_result
        WITH MEMBER [Measures].[A] AS
         '[Measures].[Store Sales] * [Measures].[Store Sales] + 0'
        SELECT {[Store]} ON COLUMNS,
         {[Measures].[Store Sales], [Measures].[A]} ON ROWS
        FROM Sales
      MDX
    end

    # Java: FunctionTest#testDivide
    it "divide operator handles nulls and NullDenominatorProducesNull property" do
      assert_expression_returns @olap, "10 / 5", "2"
      assert_expression_returns @olap, "#{NULL_NUMERIC_EXPR} / - 2", ""
      assert_expression_returns @olap, "#{NULL_NUMERIC_EXPR} / #{NULL_NUMERIC_EXPR}", ""

      # default behavior
      with_properties(NullDenominatorProducesNull: false) do
        assert_expression_returns @olap, "-2 / #{NULL_NUMERIC_EXPR}", "Infinity"
        assert_expression_returns @olap, "0 / 0", "NaN"
        assert_expression_returns @olap, "-3 / (2 - 2)", "-Infinity"

        assert_expression_returns @olap, "NULL/1", ""
        assert_expression_returns @olap, "NULL/NULL", ""
        assert_expression_returns @olap, "1/NULL", "Infinity"
      end

      # when NullOrZeroDenominatorProducesNull is set to true
      with_properties(NullDenominatorProducesNull: true) do
        assert_expression_returns @olap, "-2 / #{NULL_NUMERIC_EXPR}", ""
        assert_expression_returns @olap, "0 / 0", "NaN"
        assert_expression_returns @olap, "-3 / (2 - 2)", "-Infinity"

        assert_expression_returns @olap, "NULL/1", ""
        assert_expression_returns @olap, "NULL/NULL", ""
        assert_expression_returns @olap, "1/NULL", ""
      end
    end

    # Java: FunctionTest#testDividePrecedence
    it "divide has correct precedence with other arithmetic operators" do
      assert_expression_returns @olap, "24 / 4 / 2 * 10 - -1", "31"
    end

    # Java: FunctionTest#testMod
    it "mod function is consistent with Excel" do
      # the following tests are consistent with excel xp
      assert_expression_returns @olap, "mod(11, 3)", "2"
      assert_expression_returns @olap, "mod(-12, 3)", "0"

      # can handle non-ints, using the formula MOD(n, d) = n - d * INT(n / d)
      assert_expression_returns_numeric @olap, "mod(7.2, 3)", 1.2, 0.0001
      assert_expression_returns_numeric @olap, "mod(7.2, 3.2)", 0.8, 0.0001
      assert_expression_returns_numeric @olap, "mod(7.2, -3.2)", -2.4, 0.0001

      # per Excel doc "sign of result is same as divisor"
      assert_expression_returns @olap, "mod(3, 2)", "1"
      assert_expression_returns @olap, "mod(-3, 2)", "1"
      assert_expression_returns @olap, "mod(3, -2)", "-1"
      assert_expression_returns @olap, "mod(-3, -2)", "-1"

      assert_expression_raises @olap, "mod(4, 0)", "java.lang.ArithmeticException: / by zero"
      assert_expression_raises @olap, "mod(0, 0)", "java.lang.ArithmeticException: / by zero"
    end

    # Java: FunctionTest#testUnaryMinus
    it "unary minus negates a number" do
      assert_expression_returns @olap, "-3", "-3"
    end

    # Java: FunctionTest#testUnaryMinusMember
    it "unary minus negates a member expression" do
      assert_expression_returns @olap,
        "- ([Measures].[Unit Sales],[Gender].[F])",
        "-131,558"
    end

    # Java: FunctionTest#testUnaryMinusPrecedence
    it "unary minus has correct precedence" do
      assert_expression_returns @olap, "1 - -10.5 * 2 -3", "19"
    end

    # Java: FunctionTest#testNegativeZero
    it "negative zero literal displays as zero" do
      assert_expression_returns @olap, "-0.0", "0"
    end

    # Java: FunctionTest#testNegativeZero1
    it "negated zero displays as zero" do
      assert_expression_returns @olap, "-(0.0)", "0"
    end

    # Java: FunctionTest#testNegativeZeroSubtract
    it "negative zero minus zero displays as zero" do
      assert_expression_returns @olap, "-0.0 - 0.0", "0"
    end

    # Java: FunctionTest#testNegativeZeroMultiply
    it "negative one times zero displays as zero" do
      assert_expression_returns @olap, "-1 * 0", "0"
    end

    # Java: FunctionTest#testNegativeZeroDivide
    it "negative zero divided by two displays as zero" do
      assert_expression_returns @olap, "-0.0 / 2", "0"
    end
  end

  describe "string operators" do
    # The String(Integer,Char) function requires us to implicitly cast a
    # string to a char.
    # Java: FunctionTest#testString
    it "String function creates repeated characters" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member measures.x as 'String(3, "yahoo")'
        select measures.x on 0 from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[x]}
        Row #0: yyy
      RESULT
      # String is converted to char by taking first character
      assert_expression_returns @olap, 'String(3, "yahoo")', "yyy" # SSAS agrees
      # Integer is converted to char by converting to string and taking first
      # character. Mondrian requires an explicit cast (unlike SSAS2005).
      assert_expression_returns @olap, "String(3, Cast(32 as string))", "333"
      assert_expression_returns @olap, "String(8, Cast(-5 as string))", "--------"
      # Error if length<0
      assert_expression_returns @olap, "String(0, ''x'')", "" # SSAS agrees
      assert_expression_raises @olap, "String(-1, 'x')", "NegativeArraySizeException" # SSAS agrees
      assert_expression_raises @olap, "String(-200, 'x')", "NegativeArraySizeException" # SSAS agrees
    end

    # Java: FunctionTest#testStringConcat
    it "string concatenation with || operator" do
      assert_expression_returns @olap,
        ' "foo" || "bar"  ',
        "foobar"
    end

    # Java: FunctionTest#testStringConcat2
    it "string concatenation with member name" do
      assert_expression_returns @olap,
        ' "foo" || [Gender].[M].Name || "" ',
        "fooM"
    end
  end

  describe "boolean operators" do
    # Java: FunctionTest#testAnd
    it "AND returns true when both operands are true" do
      assert_boolean_expression_returns @olap, " 1=1 AND 2=2 ", true
    end

    # Java: FunctionTest#testAnd2
    it "AND returns false when one operand is false" do
      assert_boolean_expression_returns @olap, " 1=1 AND 2=0 ", false
    end

    # Java: FunctionTest#testOr
    it "OR returns false when both operands are false" do
      assert_boolean_expression_returns @olap, " 1=0 OR 2=0 ", false
    end

    # Java: FunctionTest#testOr2
    it "OR returns true when one operand is true" do
      assert_boolean_expression_returns @olap, " 1=0 OR 0=0 ", true
    end

    # Java: FunctionTest#testOrAssociativity1
    it "OR associativity: AND binds tighter than OR (case 1)" do
      # Would give 'false' if OR were stronger than AND (wrong!)
      assert_boolean_expression_returns @olap, " 1=1 AND 1=0 OR 1=1 ", true
    end

    # Java: FunctionTest#testOrAssociativity2
    it "OR associativity: AND binds tighter than OR (case 2)" do
      # Would give 'false' if OR were stronger than AND (wrong!)
      assert_boolean_expression_returns @olap, " 1=1 OR 1=0 AND 1=1 ", true
    end

    # Java: FunctionTest#testOrAssociativity3
    it "OR associativity: parentheses override precedence" do
      assert_boolean_expression_returns @olap, " (1=0 OR 1=1) AND 1=1 ", true
    end

    # Java: FunctionTest#testXor
    it "XOR returns false when both operands are true" do
      assert_boolean_expression_returns @olap, " 1=1 XOR 2=2 ", false
    end

    # Java: FunctionTest#testXorAssociativity
    it "XOR associativity: AND binds tighter than XOR" do
      # Would give 'false' if XOR were stronger than AND (wrong!)
      assert_boolean_expression_returns @olap, " 1 = 1 AND 1 = 1 XOR 1 = 0 ", true
    end
  end

  describe "NonEmptyCrossJoin" do
    # Java: FunctionTest#testNonEmptyCrossJoin
    it "returns non-empty cross join of two sets" do
      # NonEmptyCrossJoin needs to evaluate measures to find out whether
      # cells are empty, so it implicitly depends upon all dimensions.
      assert_axis_returns @olap,
        "NonEmptyCrossJoin(" \
        "[Customers].[All Customers].[USA].[CA].Children, " \
        "[Product].[All Products].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].Children)",
        <<~EXPECTED.chomp
          {[Customers].[USA].[CA].[Bellflower], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Light Beer]}
          {[Customers].[USA].[CA].[Downey], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Imported Beer]}
          {[Customers].[USA].[CA].[Glendale], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Imported Beer]}
          {[Customers].[USA].[CA].[Glendale], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Light Beer]}
          {[Customers].[USA].[CA].[Grossmont], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Light Beer]}
          {[Customers].[USA].[CA].[Imperial Beach], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Light Beer]}
          {[Customers].[USA].[CA].[La Jolla], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Imported Beer]}
          {[Customers].[USA].[CA].[Lincoln Acres], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Imported Beer]}
          {[Customers].[USA].[CA].[Lincoln Acres], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Light Beer]}
          {[Customers].[USA].[CA].[Long Beach], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Light Beer]}
          {[Customers].[USA].[CA].[Los Angeles], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Imported Beer]}
          {[Customers].[USA].[CA].[Newport Beach], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Imported Beer]}
          {[Customers].[USA].[CA].[Pomona], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Imported Beer]}
          {[Customers].[USA].[CA].[Pomona], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Light Beer]}
          {[Customers].[USA].[CA].[San Gabriel], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Light Beer]}
          {[Customers].[USA].[CA].[West Covina], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Imported Beer]}
          {[Customers].[USA].[CA].[West Covina], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Light Beer]}
          {[Customers].[USA].[CA].[Woodland Hills], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Imported Beer]}
        EXPECTED

      # empty set
      assert_axis_returns @olap, "NonEmptyCrossJoin({Gender.Parent}, {Store.Parent})", ""
      assert_axis_returns @olap, "NonEmptyCrossJoin({Store.Parent}, Gender.Children)", ""
      assert_axis_returns @olap, "NonEmptyCrossJoin(Store.Members, {})", ""
    end
  end

  describe "logical/not operators" do
    # Java: FunctionTest#testNot
    it "NOT negates a boolean expression" do
      assert_boolean_expression_returns @olap, " NOT 1=1 ", false
    end

    # Java: FunctionTest#testNotNot
    it "double NOT returns original value" do
      assert_boolean_expression_returns @olap, " NOT NOT 1=1 ", true
    end

    # Java: FunctionTest#testNotAssociativity
    it "NOT associativity with AND and OR" do
      assert_boolean_expression_returns @olap, " 1=1 AND NOT 1=1 OR NOT 1=1 AND 1=1 ", false
    end
  end

  describe "IS operator" do
    # Java: FunctionTest#testIsNull
    it "IS NULL checks for null members" do
      assert_boolean_expression_returns @olap, " Measures.[Profit] IS NULL ", false
      assert_boolean_expression_returns @olap, " Store.[All Stores] IS NULL ", false
      assert_boolean_expression_returns @olap, " Store.[All Stores].parent IS NULL ", true
    end

    # Java: FunctionTest#testIsMember
    it "IS compares members" do
      assert_boolean_expression_returns @olap,
        " Store.[USA].parent IS Store.[All Stores]", true
      assert_boolean_expression_returns @olap,
        " [Store].[USA].[CA].parent IS [Store].[Mexico]", false
    end

    # Java: FunctionTest#testIsString
    it "IS does not work with strings" do
      assert_expression_raises @olap,
        ' [Store].[USA].Name IS "USA" ',
        "No function matches signature '<String> IS <String>'"
    end

    # Java: FunctionTest#testIsNumeric
    it "IS does not work with numeric expressions" do
      assert_expression_raises @olap,
        " [Store].[USA].Level.Ordinal IS 25 ",
        "No function matches signature '<Numeric Expression> IS <Numeric Expression>'"
    end

    # Java: FunctionTest#testIsTuple
    it "IS compares tuples" do
      assert_boolean_expression_returns @olap,
        " (Store.[USA], Gender.[M]) IS (Store.[USA], Gender.[M])", true
      assert_boolean_expression_returns @olap,
        " (Store.[USA], Gender.[M]) IS (Gender.[M], Store.[USA])", true
      assert_boolean_expression_returns @olap,
        " (Store.[USA], Gender.[M]) IS (Gender.[M], Store.[USA]) " \
        "OR [Gender] IS NULL",
        true
      assert_boolean_expression_returns @olap,
        " (Store.[USA], Gender.[M]) IS (Gender.[M], Store.[USA]) " \
        "AND [Gender] IS NULL",
        false
      assert_boolean_expression_returns @olap,
        " (Store.[USA], Gender.[M]) IS (Store.[USA], Gender.[F])",
        false
      assert_boolean_expression_returns @olap,
        " (Store.[USA], Gender.[M]) IS (Store.[USA])",
        false
      assert_boolean_expression_returns @olap,
        " (Store.[USA], Gender.[M]) IS Store.[USA]",
        false
    end

    # Java: FunctionTest#testIsLevel
    it "IS compares levels" do
      assert_boolean_expression_returns @olap,
        " Store.[USA].level IS Store.[Store Country] ", true
      assert_boolean_expression_returns @olap,
        " Store.[USA].[CA].level IS Store.[Store Country] ", false
    end

    # Java: FunctionTest#testIsHierarchy
    it "IS compares hierarchies" do
      assert_boolean_expression_returns @olap,
        " Store.[USA].hierarchy IS Store.[Mexico].hierarchy ", true
      assert_boolean_expression_returns @olap,
        " Store.[USA].hierarchy IS Gender.[M].hierarchy ", false
    end

    # Java: FunctionTest#testIsDimension
    it "IS compares dimensions" do
      assert_boolean_expression_returns @olap, " Store.[USA].dimension IS Store ", true
      assert_boolean_expression_returns @olap, " Gender.[M].dimension IS Store ", false
    end
  end

  describe "comparison operators" do
    # Java: FunctionTest#testStringEquals
    it "string equals comparison" do
      assert_boolean_expression_returns @olap, ' "foo" = "bar" ', false
    end

    # Java: FunctionTest#testStringEqualsAssociativity
    it "string equals with concatenation" do
      assert_boolean_expression_returns @olap, ' "foo" = "fo" || "o" ', true
    end

    # Java: FunctionTest#testStringEqualsEmpty
    it "empty string equals empty string" do
      assert_boolean_expression_returns @olap, ' "" = "" ', true
    end

    # Java: FunctionTest#testEq
    it "numeric equals operator" do
      assert_boolean_expression_returns @olap, " 1.0 = 1 ", true
      assert_boolean_expression_returns @olap,
        "[Product].CurrentMember.Level.Ordinal = 2.0", false
      # checkNullOp("=")
      assert_boolean_expression_returns @olap, " 0 = #{NULL_NUMERIC_EXPR}", false
      assert_boolean_expression_returns @olap, " #{NULL_NUMERIC_EXPR} = 0", false
      assert_boolean_expression_returns @olap, " #{NULL_NUMERIC_EXPR} = #{NULL_NUMERIC_EXPR}", false
    end

    # Java: FunctionTest#testStringNe
    it "string not-equals comparison" do
      assert_boolean_expression_returns @olap, ' "foo" <> "bar" ', true
    end

    # Java: FunctionTest#testNe
    it "numeric not-equals operator" do
      assert_boolean_expression_returns @olap, " 2 <> 1.0 + 1.0 ", false
      # checkNullOp("<>")
      assert_boolean_expression_returns @olap, " 0 <> #{NULL_NUMERIC_EXPR}", false
      assert_boolean_expression_returns @olap, " #{NULL_NUMERIC_EXPR} <> 0", false
      assert_boolean_expression_returns @olap, " #{NULL_NUMERIC_EXPR} <> #{NULL_NUMERIC_EXPR}", false
    end

    # Java: FunctionTest#testNeInfinity
    it "infinity equals itself" do
      # Infinity does not equal itself
      assert_boolean_expression_returns @olap, "(1 / 0) <> (1 / 0)", false
    end

    # Java: FunctionTest#testLt
    it "less-than operator" do
      assert_boolean_expression_returns @olap, " 2 < 1.0 + 1.0 ", false
      # checkNullOp("<")
      assert_boolean_expression_returns @olap, " 0 < #{NULL_NUMERIC_EXPR}", false
      assert_boolean_expression_returns @olap, " #{NULL_NUMERIC_EXPR} < 0", false
      assert_boolean_expression_returns @olap, " #{NULL_NUMERIC_EXPR} < #{NULL_NUMERIC_EXPR}", false
    end

    # Java: FunctionTest#testLe
    it "less-than-or-equal operator" do
      assert_boolean_expression_returns @olap, " 2 <= 1.0 + 1.0 ", true
      # checkNullOp("<=")
      assert_boolean_expression_returns @olap, " 0 <= #{NULL_NUMERIC_EXPR}", false
      assert_boolean_expression_returns @olap, " #{NULL_NUMERIC_EXPR} <= 0", false
      assert_boolean_expression_returns @olap, " #{NULL_NUMERIC_EXPR} <= #{NULL_NUMERIC_EXPR}", false
    end

    # Java: FunctionTest#testGt
    it "greater-than operator" do
      assert_boolean_expression_returns @olap, " 2 > 1.0 + 1.0 ", false
      # checkNullOp(">")
      assert_boolean_expression_returns @olap, " 0 > #{NULL_NUMERIC_EXPR}", false
      assert_boolean_expression_returns @olap, " #{NULL_NUMERIC_EXPR} > 0", false
      assert_boolean_expression_returns @olap, " #{NULL_NUMERIC_EXPR} > #{NULL_NUMERIC_EXPR}", false
    end

    # Java: FunctionTest#testGe
    it "greater-than-or-equal operator" do
      assert_boolean_expression_returns @olap, " 2 > 1.0 + 1.0 ", false
      # checkNullOp(">=")
      assert_boolean_expression_returns @olap, " 0 >= #{NULL_NUMERIC_EXPR}", false
      assert_boolean_expression_returns @olap, " #{NULL_NUMERIC_EXPR} >= 0", false
      assert_boolean_expression_returns @olap, " #{NULL_NUMERIC_EXPR} >= #{NULL_NUMERIC_EXPR}", false
    end
  end
end
