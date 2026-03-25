# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2004-2005 Julian Hyde
# Copyright (C) 2005-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Factory that captures parsed MDX components for round-trip testing.
# Mirrors Java's ParserTest.TestParser inner class.
class ParserTestFactory
  include Java::MondrianParser::MdxParserValidator::QueryPartFactory

  attr_accessor :formulas, :axes, :cube, :slicer, :cell_props
  attr_accessor :drill_through, :max_row_count, :first_row_ordinal, :return_list, :explain

  def initialize
    @drill_through = false
    @explain = false
    @max_row_count = 0
    @first_row_ordinal = 0
  end

  def makeQuery(statement, formulae, axes, cube, slicer, cell_props, strict_validation)
    @formulas = formulae
    @axes = axes
    @cube = cube
    @slicer = slicer
    @cell_props = cell_props
    nil
  end

  def makeDrillThrough(query, max_row_count, first_row_ordinal, return_list)
    @drill_through = true
    @max_row_count = max_row_count
    @first_row_ordinal = first_row_ordinal
    @return_list = return_list
    nil
  end

  def makeExplain(query)
    @explain = true
    nil
  end

  def to_mdx_string
    string_writer = Java::JavaIo::StringWriter.new
    print_writer = Java::MondrianMdx::QueryPrintWriter.new(string_writer)
    unparse_to(print_writer)
    string_writer.toString
  end

  private

  def unparse_to(print_writer)
    print_writer.println("explain plan for") if @explain

    if @drill_through
      print_writer.print("drillthrough")
      print_writer.print(" maxrows #{@max_row_count}") if @max_row_count > 0
      print_writer.print(" firstrowset #{@first_row_ordinal}") if @first_row_ordinal > 0
      print_writer.println
    end

    if @formulas
      @formulas.length.times do |i|
        print_writer.print(i == 0 ? "with " : "  ")
        @formulas[i].unparse(print_writer)
        print_writer.println
      end
    end

    print_writer.print("select ")
    if @axes
      @axes.length.times do |i|
        @axes[i].unparse(print_writer)
        if i < @axes.length - 1
          print_writer.println(",")
          print_writer.print("  ")
        else
          print_writer.println
        end
      end
    end

    print_writer.println("from [#{@cube}]") if @cube

    if @slicer
      print_writer.print("where ")
      @slicer.unparse(print_writer)
      print_writer.println
    end

    if @cell_props
      @cell_props.length.times { |i| @cell_props[i].unparse(print_writer) }
    end

    if @drill_through && @return_list
      print_writer.print(" return ")
      Java::MondrianOlap::ExpBase.unparseList(
        print_writer, @return_list.to_a.to_java(Java::MondrianOlap::Exp),
        " return ", ", ", "")
    end
  end
end

