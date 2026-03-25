# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (c) 2002-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/olap/fun/VisualTotalsTest.java
describe "VisualTotals" do
  before(:all) do
    create_olap_connection
  end

  # Java: VisualTotalsTest#testSubstituteEmpty
  it "substitute with empty pattern returns empty" do
    assert_equal "", Java::MondrianOlapFun::VisualTotalsFunDef.substitute("", "anything")
  end

  # Java: VisualTotalsTest#testSubstituteOneStarOnly
  it "substitute with single star returns name" do
    assert_equal "anything", Java::MondrianOlapFun::VisualTotalsFunDef.substitute("*", "anything")
  end

  # Java: VisualTotalsTest#testSubstituteOneStarBegin
  it "substitute with star at beginning" do
    assert_equal "Grease is the word.",
      Java::MondrianOlapFun::VisualTotalsFunDef.substitute("* is the word.", "Grease")
  end

  # Java: VisualTotalsTest#testSubstituteOneStarEnd
  it "substitute with star at end" do
    assert_equal "Lies, damned lies, and statistics!",
      Java::MondrianOlapFun::VisualTotalsFunDef.substitute("Lies, damned lies, and *!", "statistics")
  end

  # Java: VisualTotalsTest#testSubstituteTwoStars
  it "substitute with two stars escapes to literal star" do
    assert_equal "*", Java::MondrianOlapFun::VisualTotalsFunDef.substitute("**", "anything")
  end

  # Java: VisualTotalsTest#testSubstituteCombined
  it "substitute with combined stars and escapes" do
    assert_equal "disclaimer: see small print** for disclaimer",
      Java::MondrianOlapFun::VisualTotalsFunDef.substitute("*: see small print**** for *", "disclaimer")
  end

  # Java: VisualTotalsTest#testDrillthroughVisualTotal
  # Test case for MONDRIAN-925, "VisualTotals + drillthrough throws Exception".
  it "drillthrough on visual total returns null, on detail returns result" do
    statement = @olap.raw_connection.createStatement
    cell_set = statement.executeOlapQuery(
      "select {[Measures].[Unit Sales]} on columns, " \
      "{VisualTotals(" \
      "    {[Product].[Food].[Baked Goods].[Bread]," \
      "     [Product].[Food].[Baked Goods].[Bread].[Bagels]," \
      "     [Product].[Food].[Baked Goods].[Bread].[Muffins]}," \
      "     \"**Subtotal - *\")} on rows " \
      "from [Sales]")

    positions = cell_set.getAxes.get(1).getPositions

    # Visual total member - drillthrough should return null
    cell = cell_set.getCell(java.util.Arrays.asList(java.lang.Integer.new(0), java.lang.Integer.new(0)))
    member = positions.get(0).getMembers.get(0)
    assert_equal "*Subtotal - Bread", member.getName
    result_set = cell.drillThrough
    assert_nil result_set

    # Detail member - drillthrough should return a result set
    cell = cell_set.getCell(java.util.Arrays.asList(java.lang.Integer.new(0), java.lang.Integer.new(1)))
    member = positions.get(1).getMembers.get(0)
    assert_equal "Bagels", member.getName
    result_set = cell.drillThrough
    refute_nil result_set
    result_set.close
  end

  # Java: VisualTotalsTest#testVisualTotalCaptionBug
  # Test case for MONDRIAN-1279, "VisualTotals name only applies to member name not caption".
  it "visual total pattern applies to both name and caption" do
    statement = @olap.raw_connection.createStatement
    cell_set = statement.executeOlapQuery(
      "select {[Measures].[Unit Sales]} on columns, " \
      "VisualTotals(" \
      "    {[Product].[Food].[Baked Goods].[Bread]," \
      "     [Product].[Food].[Baked Goods].[Bread].[Bagels]," \
      "     [Product].[Food].[Baked Goods].[Bread].[Muffins]}," \
      "     \"**Subtotal - *\") on rows " \
      "from [Sales]")

    positions = cell_set.getAxes.get(1).getPositions
    member = positions.get(0).getMembers.get(0)
    assert_equal "*Subtotal - Bread", member.getName
    assert_equal "*Subtotal - Bread", member.getCaption
  end

  # Java: VisualTotalsTest#testVisualTotalsAggregatedMemberBug
  # Test case for MONDRIAN-939, "VisualTotals returning incorrect values with aggregate members".
  it "returns correct values with aggregate members" do
    assert_query_returns @olap,
      " with  member [Gender].[YTD] as 'AGGREGATE(YTD(),[Gender].[M])'" \
      "  select " \
      " {[Time].[1997]," \
      " [Time].[1997].[Q1],[Time].[1997].[Q2],[Time].[1997].[Q3],[Time].[1997].[Q4]} ON COLUMNS, " \
      " {[Gender].[M],[Gender].[YTD]} ON ROWS" \
      " FROM [Sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Time].[1997]}
        {[Time].[1997].[Q1]}
        {[Time].[1997].[Q2]}
        {[Time].[1997].[Q3]}
        {[Time].[1997].[Q4]}
        Axis #2:
        {[Gender].[M]}
        {[Gender].[YTD]}
        Row #0: 135,215
        Row #0: 33,381
        Row #0: 31,618
        Row #0: 33,249
        Row #0: 36,967
        Row #1: 135,215
        Row #1: 33,381
        Row #1: 64,999
        Row #1: 98,248
        Row #1: 135,215
      RESULT
  end
end
