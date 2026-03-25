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

# Java: mondrian/olap/CustomizedParserTest.java
describe "CustomizedParser" do
  before(:all) do
    create_olap_connection
  end

  def build_function_table(*function_names)
    function_name_set = java.util.HashSet.new
    function_names.each { |name| function_name_set.add(name) }

    special_functions = java.util.HashSet.new
    special_functions.add(
      Java::MondrianOlapFun::ParenthesesFunDef.new(Java::MondrianOlap::Category::Numeric)
    )

    function_table = Java::MondrianOlapFun::CustomizedFunctionTable.new(function_name_set, special_functions)
    function_table.init
    function_table
  end

  def parse_and_resolve(function_table, expression, strict_validation: false)
    mdx = "with member [Measures].[Foo] as #{expression}\n select from [Sales]"
    connection = @olap.raw_mondrian_connection
    statement = connection.getInternalStatement
    begin
      query = connection.parseStatement(statement, mdx, function_table, strict_validation)
      query.resolve(query.createValidator(function_table, true))
      query
    ensure
      statement.close
    end
  end

  def root_cause_message(exception)
    cause = exception
    cause = cause.cause while cause.cause && cause.cause != cause
    cause.message
  end

  describe "allowed operations" do
    # Java: CustomizedParserTest#testAddition
    it "parses addition" do
      function_table = build_function_table("+")
      query = parse_and_resolve(function_table, "([Measures].[Store Cost] + [Measures].[Unit Sales])")
      refute_nil query
    end

    # Java: CustomizedParserTest#testSubtraction
    it "parses subtraction" do
      function_table = build_function_table("-")
      query = parse_and_resolve(function_table, "([Measures].[Store Cost] - [Measures].[Unit Sales])")
      refute_nil query
    end

    # Java: CustomizedParserTest#testSingleMultiplication
    it "parses single multiplication" do
      function_table = build_function_table("*")
      query = parse_and_resolve(function_table, "[Measures].[Store Cost] * [Measures].[Unit Sales]")
      refute_nil query
    end

    # Java: CustomizedParserTest#testMultipleMultiplication
    it "parses multiple multiplication" do
      function_table = build_function_table("*")
      query = parse_and_resolve(function_table,
        "([Measures].[Store Cost] * [Measures].[Unit Sales] * [Measures].[Store Sales])")
      refute_nil query
    end

    # Java: CustomizedParserTest#testLiterals
    it "parses literals" do
      function_table = build_function_table("+")
      query = parse_and_resolve(function_table, "([Measures].[Store Cost] + 10)")
      refute_nil query
    end
  end

  describe "disallowed operations" do
    # Java: CustomizedParserTest#testMissingObjectFail
    it "fails on missing object" do
      function_table = build_function_table("+")
      error = assert_raises(Java::MondrianOlap::MondrianException) do
        parse_and_resolve(function_table,
          "'[Measures].[Store Cost] + [Measures].[Unit Salese]'")
      end
      assert_equal "Mondrian Error:MDX object '[Measures].[Unit Salese]' not found in cube 'Sales'",
        root_cause_message(error)
    end

    # Java: CustomizedParserTest#testMultiplicationFail
    it "fails when multiplication is not allowed" do
      function_table = build_function_table("+")
      error = assert_raises(Java::MondrianOlap::MondrianException) do
        parse_and_resolve(function_table,
          "([Measures].[Store Cost] * [Measures].[Unit Sales])")
      end
      assert_equal "Mondrian Error:No function matches signature '<Member> * <Member>'",
        root_cause_message(error)
    end

    # Java: CustomizedParserTest#testMixingAttributesFail
    it "fails when mixing attributes" do
      function_table = build_function_table("+")
      error = assert_raises(Java::MondrianOlap::MondrianException) do
        parse_and_resolve(function_table,
          "([Measures].[Store Cost] + [Store].[Store Country])")
      end
      assert_equal "Mondrian Error:No function matches signature '<Member> + <Level>'",
        root_cause_message(error)
    end

    # Java: CustomizedParserTest#testCrossJoinFail
    it "fails on CrossJoin with same hierarchy" do
      function_table = build_function_table("+", "-", "*", "/")
      error = assert_raises(Java::MondrianOlap::MondrianException) do
        parse_and_resolve(function_table,
          "CrossJoin([Measures].[Store Cost], [Measures].[Unit Sales])")
      end
      assert_equal "Mondrian Error:Tuple contains more than one member of hierarchy '[Measures]'.",
        root_cause_message(error)
    end

    # Java: CustomizedParserTest#testMeasureSlicerFail
    it "fails on measure slicer tuple" do
      function_table = build_function_table("+", "-", "*", "/")
      error = assert_raises(Java::MondrianOlap::MondrianException) do
        parse_and_resolve(function_table,
          "([Measures].[Store Cost], [Gender].[F])")
      end
      assert_equal "Mondrian Error:No function matches signature '(<Member>, <Member>)'",
        root_cause_message(error)
    end

    # Java: CustomizedParserTest#testTupleFail
    it "fails on tuple" do
      function_table = build_function_table("+", "-", "*", "/")
      error = assert_raises(Java::MondrianOlap::MondrianException) do
        parse_and_resolve(function_table,
          "([Store].[USA], [Gender].[F])")
      end
      assert_equal "Mondrian Error:No function matches signature '(<Member>, <Member>)'",
        root_cause_message(error)
    end
  end

  describe "strict validation" do
    # Java: CustomizedParserTest#testMissingObjectFailWithStrict
    it "fails on missing object with strict validation" do
      function_table = build_function_table("+")
      with_properties(IgnoreInvalidMembers: true, IgnoreInvalidMembersDuringQuery: true) do
        error = assert_raises(Java::MondrianOlap::MondrianException) do
          parse_and_resolve(function_table,
            "'[Measures].[Store Cost] + [Measures].[Unit Salese]'",
            strict_validation: true)
        end
        assert_equal "Mondrian Error:MDX object '[Measures].[Unit Salese]' not found in cube 'Sales'",
          root_cause_message(error)
      end
    end

    # Java: CustomizedParserTest#testMissingObjectSucceedWithoutStrict
    it "succeeds on missing object without strict validation" do
      function_table = build_function_table("+")
      with_properties(IgnoreInvalidMembers: true, IgnoreInvalidMembersDuringQuery: true) do
        query = parse_and_resolve(function_table,
          "'[Measures].[Store Cost] + [Measures].[Unit Salese]'",
          strict_validation: false)
        refute_nil query
      end
    end
  end

  # Java: CustomizedParserTest#testMixingMemberLimitation
  # Mondrian is not strict about referencing a dimension member in calculated
  # measures. The following expression passes parsing and validation.
  # Its computation is strange: the result is as if the measure is defined as
  # ([Measures].[Store Cost] + [Measures].[Store Cost]).
  it "allows mixing member from different dimension (known limitation)" do
    function_table = build_function_table("+")
    query = parse_and_resolve(function_table,
      "([Measures].[Store Cost] + [Store].[USA])")
    refute_nil query
  end
end