# Java: mondrian/olap/ParserTest.java
describe "Parser" do
  FUN_TABLE = Java::MondrianOlapFun::BuiltinFunTable.instance

  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  def create_factory
    ParserTestFactory.new
  end

  def parse_query_old(factory, mdx)
    parser = Java::MondrianOlap::Parser.new
    parser.parseInternal(factory, nil, mdx, false, FUN_TABLE, false)
  end

  def parse_query_javacc(factory, mdx)
    parser = Java::MondrianParser::JavaccParserValidatorImpl.new(factory)
    parser.parseInternal(nil, mdx, false, FUN_TABLE, false)
  end

  # Parse MDX and assert unparsed output matches expected.
  # Tests with both old and new parsers by default.
  def assert_parse_query(mdx, expected, old: nil)
    parsers = old.nil? ? [true, false] : [old]
    parsers.each do |is_old|
      factory = create_factory
      result = is_old ? parse_query_old(factory, mdx) : parse_query_javacc(factory, mdx)
      assert_nil result, "Test parser should return null query (#{is_old ? 'old' : 'new'} parser)"
      actual = factory.to_mdx_string
      assert_equal expected, actual, "#{is_old ? 'old' : 'new'} parser"
    end
  end

  # Parse expression and assert unparsed output matches expected.
  def assert_parse_expr(expr, expected, old: nil)
    mdx = wrap_expr(expr)
    parsers = old.nil? ? [true, false] : [old]
    parsers.each do |is_old|
      factory = create_factory
      is_old ? parse_query_old(factory, mdx) : parse_query_javacc(factory, mdx)
      actual = Java::MondrianOlap::Util.unparse(factory.formulas[0].getExpression)
      assert_equal expected, actual, "#{is_old ? 'old' : 'new'} parser: #{expr}"
    end
  end

  # Assert that parsing MDX raises an error containing expected message.
  def assert_parse_query_fails(mdx, expected)
    factory = create_factory
    error = nil
    begin
      parse_query_old(factory, mdx)
    rescue => caught
      error = caught
    end
    refute_nil error, "Must return an error"
    cause = error
    while cause.respond_to?(:cause) && cause.cause && cause.cause != cause
      cause = cause.cause
    end
    assert cause.message.to_s.include?(expected),
      "Expected error containing '#{expected}', got: #{cause.message}"
  end

  def assert_parse_expr_fails(expr, expected)
    assert_parse_query_fails(wrap_expr(expr), expected)
  end

  def wrap_expr(expr)
    "with member [Measures].[Foo] as #{expr}\n select from [Sales]"
  end

  # Java: ParserTest#testAxisParsing
  it "parses axis specifications" do
    {0 => "COLUMNS", 1 => "ROWS", 2 => "PAGES", 3 => "CHAPTERS", 4 => "SECTIONS"}.each do |ordinal, name|
      [ordinal.to_s, "AXIS(#{ordinal})", name].each do |specification|
        factory = create_factory
        mdx = "select [member] on #{specification} from [cube]"
        result = parse_query_old(factory, mdx)
        assert_nil result, "Test parser should return null query"
        assert_equal 1, factory.axes.length, "Number of axes must be 1"
        assert_equal name, factory.axes[0].getAxisName, "Axis index name must be correct for '#{specification}'"
      end
    end
  end

  # Java: ParserTest#testNegativeCases
  it "rejects invalid axis specifications" do
    assert_parse_query_fails(
      "select [member] on axis(1.7) from sales",
      "Invalid axis specification. The axis number must be a non-negative integer, but it was 1.7.")
    assert_parse_query_fails(
      "select [member] on axis(-1) from sales",
      "Syntax error at line")
    # used to be an error, no longer
    assert_parse_query(
      "select [member] on axis(5) from sales",
      "select [member] ON AXIS(5)\nfrom [sales]\n")
    assert_parse_query_fails(
      "select [member] on axes(0) from sales",
      "Syntax error at line")
    assert_parse_query_fails(
      "select [member] on 0.5 from sales",
      "Invalid axis specification. The axis number must be a non-negative integer, but it was 0.5.")
    assert_parse_query(
      "select [member] on 555 from sales",
      "select [member] ON AXIS(555)\nfrom [sales]\n")
  end

  # Java: ParserTest#testScannerPunc
  # MONDRIAN-831: Identifiers beginning with '_' and '$'
  it "handles underscore and special characters in identifiers" do
    assert_parse_query(
      "with member [Measures].__Foo as 1 + 2\nselect __Foo on 0\nfrom _Bar_Baz",
      "with member [Measures].__Foo as '(1 + 2)'\nselect __Foo ON COLUMNS\nfrom [_Bar_Baz]\n")

    # # is not allowed
    assert_parse_query_fails(
      "with member [Measures].#_Foo as 1 + 2\nselect __Foo on 0\nfrom _Bar#Baz",
      "Unexpected character '#'")
    assert_parse_query_fails(
      "with member [Measures].Foo as 1 + 2\nselect Foo on 0\nfrom Bar#Baz",
      "Unexpected character '#'")

    # The spec doesn't allow $ but SSAS allows it so we allow it too
    assert_parse_query(
      "with member [Measures].$Foo as 1 + 2\nselect $Foo on 0\nfrom Bar$Baz",
      "with member [Measures].$Foo as '(1 + 2)'\nselect $Foo ON COLUMNS\nfrom [Bar$Baz]\n")
    # '$' is OK inside brackets too
    assert_parse_query(
      "select [measures].[$foo] on columns from sales",
      "select [measures].[$foo] ON COLUMNS\nfrom [sales]\n")

    # ']' unexpected
    assert_parse_query_fails(
      "select { Customers].Children } on columns from [Sales]",
      "Unexpected character ']'")
  end

  # Java: ParserTest#testUnderscore
  # Empty test in Java source
  it "underscore (placeholder)" do
    assert true
  end

  # Java: ParserTest#testUnparse
  it "round-trips parsed query through unparse" do
    mdx = "with member [Measures].[Foo] as ' 123 '\n" \
      "select {[Measures].members} on columns,\n" \
      " CrossJoin([Product].members, {[Gender].Children}) on rows\n" \
      "from [Sales]\n" \
      "where [Marital Status].[S]"
    expected = "with member [Measures].[Foo] as '123'\n" \
      "select {[Measures].Members} ON COLUMNS,\n" \
      "  Crossjoin([Product].Members, {[Gender].Children}) ON ROWS\n" \
      "from [Sales]\n" \
      "where [Marital Status].[S]\n"
    query = @olap.raw_mondrian_connection.parseQuery(mdx)
    actual = Java::MondrianOlap::Util.unparse(query)
    assert_equal expected, actual
  end

  # Java: ParserTest#testMultipleAxes
  it "parses multiple axes with ordinals in any order" do
    factory = create_factory
    mdx = "select {[axis0mbr]} on axis(0), {[axis1mbr]} on axis(1) from cube"
    result = parse_query_old(factory, mdx)
    assert_nil result, "Test parser should return null query"

    assert_equal 2, factory.axes.length, "Number of axes"
    assert_equal Java::MondrianOlap::AxisOrdinal::StandardAxisOrdinal.forLogicalOrdinal(0).name,
      factory.axes[0].getAxisName
    assert_equal Java::MondrianOlap::AxisOrdinal::StandardAxisOrdinal.forLogicalOrdinal(1).name,
      factory.axes[1].getAxisName

    # Capture first parse's axes before second parse overwrites factory.axes
    first_axes = factory.axes

    # Second parse: reversed order, mixed case — verifies parser handles this
    result = parse_query_old(factory,
      "select {[axis1mbr]} on aXiS(1), {[axis0mbr]} on AxIs(0) from cube")
    assert_nil result

    # Verify using first parse's axes (matches Java where local var wasn't updated)
    assert_equal 2, first_axes.length, "Number of axes"
    assert_equal Java::MondrianOlap::AxisOrdinal::StandardAxisOrdinal.forLogicalOrdinal(0).name,
      first_axes[0].getAxisName
    assert_equal Java::MondrianOlap::AxisOrdinal::StandardAxisOrdinal.forLogicalOrdinal(1).name,
      first_axes[1].getAxisName

    # Verify set expressions from first parse
    columns_set = first_axes[0].getSet
    refute_nil columns_set, "Column tuples"
    argument = columns_set.getArgs[0]
    segment = argument.getElement(0)
    assert_equal "axis0mbr", segment.name

    rows_set = first_axes[1].getSet
    refute_nil rows_set, "Row tuples"
    argument = rows_set.getArgs[0]
    segment = argument.getElement(0)
    assert_equal "axis1mbr", segment.name
  end

  # Java: ParserTest#testMemberOnAxis
  # If an axis expression is a member, implicitly convert it to a set.
  it "accepts member on axis" do
    assert_parse_query(
      "select [Measures].[Sales Count] on 0, non empty [Store].[Store State].members on 1 from [Sales]",
      "select [Measures].[Sales Count] ON COLUMNS,\n" \
      "  NON EMPTY [Store].[Store State].members ON ROWS\n" \
      "from [Sales]\n")
  end

  # Java: ParserTest#testCaseTest
  it "parses CASE WHEN expression" do
    assert_parse_query(
      "with member [Measures].[Foo] as " \
      " ' case when x = y then \"eq\" when x < y then \"lt\" else \"gt\" end '" \
      "select {[foo]} on axis(0) from cube",
      "with member [Measures].[Foo] as 'CASE WHEN (x = y) THEN \"eq\" WHEN (x < y) THEN \"lt\" ELSE \"gt\" END'\n" \
      "select {[foo]} ON COLUMNS\n" \
      "from [cube]\n")
  end

  # Java: ParserTest#testCaseSwitch
  it "parses CASE switch expression" do
    assert_parse_query(
      "with member [Measures].[Foo] as " \
      " ' case x when 1 then 2 when 3 then 4 else 5 end '" \
      "select {[foo]} on axis(0) from cube",
      "with member [Measures].[Foo] as 'CASE x WHEN 1 THEN 2 WHEN 3 THEN 4 ELSE 5 END'\n" \
      "select {[foo]} ON COLUMNS\n" \
      "from [cube]\n")
  end

  # Java: ParserTest#testSetExpr
  # MONDRIAN-306: Parser should not require braces around range op in WITH SET
  it "parses set expressions with range operator" do
    assert_parse_query(
      "with set [Set1] as '[Product].[Drink]:[Product].[Food]' \n" \
      "select [Set1] on columns, {[Measures].defaultMember} on rows \nfrom Sales",
      "with set [Set1] as '([Product].[Drink] : [Product].[Food])'\n" \
      "select [Set1] ON COLUMNS,\n" \
      "  {[Measures].defaultMember} ON ROWS\n" \
      "from [Sales]\n")

    # set expr in axes
    assert_parse_query(
      "select [Product].[Drink]:[Product].[Food] on columns,\n" \
      " {[Measures].defaultMember} on rows \nfrom Sales",
      "select ([Product].[Drink] : [Product].[Food]) ON COLUMNS,\n" \
      "  {[Measures].defaultMember} ON ROWS\n" \
      "from [Sales]\n")
  end

  # Java: ParserTest#testDimensionProperties
  it "parses DIMENSION PROPERTIES" do
    assert_parse_query(
      "select {[foo]} properties p1,   p2 on columns from [cube]",
      "select {[foo]} DIMENSION PROPERTIES p1, p2 ON COLUMNS\n" \
      "from [cube]\n")
  end

  # Java: ParserTest#testCellProperties
  it "parses CELL PROPERTIES" do
    assert_parse_query(
      "select {[foo]} on columns from [cube] CELL PROPERTIES FORMATTED_VALUE",
      "select {[foo]} ON COLUMNS\n" \
      "from [cube]\n" \
      "[FORMATTED_VALUE]")
  end

  # Java: ParserTest#testIsEmpty
  it "parses IS EMPTY expressions" do
    assert_parse_expr(
      "[Measures].[Unit Sales] IS EMPTY",
      "([Measures].[Unit Sales] IS EMPTY)")

    assert_parse_expr(
      "[Measures].[Unit Sales] IS EMPTY AND 1 IS NULL",
      "(([Measures].[Unit Sales] IS EMPTY) AND (1 IS NULL))")

    # FIXME: Gives error at token '+' with new parser.
    assert_parse_expr(
      "- x * 5 is empty is empty is null + 56",
      "(((((- x) * 5) IS EMPTY) IS EMPTY) IS (NULL + 56))",
      old: true)
  end

  # Java: ParserTest#testIs
  it "parses IS expressions" do
    assert_parse_expr(
      "[Measures].[Unit Sales] IS [Measures].[Unit Sales] " \
      "AND [Measures].[Unit Sales] IS NULL",
      "(([Measures].[Unit Sales] IS [Measures].[Unit Sales]) " \
      "AND ([Measures].[Unit Sales] IS NULL))")
  end

  # Java: ParserTest#testIsNull
  it "parses IS NULL expressions" do
    assert_parse_expr(
      "[Measures].[Unit Sales] IS NULL",
      "([Measures].[Unit Sales] IS NULL)")

    assert_parse_expr(
      "[Measures].[Unit Sales] IS NULL AND 1 <> 2",
      "(([Measures].[Unit Sales] IS NULL) AND (1 <> 2))")

    assert_parse_expr(
      "x is null or y is null and z = 5",
      "((x IS NULL) OR ((y IS NULL) AND (z = 5)))")

    assert_parse_expr(
      "(x is null) + 56 > 6",
      "((((x IS NULL)) + 56) > 6)")

    # FIXME: Gives error at token '+' with new parser.
    assert_parse_expr(
      "x is null and a = b or c = d + 5 is null + 5",
      "(((x IS NULL) AND (a = b)) OR ((c = (d + 5)) IS (NULL + 5)))",
      old: true)
  end

  # Java: ParserTest#testNull
  it "parses NULL in expressions" do
    assert_parse_expr(
      "Filter({[Measures].[Foo]}, Iif(1 = 2, NULL, 'X'))",
      "Filter({[Measures].[Foo]}, Iif((1 = 2), NULL, \"X\"))")
  end

  # Java: ParserTest#testCast
  it "parses CAST expressions" do
    assert_parse_expr(
      "Cast([Measures].[Unit Sales] AS Numeric)",
      "CAST([Measures].[Unit Sales] AS Numeric)")

    assert_parse_expr(
      "Cast(1 + 2 AS String)",
      "CAST((1 + 2) AS String)")
  end

  # Java: ParserTest#testMultiplication
  # Verifies that calculated measures made of several '*' operators can resolve correctly.
  it "resolves multiple multiplication operators" do
    parser = Java::MondrianOlap::Parser.new
    mdx = wrap_expr("([Measures].[Unit Sales] * [Measures].[Store Cost] * [Measures].[Store Sales])")
    statement = @olap.raw_mondrian_connection.getInternalStatement
    begin
      factory_impl = Java::MondrianOlap::Parser::FactoryImpl.new
      query = parser.parseInternal(factory_impl, statement, mdx, false, FUN_TABLE, false)
      assert_kind_of Java::MondrianOlap::Query, query
      query.resolve
    ensure
      statement.close
    end
  end

  # Java: ParserTest#testBangFunction
  it "parses bang function syntax" do
    # Parser accepts '<id> [! <id>] *' as a function name, but ignores all but last name.
    assert_parse_expr("foo!bar!Exp(2.0)", "Exp(2.0)")
    assert_parse_expr("1 + VBA!Exp(2.0 + 3)", "(1 + Exp((2.0 + 3)))")
  end

  # Java: ParserTest#testId
  it "parses identifiers" do
    assert_parse_expr("foo", "foo")
    assert_parse_expr("fOo", "fOo")
    assert_parse_expr("[Foo].[Bar Baz]", "[Foo].[Bar Baz]")
    assert_parse_expr("[Foo].&[Bar]", "[Foo].&[Bar]", old: false)
  end

  # Java: ParserTest#testIdWithKey
  it "parses identifiers with compound keys" do
    mdx_expr = "[Foo].&Key1&Key2.&[Key3]&Key4&[5]"
    assert_parse_expr(mdx_expr, mdx_expr, old: false)

    factory = create_factory
    parse_query_javacc(factory, wrap_expr(mdx_expr))
    assert_equal 1, factory.formulas.length
    formula = factory.formulas[0]
    expr = formula.getExpression
    assert_equal 3, expr.getSegments.size

    segment0 = expr.getSegments.get(0)
    assert_equal "Foo", segment0.getName
    assert_equal Java::MondrianOlap::Id::Quoting::QUOTED, segment0.getQuoting

    segment1 = expr.getSegments.get(1)
    assert_equal Java::MondrianOlap::Id::Quoting::KEY, segment1.getQuoting
    key_parts = segment1.getKeyParts
    refute_nil key_parts
    assert_equal 2, key_parts.size
    assert_equal "Key1", key_parts.get(0).getName
    assert_equal Java::MondrianOlap::Id::Quoting::UNQUOTED, key_parts.get(0).getQuoting
    assert_equal "Key2", key_parts.get(1).getName
    assert_equal Java::MondrianOlap::Id::Quoting::UNQUOTED, key_parts.get(1).getQuoting

    segment2 = expr.getSegments.get(2)
    assert_equal Java::MondrianOlap::Id::Quoting::KEY, segment2.getQuoting
    key_parts2 = segment2.getKeyParts
    refute_nil key_parts2
    assert_equal 3, key_parts2.size
    assert_equal Java::MondrianOlap::Id::Quoting::QUOTED, key_parts2.get(0).getQuoting
    assert_equal Java::MondrianOlap::Id::Quoting::UNQUOTED, key_parts2.get(1).getQuoting
    assert_equal Java::MondrianOlap::Id::Quoting::QUOTED, key_parts2.get(2).getQuoting
    assert_equal "5", key_parts2.get(2).getName

    assert_equal mdx_expr, expr.toString
  end

  # Java: ParserTest#testIdComplex
  it "parses complex identifiers with keys" do
    # simple key
    assert_parse_expr("[Foo].&[Key1]&[Key2].[Bar]", "[Foo].&[Key1]&[Key2].[Bar]", old: false)
    # compound key
    assert_parse_expr("[Foo].&[1]&[Key 2]&[3].[Bar]", "[Foo].&[1]&[Key 2]&[3].[Bar]", old: false)
    # compound key sans brackets
    assert_parse_expr("[Foo].&Key1&Key2 + 4", "([Foo].&Key1&Key2 + 4)", old: false)
    # but underscore is OK within brackets
    assert_parse_expr("[Foo].&[_Key2].[Bar]", "[Foo].&[_Key2].[Bar]", old: false)
  end

  # Java: ParserTest#testCloneQuery
  it "clones a parsed query" do
    connection = @olap.raw_mondrian_connection
    query = connection.parseQuery(
      "select {[Measures].Members} on columns,\n" \
      " {[Store].Members} on rows\n" \
      "from [Sales]\n" \
      "where ([Gender].[M])")
    query_clone = query.clone
    assert_kind_of Java::MondrianOlap::Query, query_clone
    assert_equal query.toString, query_clone.toString
  end

  # Java: ParserTest#testNumbers
  it "parses numbers" do
    assert_parse_expr("2", "2")
    assert_parse_expr("-3", "(- 3)")
    assert_parse_expr("+45", "45")

    assert_parse_expr_fails("4 5", "Syntax error at line 1, column 35, token '5'")

    assert_parse_expr("3.14", "3.14")
    assert_parse_expr(".12345", "0.12345")

    # lots of digits left and right of point
    assert_parse_expr("31415926535.89793", "31415926535.89793")
    assert_parse_expr("31415926535897.9314159265358979", "31415926535897.9314159265358979")
    assert_parse_expr("3.141592653589793", "3.141592653589793")
    assert_parse_expr("-3141592653589793.14159265358979", "(- 3141592653589793.14159265358979)")

    # exponents — old and new parsers differ
    assert_parse_expr("1e2", "100", old: true)
    assert_parse_expr("1e2", "1E+2", old: false)

    assert_parse_expr_fails("1e2e3", "Syntax error at line 1, column 37, token 'e3'")

    assert_parse_expr("1.2e3", "1200", old: true)
    assert_parse_expr("1.2e3", "1.2E+3", old: false)

    assert_parse_expr("-1.2345e3", "(- 1234.5)")
    assert_parse_expr_fails("1.2e3.4", "Syntax error at line 1, column 39, token '0.4'")
    assert_parse_expr(".00234e0003", "2.34")
    assert_parse_expr(".00234e-0067", "2.34E-70")
  end

  # Java: ParserTest#testLargePrecision
  # MONDRIAN-272: High precision number in MDX causes overflow
  it "handles large precision numbers" do
    assert_parse_query(
      "with member [Measures].[Small Number] as '[Measures].[Store Sales] / 9000'\n" \
      "select\n" \
      "{[Measures].[Small Number]} on columns,\n" \
      "{Filter([Product].[Product Department].members, [Measures].[Small Number] >= 0.3\n" \
      "and [Measures].[Small Number] <= 0.5000001234)} on rows\n" \
      "from Sales\n" \
      "where ([Time].[1997].[Q2].[4])",
      "with member [Measures].[Small Number] as '([Measures].[Store Sales] / 9000)'\n" \
      "select {[Measures].[Small Number]} ON COLUMNS,\n" \
      "  {Filter([Product].[Product Department].members, (([Measures].[Small Number] >= 0.3) AND ([Measures].[Small Number] <= 0.5000001234)))} ON ROWS\n" \
      "from [Sales]\n" \
      "where ([Time].[1997].[Q2].[4])\n")
  end

  # Java: ParserTest#testIdentifier
  it "constructs and inspects Id objects" do
    # must have at least one segment
    assert_raises(java.lang.IllegalArgumentException) do
      Java::MondrianOlap::Id.new(java.util.Collections.emptyList)
    end

    id = Java::MondrianOlap::Id.new(Java::MondrianOlap::Id::NameSegment.new("foo"))
    assert_equal "[foo]", id.toString

    # append does not mutate
    id2 = id.append(
      Java::MondrianOlap::Id::KeySegment.new(
        Java::MondrianOlap::Id::NameSegment.new("bar", Java::MondrianOlap::Id::Quoting::QUOTED)))
    refute_same id, id2
    assert_equal "[foo]", id.toString
    assert_equal "[foo].&[bar]", id2.toString

    # cannot mutate segment list
    segments = id.getSegments
    assert_raises(java.lang.UnsupportedOperationException) { segments.remove(0) }
    assert_raises(java.lang.UnsupportedOperationException) { segments.clear }
    assert_raises(java.lang.UnsupportedOperationException) do
      segments.add(Java::MondrianOlap::Id::NameSegment.new("baz"))
    end
  end

  # Java: ParserTest#testEmptyExpr
  # Bug 3030772: DrilldownLevelTop parser error
  it "parses empty expressions in function arguments" do
    assert_parse_query(
      "select NON EMPTY HIERARCHIZE(\n" \
      "  {DrillDownLevelTop(\n" \
      "     {[Product].[All Products]},3,,[Measures].[Unit Sales])}" \
      "  ) ON COLUMNS\n" \
      "from [Sales]\n",
      "select NON EMPTY HIERARCHIZE({DrillDownLevelTop({[Product].[All Products]}, 3, , [Measures].[Unit Sales])}) ON COLUMNS\n" \
      "from [Sales]\n")

    assert_parse_query(
      "SELECT {[Measures].[NetSales]}" \
      " DIMENSION PROPERTIES PARENT_UNIQUE_NAME ON COLUMNS ," \
      " NON EMPTY HIERARCHIZE(AddCalculatedMembers(" \
      "{DrillDownLevelTop({[ProductDim].[Name].[All]}, 10, ," \
      " [Measures].[NetSales])}))" \
      " DIMENSION PROPERTIES PARENT_UNIQUE_NAME ON ROWS " \
      "FROM [cube]",
      "select {[Measures].[NetSales]} DIMENSION PROPERTIES PARENT_UNIQUE_NAME ON COLUMNS,\n" \
      "  NON EMPTY HIERARCHIZE(AddCalculatedMembers({DrillDownLevelTop({[ProductDim].[Name].[All]}, 10, , [Measures].[NetSales])})) DIMENSION PROPERTIES PARENT_UNIQUE_NAME ON ROWS\n" \
      "from [cube]\n")
  end

  # Java: ParserTest#testAsPrecedence
  # MONDRIAN-648: AS operator has lower precedence than required by MDX specification
  it "handles AS operator precedence" do
    bug_fixed = Java::MondrianUtil::Bug::BugMondrian648Fixed

    # low precedence operator (AND) in CAST
    assert_parse_query(
      "select cast(a and b as string) on 0 from cube",
      "select CAST((a AND b) AS string) ON COLUMNS\nfrom [cube]\n")

    # medium precedence operator (:) in CAST
    assert_parse_query(
      "select cast(a : b as string) on 0 from cube",
      "select CAST((a : b) AS string) ON COLUMNS\nfrom [cube]\n")

    # high precedence operator (IS) in CAST
    assert_parse_query(
      "select cast(a is b as string) on 0 from cube",
      "select CAST((a IS b) AS string) ON COLUMNS\nfrom [cube]\n")

    # low precedence operator in axis expression
    expected = bug_fixed \
      ? "select (a * (b AS c) ON COLUMNS\nfrom [cube]\n" \
      : "select ((a * b) AS c) ON COLUMNS\nfrom [cube]\n"
    assert_parse_query("select a * b as c on 0 from cube", expected)

    if bug_fixed
      assert_parse_query(
        "select a * b as c * d on 0 from cube",
        "select (((a * b) AS c) * d) ON COLUMNS\nfrom [cube]\n")
    else
      assert_parse_query_fails(
        "select a * b as c * d on 0 from cube",
        "Syntax error at line 1, column 19, token '*'")
    end

    # Spec says ':' has a higher precedence than '*'.
    expected = bug_fixed \
      ? "select ((a : b) * (c : d)) ON COLUMNS\nfrom [cube]\n" \
      : "select ((a : (b * c)) : d) ON COLUMNS\nfrom [cube]\n"
    assert_parse_query("select a : b * c : d on 0 from cube", expected)

    if bug_fixed
      assert_parse_query(
        "select a : b as n * c : d as n2 as n3 on 0 from cube",
        "select (((a : b) as n) * ((c : d) AS n2) as n3) ON COLUMNS\nfrom [cube]\n")
    else
      assert_parse_query_fails(
        "select a : b as n * c : d as n2 as n3 on 0 from cube",
        "Syntax error at line 1, column 19, token '*'")
    end
  end

  # Java: ParserTest#testDrillThrough
  it "parses DRILLTHROUGH" do
    assert_parse_query(
      "DRILLTHROUGH SELECT [Foo] on 0, [Bar] on 1 FROM [Cube]",
      "drillthrough\nselect [Foo] ON COLUMNS,\n  [Bar] ON ROWS\nfrom [Cube]\n")
  end

  # Java: ParserTest#testDrillThroughExtended1
  it "parses DRILLTHROUGH with MAXROWS, FIRSTROWSET and single RETURN" do
    assert_parse_query(
      "DRILLTHROUGH MAXROWS 5 FIRSTROWSET 7\n" \
      "SELECT [Foo] on 0, [Bar] on 1 FROM [Cube]\n" \
      "RETURN [Xxx].[AAa]",
      "drillthrough maxrows 5 firstrowset 7\n" \
      "select [Foo] ON COLUMNS,\n  [Bar] ON ROWS\n" \
      "from [Cube]\n return  return [Xxx].[AAa]")
  end

  # Java: ParserTest#testDrillThroughExtended
  it "parses DRILLTHROUGH with two RETURN columns" do
    assert_parse_query(
      "DRILLTHROUGH MAXROWS 5 FIRSTROWSET 7\n" \
      "SELECT [Foo] on 0, [Bar] on 1 FROM [Cube]\n" \
      "RETURN [Xxx].[AAa], [YYY]",
      "drillthrough maxrows 5 firstrowset 7\n" \
      "select [Foo] ON COLUMNS,\n  [Bar] ON ROWS\n" \
      "from [Cube]\n return  return [Xxx].[AAa], [YYY]")
  end

  # Java: ParserTest#testDrillThroughExtended3
  it "parses DRILLTHROUGH with three RETURN columns" do
    assert_parse_query(
      "DRILLTHROUGH MAXROWS 5 FIRSTROWSET 7\n" \
      "SELECT [Foo] on 0, [Bar] on 1 FROM [Cube]\n" \
      "RETURN [Xxx].[AAa], [YYY], [zzz]",
      "drillthrough maxrows 5 firstrowset 7\n" \
      "select [Foo] ON COLUMNS,\n  [Bar] ON ROWS\n" \
      "from [Cube]\n return  return [Xxx].[AAa], [YYY], [zzz]")
  end

  # Java: ParserTest#testExplain
  it "parses EXPLAIN PLAN FOR" do
    assert_parse_query(
      "explain plan for\n" \
      "with member [Mesaures].[Foo] as 1 + 3\n" \
      "select [Measures].[Unit Sales] on 0,\n" \
      " [Product].Children on 1\n" \
      "from [Sales]",
      "explain plan for\n" \
      "with member [Mesaures].[Foo] as '(1 + 3)'\n" \
      "select [Measures].[Unit Sales] ON COLUMNS,\n" \
      "  [Product].Children ON ROWS\n" \
      "from [Sales]\n")
    assert_parse_query(
      "explain plan for\n" \
      "drillthrough maxrows 5\n" \
      "with member [Mesaures].[Foo] as 1 + 3\n" \
      "select [Measures].[Unit Sales] on 0,\n" \
      " [Product].Children on 1\n" \
      "from [Sales]",
      "explain plan for\n" \
      "drillthrough maxrows 5\n" \
      "with member [Mesaures].[Foo] as '(1 + 3)'\n" \
      "select [Measures].[Unit Sales] ON COLUMNS,\n" \
      "  [Product].Children ON ROWS\n" \
      "from [Sales]\n")
  end

  # Java: ParserTest#testMultipleSpaces
  # MONDRIAN-924: Parsing fails with multiple spaces between words
  it "preserves multiple spaces in identifiers" do
    assert_parse_query(
      "select [Store].[With   multiple  spaces] on 0\nfrom [Sales]",
      "select [Store].[With   multiple  spaces] ON COLUMNS\nfrom [Sales]\n")
  end

  # Java: ParserTest#testChildren
  # olap4j bug 3515404: Inconsistent parsing behavior('.CHILDREN' and '.Children')
  it "parses .Children in any case" do
    parser = Java::MondrianOlap::Parser.new
    %w[CHILDREN Children children].each do |name|
      node = parser.parseExpression(nil, nil, "[Store].[USA].#{name}", false, FUN_TABLE)
      assert_kind_of Java::MondrianOlap::FunCall, node
      assert_equal name, node.getFunName
      assert_kind_of Java::MondrianOlap::Id, node.getArgs[0]
      assert_equal "[Store].[USA]", node.getArgs[0].toString
      assert_equal 1, node.getArgCount
    end
  end
end
