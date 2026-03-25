# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/olap/NullMemberRepresentationTest.java
describe "NullMemberRepresentation" do
  before(:all) do
    create_olap_connection
  end

  def null_member_representation
    Java::MondrianRolap::RolapUtil.mdxNullLiteral
  end

  # Java: NullMemberRepresentationTest#testClosingPeriodMemberLeafWithCustomNullRepresentation
  it "ClosingPeriod on leaf returns null member with custom representation" do
    assert_query_returns @olap,
      "with member [Measures].[Foo] as ' ClosingPeriod().uniquename '\n" \
      "select {[Measures].[Foo]} on columns,\n" \
      "  {[Time].[1997],\n" \
      "   [Time].[1997].[Q2],\n" \
      "   [Time].[1997].[Q2].[4]} on rows\n" \
      "from Sales",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Foo]}
        Axis #2:
        {[Time].[1997]}
        {[Time].[1997].[Q2]}
        {[Time].[1997].[Q2].[4]}
        Row #0: [Time].[1997].[Q4]
        Row #1: [Time].[1997].[Q2].[6]
        Row #2: [Time].[#{null_member_representation}]
      RESULT
  end

  # Java: NullMemberRepresentationTest#testItemMemberWithCustomNullMemberRepresentation
  it "Item with out-of-range index returns null member" do
    assert_expression_returns @olap,
      "[Time].[1997].Children.Item(6).UniqueName",
      "[Time].[#{null_member_representation}]"

    assert_expression_returns @olap,
      "[Time].[1997].Children.Item(-1).UniqueName",
      "[Time].[#{null_member_representation}]"
  end

  # Java: NullMemberRepresentationTest#testNullMemberWithCustomRepresentation
  it "Parent of root member returns null member" do
    assert_expression_returns @olap,
      "[Gender].[All Gender].Parent.UniqueName",
      "[Gender].[#{null_member_representation}]"

    assert_expression_returns @olap,
      "[Gender].[All Gender].Parent.Name",
      null_member_representation
  end
end
