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
describe "String Functions" do
  before(:all) do
    create_olap_connection
  end

  describe "Literals" do
    # Java: FunctionTest#testNumericLiteral
    it "numeric literal returns formatted value" do
      assert_expression_returns @olap, "2", "2"
      # The test for 2.5 is currently broken because the value 2.5 is formatted
      # as "2". TODO: better default format string
      assert_expression_returns @olap, "-10.0", "-10"
    end

    # Java: FunctionTest#testStringLiteral
    it "double-quoted string literal returns string value" do
      # double-quoted string
      assert_expression_returns @olap, '"foobar"', "foobar"
    end
  end

  describe "Format" do
    # Java: FunctionTest#testFormatFixed
    it "Format with fixed format string" do
      assert_expression_returns @olap, 'Format(12.2, "#,##0.00")', "12.20"
    end

    # Java: FunctionTest#testFormatVariable
    it "Format with variable format string built by concatenation" do
      assert_expression_returns @olap, 'Format(1234.5, "#,#" || "#0.00")', "1,234.50"
    end

    # Java: FunctionTest#testFormatMember
    it "Format applied to a member" do
      assert_expression_returns @olap, 'Format([Store].[USA].[CA], "#,#" || "#0.00")', "74,748.00"
    end
  end

  describe "Caption" do
    # Java: FunctionTest#testDimensionCaption
    it "Dimension.Caption returns dimension caption" do
      assert_expression_returns @olap, "[Time].[1997].Dimension.Caption", "Time"
    end

    # Java: FunctionTest#testHierarchyCaption
    it "Hierarchy.Caption returns hierarchy caption" do
      assert_expression_returns @olap, "[Time].[1997].Hierarchy.Caption", "Time"
    end

    # Java: FunctionTest#testLevelCaption
    it "Level.Caption returns level caption" do
      assert_expression_returns @olap, "[Time].[1997].Level.Caption", "Year"
    end

    # Java: FunctionTest#testMemberCaption
    it "Member.Caption returns member caption" do
      assert_expression_returns @olap, "[Time].[1997].Caption", "1997"
    end
  end

  describe "Name" do
    # Java: FunctionTest#testDimensionName
    it "Dimension.Name returns dimension name" do
      assert_expression_returns @olap, "[Time].[1997].Dimension.Name", "Time"
    end

    # Java: FunctionTest#testHierarchyName
    it "Hierarchy.Name returns hierarchy name" do
      assert_expression_returns @olap, "[Time].[1997].Hierarchy.Name", "Time"
    end

    # Java: FunctionTest#testLevelName
    it "Level.Name returns level name" do
      assert_expression_returns @olap, "[Time].[1997].Level.Name", "Year"
    end

    # Java: FunctionTest#testMemberName
    it "Member.Name returns member name" do
      assert_expression_returns @olap, "[Time].[1997].Name", "1997"
      # dimension name
      assert_expression_returns @olap, "[Store].Name", "Store"
      # member name
      assert_expression_returns @olap, "[Store].DefaultMember.Name", "All Stores"
      # name of null member
      assert_expression_returns @olap, "[Store].Parent.Name", "#null"
    end
  end

  describe "UniqueName" do
    # Java: FunctionTest#testDimensionUniqueName
    it "Dimension.UniqueName returns dimension unique name" do
      assert_expression_returns @olap, "[Gender].DefaultMember.Dimension.UniqueName", "[Gender]"
    end

    # Java: FunctionTest#testHierarchyUniqueName
    it "Hierarchy.UniqueName returns hierarchy unique name" do
      assert_expression_returns @olap, "[Gender].DefaultMember.Hierarchy.UniqueName", "[Gender]"
    end

    # Java: FunctionTest#testLevelUniqueName
    it "Level.UniqueName returns level unique name" do
      assert_expression_returns @olap, "[Gender].DefaultMember.Level.UniqueName", "[Gender].[(All)]"
    end

    # Java: FunctionTest#testMemberUniqueName
    it "Member.UniqueName returns member unique name" do
      assert_expression_returns @olap, "[Gender].DefaultMember.UniqueName", "[Gender].[All Gender]"
    end

    # Java: FunctionTest#testMemberUniqueNameOfNull
    it "UniqueName of null member returns #null unique name" do
      assert_expression_returns @olap, "[Measures].[Unit Sales].FirstChild.UniqueName", "[Measures].[#null]"
    end
  end

  describe "Left" do
    # Java: FunctionTest#testLeftFunctionWithValidArguments
    it "Left with valid arguments filters matching members" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS," \
        "Left([Store].CURRENTMEMBER.Name, 4)=\"Bell\") on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end

    # Java: FunctionTest#testLeftFunctionWithLengthValueZero
    it "Left with length zero returns empty string" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS," \
        "Left([Store].CURRENTMEMBER.Name, 0)=\"\" And " \
        "[Store].CURRENTMEMBER.Name = \"Bellingham\") on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end

    # Java: FunctionTest#testLeftFunctionWithLengthValueEqualToStringLength
    it "Left with length equal to string length returns full string" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS," \
        "Left([Store].CURRENTMEMBER.Name, 10)=\"Bellingham\") " \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end

    # Java: FunctionTest#testLeftFunctionWithLengthMoreThanStringLength
    it "Left with length more than string length returns full string" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS," \
        "Left([Store].CURRENTMEMBER.Name, 20)=\"Bellingham\") " \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end

    # Java: FunctionTest#testLeftFunctionWithZeroLengthString
    it "Left on empty string returns empty string" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS,Left(\"\", 20)=\"\" " \
        "And [Store].CURRENTMEMBER.Name = \"Bellingham\") " \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end

    # Java: FunctionTest#testLeftFunctionWithNegativeLength
    it "Left with negative length raises StringIndexOutOfBoundsException" do
      error = assert_raises(Mondrian::OLAP::Error) do
        @olap.execute(
          "select filter([Store].MEMBERS," \
          "Left([Store].CURRENTMEMBER.Name, -20)=\"Bellingham\") " \
          "on 0 from sales")
      end
      assert error.root_cause_message.include?("StringIndexOutOfBoundsException"),
        "Expected root cause containing 'StringIndexOutOfBoundsException', got: #{error.root_cause_message}"
    end
  end

  describe "Mid" do
    # Java: FunctionTest#testMidFunctionWithValidArguments
    it "Mid with valid arguments extracts substring" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS," \
        "[Store].CURRENTMEMBER.Name = \"Bellingham\"" \
        "And Mid(\"Bellingham\", 4, 6) = \"lingha\")" \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end

    # Java: FunctionTest#testMidFunctionWithZeroLengthStringArgument
    it "Mid on empty string returns empty string" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS," \
        "[Store].CURRENTMEMBER.Name = \"Bellingham\"" \
        "And Mid(\"\", 4, 6) = \"\")" \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end

    # Java: FunctionTest#testMidFunctionWithLengthArgumentLargerThanStringLength
    it "Mid with length larger than string length returns remainder" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS," \
        "[Store].CURRENTMEMBER.Name = \"Bellingham\"" \
        "And Mid(\"Bellingham\", 4, 20) = \"lingham\")" \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end

    # Java: FunctionTest#testMidFunctionWithStartIndexGreaterThanStringLength
    it "Mid with start index greater than string length returns empty string" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS," \
        "[Store].CURRENTMEMBER.Name = \"Bellingham\"" \
        "And Mid(\"Bellingham\", 20, 2) = \"\")" \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end

    # Java: FunctionTest#testMidFunctionWithStartIndexZeroFails
    # Note: SSAS 2005 treats start<=0 as 1, therefore gives different
    # result for this query. We favor the VBA spec over SSAS 2005.
    it "Mid with start index zero raises error" do
      error = assert_raises(Mondrian::OLAP::Error) do
        @olap.execute(
          "select filter([Store].MEMBERS," \
          "[Store].CURRENTMEMBER.Name = \"Bellingham\"" \
          "And Mid(\"Bellingham\", 0, 2) = \"Be\")" \
          "on 0 from sales")
      end
      assert error.root_cause_message.include?("Invalid parameter. Start parameter of Mid function must be positive"),
        "Expected root cause containing 'Invalid parameter. Start parameter of Mid function must be positive', " \
        "got: #{error.root_cause_message}"
    end

    # Java: FunctionTest#testMidFunctionWithStartIndexOne
    it "Mid with start index one extracts from beginning" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS," \
        "[Store].CURRENTMEMBER.Name = \"Bellingham\"" \
        "And Mid(\"Bellingham\", 1, 2) = \"Be\")" \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end

    # Java: FunctionTest#testMidFunctionWithNegativeStartIndex
    it "Mid with negative start index raises error" do
      error = assert_raises(Mondrian::OLAP::Error) do
        @olap.execute(
          "select filter([Store].MEMBERS," \
          "[Store].CURRENTMEMBER.Name = \"Bellingham\"" \
          "And Mid(\"Bellingham\", -20, 2) = \"\")" \
          "on 0 from sales")
      end
      assert error.root_cause_message.include?("Invalid parameter. Start parameter of Mid function must be positive"),
        "Expected root cause containing 'Invalid parameter. Start parameter of Mid function must be positive', " \
        "got: #{error.root_cause_message}"
    end

    # Java: FunctionTest#testMidFunctionWithNegativeLength
    it "Mid with negative length raises error" do
      error = assert_raises(Mondrian::OLAP::Error) do
        @olap.execute(
          "select filter([Store].MEMBERS," \
          "[Store].CURRENTMEMBER.Name = \"Bellingham\"" \
          "And Mid(\"Bellingham\", 2, -2) = \"\")" \
          "on 0 from sales")
      end
      assert error.root_cause_message.include?("Invalid parameter. Length parameter of Mid function must be non-negative"),
        "Expected root cause containing 'Invalid parameter. Length parameter of Mid function must be non-negative', " \
        "got: #{error.root_cause_message}"
    end

    # Java: FunctionTest#testMidFunctionWithoutLength
    it "Mid without length returns remainder of string" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS," \
        "[Store].CURRENTMEMBER.Name = \"Bellingham\"" \
        "And Mid(\"Bellingham\", 2) = \"ellingham\")" \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end
  end

  describe "Len" do
    # Java: FunctionTest#testLenFunctionWithNonEmptyString
    it "Len of non-empty string returns character count" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS, " \
        "Len([Store].CURRENTMEMBER.Name) = 3) on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA]}
          Row #0: 266,773
        RESULT
    end

    # Java: FunctionTest#testLenFunctionWithAnEmptyString
    it "Len of empty string returns zero" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS,Len(\"\")=0 " \
        "And [Store].CURRENTMEMBER.Name = \"Bellingham\") " \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end

    # Java: FunctionTest#testLenFunctionWithNullString
    it "Len of null string returns zero" do
      # SSAS2005 returns 0
      assert_query_returns @olap,
        "with member [Measures].[Foo] as ' NULL '\n" \
        " member [Measures].[Bar] as ' len([Measures].[Foo]) '\n" \
        "select [Measures].[Bar] on 0\n" \
        "from [Warehouse and Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Bar]}
          Row #0: 0
        RESULT
      # same, but inline
      assert_expression_returns @olap, "len(null)", "0"
    end
  end

  describe "UCase" do
    # Java: FunctionTest#testUCaseWithNonEmptyString
    it "UCase converts string to uppercase" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS, " \
        " UCase([Store].CURRENTMEMBER.Name) = \"BELLINGHAM\") " \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end

    # Java: FunctionTest#testUCaseWithEmptyString
    it "UCase of empty string returns empty string" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS, " \
        " UCase(\"\") = \"\" " \
        "And [Store].CURRENTMEMBER.Name = \"Bellingham\") " \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end

    # Java: FunctionTest#testUCaseWithNullString
    it "UCase of string literal NULL does not match empty string" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS, " \
        " UCase(\"NULL\") = \"\" " \
        "And [Store].CURRENTMEMBER.Name = \"Bellingham\") " \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
        RESULT
    end

    # Java: FunctionTest#testUCaseWithNull
    it "UCase with NULL argument raises error about no matching function signature" do
      error = assert_raises(Mondrian::OLAP::Error) do
        @olap.execute(
          "select filter([Store].MEMBERS, " \
          " UCase(NULL) = \"\" " \
          "And [Store].CURRENTMEMBER.Name = \"Bellingham\") " \
          "on 0 from sales")
      end
      assert error.root_cause_message.include?("No method with the signature UCase(NULL) matches known functions."),
        "Expected root cause containing 'No method with the signature UCase(NULL) matches known functions.', " \
        "got: #{error.root_cause_message}"
    end
  end

  describe "InStr" do
    # Java: FunctionTest#testInStrFunctionWithValidArguments
    it "InStr finds substring at correct position" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS,InStr(\"Bellingham\", \"ingha\")=5 " \
        "And [Store].CURRENTMEMBER.Name = \"Bellingham\") " \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end

    # Java: FunctionTest#testInStrFunctionWithEmptyString1
    it "InStr searching in empty string returns zero" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS,InStr(\"\", \"ingha\")=0 " \
        "And [Store].CURRENTMEMBER.Name = \"Bellingham\") " \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end

    # Java: FunctionTest#testInStrFunctionWithEmptyString2
    it "InStr searching for empty string returns one" do
      assert_query_returns @olap,
        "select filter([Store].MEMBERS,InStr(\"Bellingham\", \"\")=1 " \
        "And [Store].CURRENTMEMBER.Name = \"Bellingham\") " \
        "on 0 from sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA].[Bellingham]}
          Row #0: 2,237
        RESULT
    end
  end

  describe "GetCaption" do
    # Java: FunctionTest#testGetCaptionUsingMemberDotCaption
    it "Member.Caption filters by caption value" do
      assert_query_returns @olap,
        "SELECT Filter(Store.allmembers, " \
        "[store].currentMember.caption = \"USA\") on 0 FROM SALES",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA]}
          Row #0: 266,773
        RESULT
    end
  end
end
