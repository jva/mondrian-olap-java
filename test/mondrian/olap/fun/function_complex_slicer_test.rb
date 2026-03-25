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
describe "ComplexSlicer" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  def root_cause_message(exception)
    cause = exception
    cause = cause.cause while cause.cause && cause.cause != cause
    cause.message
  end

  describe "with base members only" do
    # Java: FunctionTest#testComplexSlicer_BaseBase
    it "base members from two time periods in slicer" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        SELECT
        {[Measures].[Customer Count]} ON 0,
        {[Education Level].Members} ON 1
        FROM [Sales]
        WHERE {[Time].[1997].[Q2],[Time].[1998].[Q1]}
      MDX
        Axis #0:
        {[Time].[1997].[Q2]}
        {[Time].[1998].[Q1]}
        Axis #1:
        {[Measures].[Customer Count]}
        Axis #2:
        {[Education Level].[All Education Levels]}
        {[Education Level].[Bachelors Degree]}
        {[Education Level].[Graduate Degree]}
        {[Education Level].[High School Degree]}
        {[Education Level].[Partial College]}
        {[Education Level].[Partial High School]}
        Row #0: 2,973
        Row #1: 760
        Row #2: 178
        Row #3: 853
        Row #4: 273
        Row #5: 909
      RESULT
    end

    # Java: FunctionTest#testComplexSlicer_X_BaseBaseBase_BaseBase
    it "crossjoin of three time periods with two education levels in slicer" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        SELECT
        {[Measures].[Customer Count]} ON 0
        FROM [Sales]
        WHERE CROSSJOIN ({[Time].[1997].[Q1],[Time].[1997].[Q2],[Time].[1998].[Q1]} , {[Education Level].[Partial College],[Education Level].[Partial High School]})
      MDX
        Axis #0:
        {[Time].[1997].[Q1], [Education Level].[Partial College]}
        {[Time].[1997].[Q1], [Education Level].[Partial High School]}
        {[Time].[1997].[Q2], [Education Level].[Partial College]}
        {[Time].[1997].[Q2], [Education Level].[Partial High School]}
        {[Time].[1998].[Q1], [Education Level].[Partial College]}
        {[Time].[1998].[Q1], [Education Level].[Partial High School]}
        Axis #1:
        {[Measures].[Customer Count]}
        Row #0: 1,671
      RESULT
    end
  end

  describe "with WITH clause calculated members" do
    # Java: FunctionTest#testComplexSlicerWith_Calc
    it "WITH clause calculated member in slicer" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH
        MEMBER [Time].[H1 1997] AS 'Aggregate([Time].[1997].[Q1] : [Time].[1997].[Q2])', $member_scope = "CUBE", MEMBER_ORDINAL = 6
        SELECT
        {[Measures].[Customer Count]} ON 0,
        {[Education Level].Members} ON 1
        FROM [Sales]
        WHERE {[Time].[H1 1997]}
      MDX
        Axis #0:
        {[Time].[H1 1997]}
        Axis #1:
        {[Measures].[Customer Count]}
        Axis #2:
        {[Education Level].[All Education Levels]}
        {[Education Level].[Bachelors Degree]}
        {[Education Level].[Graduate Degree]}
        {[Education Level].[High School Degree]}
        {[Education Level].[Partial College]}
        {[Education Level].[Partial High School]}
        Row #0: 4,257
        Row #1: 1,109
        Row #2: 240
        Row #3: 1,237
        Row #4: 394
        Row #5: 1,277
      RESULT
    end

    # Java: FunctionTest#testComplexSlicerWith_CalcBase
    it "WITH clause calculated member and base member in slicer" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH
        MEMBER [Time].[H1 1997] AS 'Aggregate([Time].[1997].[Q1] : [Time].[1997].[Q2])', $member_scope = "CUBE", MEMBER_ORDINAL = 6
        SELECT
        {[Measures].[Customer Count]} ON 0,
        {[Education Level].Members} ON 1
        FROM [Sales]
        WHERE {[Time].[H1 1997],[Time].[1998].[Q1]}
      MDX
        Axis #0:
        {[Time].[H1 1997]}
        {[Time].[1998].[Q1]}
        Axis #1:
        {[Measures].[Customer Count]}
        Axis #2:
        {[Education Level].[All Education Levels]}
        {[Education Level].[Bachelors Degree]}
        {[Education Level].[Graduate Degree]}
        {[Education Level].[High School Degree]}
        {[Education Level].[Partial College]}
        {[Education Level].[Partial High School]}
        Row #0: 4,257
        Row #1: 1,109
        Row #2: 240
        Row #3: 1,237
        Row #4: 394
        Row #5: 1,277
      RESULT
    end

    # Java: FunctionTest#testComplexSlicerWith_Calc_Calc
    it "WITH clause two calculated members as tuple in slicer" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH
        MEMBER [Time].[H1 1997] AS 'Aggregate([Time].[1997].[Q1] : [Time].[1997].[Q2])', $member_scope = "CUBE", MEMBER_ORDINAL = 6
        MEMBER [Education Level].[Partial] AS 'Aggregate([Education Level].[Partial College]:[Education Level].[Partial High School])', $member_scope = "CUBE", MEMBER_ORDINAL = 7
        SELECT
        {[Measures].[Customer Count]} ON 0
        FROM [Sales]
        WHERE ([Time].[H1 1997],[Education Level].[Partial])
      MDX
        Axis #0:
        {[Time].[H1 1997], [Education Level].[Partial]}
        Axis #1:
        {[Measures].[Customer Count]}
        Row #0: 1,671
      RESULT
    end
  end

  describe "with schema-defined H1 1997 calculated member" do
    before(:all) do
      @olap_h1 = connection_with_modified_cube("Sales",
        calculated_members: <<~XML
          <CalculatedMember name="H1 1997" formula="Aggregate([Time].[1997].[Q1]:[Time].[1997].[Q2])" dimension="Time" />
        XML
      )
    end

    after(:all) do
      @olap_h1&.close
    end

    # Java: FunctionTest#testComplexSlicer_Calc
    it "schema calculated member in slicer" do
      assert_query_returns @olap_h1, <<~MDX, <<~RESULT
        SELECT
        {[Measures].[Customer Count]} ON 0,
        {[Education Level].Members} ON 1
        FROM [Sales]
        WHERE {[Time].[H1 1997]}
      MDX
        Axis #0:
        {[Time].[H1 1997]}
        Axis #1:
        {[Measures].[Customer Count]}
        Axis #2:
        {[Education Level].[All Education Levels]}
        {[Education Level].[Bachelors Degree]}
        {[Education Level].[Graduate Degree]}
        {[Education Level].[High School Degree]}
        {[Education Level].[Partial College]}
        {[Education Level].[Partial High School]}
        Row #0: 4,257
        Row #1: 1,109
        Row #2: 240
        Row #3: 1,237
        Row #4: 394
        Row #5: 1,277
      RESULT
    end

    # Java: FunctionTest#testComplexSlicer_CalcBase
    it "schema calculated member and base member in slicer" do
      assert_query_returns @olap_h1, <<~MDX, <<~RESULT
        SELECT
        {[Measures].[Customer Count]} ON 0,
        {[Education Level].Members} ON 1
        FROM [Sales]
        WHERE {[Time].[H1 1997],[Time].[1998].[Q1]}
      MDX
        Axis #0:
        {[Time].[H1 1997]}
        {[Time].[1998].[Q1]}
        Axis #1:
        {[Measures].[Customer Count]}
        Axis #2:
        {[Education Level].[All Education Levels]}
        {[Education Level].[Bachelors Degree]}
        {[Education Level].[Graduate Degree]}
        {[Education Level].[High School Degree]}
        {[Education Level].[Partial College]}
        {[Education Level].[Partial High School]}
        Row #0: 4,257
        Row #1: 1,109
        Row #2: 240
        Row #3: 1,237
        Row #4: 394
        Row #5: 1,277
      RESULT
    end

    # Java: FunctionTest#testComplexSlicer_BaseCalc
    it "base member and schema calculated member in slicer" do
      assert_query_returns @olap_h1, <<~MDX, <<~RESULT
        SELECT
        {[Measures].[Customer Count]} ON 0,
        {[Education Level].Members} ON 1
        FROM [Sales]
        WHERE {[Time].[1998].[Q1], [Time].[H1 1997]}
      MDX
        Axis #0:
        {[Time].[1998].[Q1]}
        {[Time].[H1 1997]}
        Axis #1:
        {[Measures].[Customer Count]}
        Axis #2:
        {[Education Level].[All Education Levels]}
        {[Education Level].[Bachelors Degree]}
        {[Education Level].[Graduate Degree]}
        {[Education Level].[High School Degree]}
        {[Education Level].[Partial College]}
        {[Education Level].[Partial High School]}
        Row #0: 4,257
        Row #1: 1,109
        Row #2: 240
        Row #3: 1,237
        Row #4: 394
        Row #5: 1,277
      RESULT
    end

    # Java: FunctionTest#testComplexSlicer_Calc_Base
    it "schema calculated member and base member as tuple in slicer" do
      assert_query_returns @olap_h1, <<~MDX, <<~RESULT
        SELECT
        {[Measures].[Customer Count]} ON 0
        FROM [Sales]
        WHERE ([Time].[H1 1997],[Education Level].[Partial College])
      MDX
        Axis #0:
        {[Time].[H1 1997], [Education Level].[Partial College]}
        Axis #1:
        {[Measures].[Customer Count]}
        Row #0: 394
      RESULT
    end

    # Java: FunctionTest#testComplexSlicer_X_Base_Base
    it "crossjoin of base time member with base education level in slicer" do
      assert_query_returns @olap_h1, <<~MDX, <<~RESULT
        SELECT
        {[Measures].[Customer Count]} ON 0
        FROM [Sales]
        WHERE CROSSJOIN ([Time].[1997].[Q1] , [Education Level].[Partial College])
      MDX
        Axis #0:
        {[Time].[1997].[Q1], [Education Level].[Partial College]}
        Axis #1:
        {[Measures].[Customer Count]}
        Row #0: 278
      RESULT
    end

    # Java: FunctionTest#testComplexSlicer_X_Calc_Base
    it "crossjoin of calculated time member with base education level in slicer" do
      assert_query_returns @olap_h1, <<~MDX, <<~RESULT
        SELECT
        {[Measures].[Customer Count]} ON 0
        FROM [Sales]
        WHERE CROSSJOIN ([Time].[H1 1997] , [Education Level].[Partial College])
      MDX
        Axis #0:
        {[Time].[H1 1997], [Education Level].[Partial College]}
        Axis #1:
        {[Measures].[Customer Count]}
        Row #0: 394
      RESULT
    end

    # Java: FunctionTest#testComplexSlicer_X_BaseBase_Base
    it "crossjoin of two base time members with base education level in slicer" do
      assert_query_returns @olap_h1, <<~MDX, <<~RESULT
        SELECT
        {[Measures].[Customer Count]} ON 0
        FROM [Sales]
        WHERE CROSSJOIN ({[Time].[1997].[Q1], [Time].[1997].[Q2]} , [Education Level].[Partial College])
      MDX
        Axis #0:
        {[Time].[1997].[Q1], [Education Level].[Partial College]}
        {[Time].[1997].[Q2], [Education Level].[Partial College]}
        Axis #1:
        {[Measures].[Customer Count]}
        Row #0: 394
      RESULT
    end

    # Java: FunctionTest#testComplexSlicer_X_CalcBase_Base
    it "crossjoin of calculated and base time members with base education level in slicer" do
      assert_query_returns @olap_h1, <<~MDX, <<~RESULT
        SELECT
        {[Measures].[Customer Count]} ON 0
        FROM [Sales]
        WHERE CROSSJOIN ({[Time].[H1 1997],[Time].[1998].[Q1]} , [Education Level].[Partial College])
      MDX
        Axis #0:
        {[Time].[H1 1997], [Education Level].[Partial College]}
        {[Time].[1998].[Q1], [Education Level].[Partial College]}
        Axis #1:
        {[Measures].[Customer Count]}
        Row #0: 394
      RESULT
    end

    # Java: FunctionTest#testComplexSlicer_X_CalcBase_BaseBase
    it "crossjoin of calculated and base time members with two base education levels in slicer" do
      assert_query_returns @olap_h1, <<~MDX, <<~RESULT
        SELECT
        {[Measures].[Customer Count]} ON 0
        FROM [Sales]
        WHERE CROSSJOIN ({[Time].[H1 1997],[Time].[1998].[Q1]} , {[Education Level].[Partial College],[Education Level].[Partial High School]})
      MDX
        Axis #0:
        {[Time].[H1 1997], [Education Level].[Partial College]}
        {[Time].[H1 1997], [Education Level].[Partial High School]}
        {[Time].[1998].[Q1], [Education Level].[Partial College]}
        {[Time].[1998].[Q1], [Education Level].[Partial High School]}
        Axis #1:
        {[Measures].[Customer Count]}
        Row #0: 1,671
      RESULT
    end
  end

  describe "with schema-defined H1 1997 and Partial calculated members" do
    before(:all) do
      @olap_h1_partial = connection_with_modified_cube("Sales",
        calculated_members: <<~XML
          <CalculatedMember name="H1 1997" formula="Aggregate([Time].[1997].[Q1]:[Time].[1997].[Q2])" dimension="Time" />
          <CalculatedMember name="Partial" formula="Aggregate([Education Level].[Partial College]:[Education Level].[Partial High School])" dimension="Education Level" />
        XML
      )
    end

    after(:all) do
      @olap_h1_partial&.close
    end

    # Java: FunctionTest#testComplexSlicer_Calc_Calc
    it "two schema calculated members as tuple in slicer" do
      assert_query_returns @olap_h1_partial, <<~MDX, <<~RESULT
        SELECT
        {[Measures].[Customer Count]} ON 0
        FROM [Sales]
        WHERE ([Time].[H1 1997],[Education Level].[Partial])
      MDX
        Axis #0:
        {[Time].[H1 1997], [Education Level].[Partial]}
        Axis #1:
        {[Measures].[Customer Count]}
        Row #0: 1,671
      RESULT
    end

    # Java: FunctionTest#testComplexSlicer_X_Calc_Calc
    it "crossjoin of two schema calculated members in slicer" do
      assert_query_returns @olap_h1_partial, <<~MDX, <<~RESULT
        SELECT
        {[Measures].[Customer Count]} ON 0
        FROM [Sales]
        WHERE CROSSJOIN ([Time].[H1 1997] , [Education Level].[Partial])
      MDX
        Axis #0:
        {[Time].[H1 1997], [Education Level].[Partial]}
        Axis #1:
        {[Measures].[Customer Count]}
        Row #0: 1,671
      RESULT
    end

    # Java: FunctionTest#testComplexSlicer_Calc_ComplexAxis
    it "calculated member in slicer with calculated and base members on axis" do
      assert_query_returns @olap_h1_partial, <<~MDX, <<~RESULT
        SELECT
        {[Measures].[Customer Count]} ON 0,
        {[Time].[H1 1997], [Time].[1997].[Q1]} ON 1
        FROM [Sales]
        WHERE {[Education Level].[Partial]}
      MDX
        Axis #0:
        {[Education Level].[Partial]}
        Axis #1:
        {[Measures].[Customer Count]}
        Axis #2:
        {[Time].[H1 1997]}
        {[Time].[1997].[Q1]}
        Row #0: 1,671
        Row #1: 1,173
      RESULT
    end
  end

  describe "unsupported calculated member in compound predicate" do
    # Java: FunctionTest#testComplexSlicer_Unsupported
    it "raises error for non-aggregate calculated member in compound slicer" do
      olap_unsupported = connection_with_modified_cube("Sales",
        calculated_members: <<~XML
          <CalculatedMember name="H1 1997" formula="([Time].[1997].[Q1] - [Time].[1997].[Q2])" dimension="Time" />
        XML
      )
      begin
        error = assert_raises(Mondrian::OLAP::Error) do
          olap_unsupported.execute(
            "SELECT " \
            "{[Measures].[Customer Count]} ON 0, " \
            "{[Education Level].Members} ON 1 " \
            "FROM [Sales] " \
            "WHERE {[Time].[H1 1997],[Time].[1998].[Q1]}"
          )
        end
        assert_match(/Calculated member 'H1 1997' is not supported within a compound predicate/,
          root_cause_message(error))
      ensure
        olap_unsupported.close
      end
    end
  end
end
