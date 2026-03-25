# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (c) 2015-2017 Hitachi Vantara.
# Copyright (C) 2026 eazyBI
# All rights reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/olap/fun/PropertiesFunctionTest.java
describe "PropertiesFunction" do
  before(:all) do
    create_olap_connection
    @connection = @olap.raw_mondrian_connection
  end

  def verify_member_caption_property(expression, expected_caption)
    mdx = "WITH MEMBER [Measures].[Foo] as #{expression} SELECT {[Measures].[Foo]} ON COLUMNS from [Sales]"
    query = @connection.parseQuery(mdx)
    refute_nil query

    resolved_expression = query.getFormulas[0].getExpression
    refute_nil resolved_expression
    assert_equal Java::MondrianOlap::Category::String, resolved_expression.getCategory
    assert_equal Java::MondrianOlapType::StringType.new, resolved_expression.getType

    result = @connection.execute(query)
    refute_nil result
    assert_equal expected_caption, result.getCell([0].to_java(:int)).getFormattedValue
  end

  # The "Time" dimension in FoodMart schema contains two hierarchies.
  # The first hierarchy doesn't have a name. By default, a hierarchy has the same
  # name as its dimension, so the first hierarchy is called "Time".
  describe "Time dimension and hierarchy" do
    # Java: PropertiesFunctionTest#testMemberCaptionPropertyOnTimeDimension
    it "MEMBER_CAPTION on Time dimension" do
      verify_member_caption_property("[Time].Properties('MEMBER_CAPTION')", "1997")
    end

    # Java: PropertiesFunctionTest#testCurrentMemberCaptionPropertyOnTimeDimension
    it "CurrentMember MEMBER_CAPTION on Time dimension" do
      verify_member_caption_property("[Time].CurrentMember.Properties('MEMBER_CAPTION')", "1997")
    end

    # Java: PropertiesFunctionTest#testMemberCaptionPropertyOnTimeHierarchy
    it "MEMBER_CAPTION on Time hierarchy" do
      verify_member_caption_property("[Time].[Time].Properties('MEMBER_CAPTION')", "1997")
    end

    # Java: PropertiesFunctionTest#testCurrentMemberCaptionPropertyOnTimeHierarchy
    it "CurrentMember MEMBER_CAPTION on Time hierarchy" do
      verify_member_caption_property("[Time].[Time].CurrentMember.Properties('MEMBER_CAPTION')", "1997")
    end

    # Java: PropertiesFunctionTest#testGenerateWithMemberCaptionPropertyOnTimeDimension
    it "Generate with MEMBER_CAPTION on Time dimension" do
      verify_member_caption_property(
        "Generate([Time].CurrentMember, [Time].CurrentMember.Properties('MEMBER_CAPTION'))", "1997")
    end

    # Java: PropertiesFunctionTest#testGenerateWithMemberCaptionPropertyOnTimeHierarchy
    it "Generate with MEMBER_CAPTION on Time hierarchy" do
      verify_member_caption_property(
        "Generate([Time].CurrentMember, [Time].[Time].CurrentMember.Properties('MEMBER_CAPTION'))", "1997")
    end
  end

  # Below the tests for the "Time.Weekly" hierarchy.
  describe "Time.Weekly hierarchy" do
    # Java: PropertiesFunctionTest#testMemberCaptionPropertyOnWeeklyHierarchy
    it "MEMBER_CAPTION on Weekly hierarchy" do
      verify_member_caption_property("[Time.Weekly].Properties('MEMBER_CAPTION')", "All Time.Weeklys")
    end

    # Java: PropertiesFunctionTest#testCurrentMemberCaptionPropertyOnWeeklyHierarchy
    it "CurrentMember MEMBER_CAPTION on Weekly hierarchy" do
      verify_member_caption_property("[Time.Weekly].CurrentMember.Properties('MEMBER_CAPTION')", "All Time.Weeklys")
    end

    # Java: PropertiesFunctionTest#testGenerateWithMemberCaptionPropertyOnWeeklyHierarchy
    it "Generate with MEMBER_CAPTION on Weekly hierarchy" do
      verify_member_caption_property(
        "Generate([Time.Weekly].CurrentMember, [Time.Weekly].CurrentMember.Properties('MEMBER_CAPTION'))",
        "All Time.Weeklys")
    end
  end

  # The "Store" dimension in FoodMart schema contains only one hierarchy that has
  # no name. So its name is "Store".
  describe "Store dimension and hierarchy" do
    # Java: PropertiesFunctionTest#testMemberCaptionPropertyOnStoreDimension
    it "MEMBER_CAPTION on Store dimension" do
      verify_member_caption_property("[Store].Properties('MEMBER_CAPTION')", "All Stores")
    end

    # Java: PropertiesFunctionTest#testCurrentMemberCaptionPropertyOnStoreDimension
    it "CurrentMember MEMBER_CAPTION on Store dimension" do
      verify_member_caption_property("[Store].CurrentMember.Properties('MEMBER_CAPTION')", "All Stores")
    end

    # Java: PropertiesFunctionTest#testMemberCaptionPropertyOnStoreHierarchy
    it "MEMBER_CAPTION on Store hierarchy" do
      verify_member_caption_property("[Store].[Store].Properties('MEMBER_CAPTION')", "All Stores")
    end

    # Java: PropertiesFunctionTest#testCurrentMemberCaptionPropertyOnStoreHierarchy
    it "CurrentMember MEMBER_CAPTION on Store hierarchy" do
      verify_member_caption_property("[Store].[Store].CurrentMember.Properties('MEMBER_CAPTION')", "All Stores")
    end

    # Java: PropertiesFunctionTest#testGenerateWithMemberCaptionPropertyOnStoreDimension
    it "Generate with MEMBER_CAPTION on Store dimension" do
      verify_member_caption_property(
        "Generate([Store].CurrentMember, [Store].CurrentMember.Properties('MEMBER_CAPTION'))", "All Stores")
    end

    # Java: PropertiesFunctionTest#testGenerateWithMemberCaptionPropertyOnStoreHierarchy
    it "Generate with MEMBER_CAPTION on Store hierarchy" do
      verify_member_caption_property(
        "Generate([Store].CurrentMember, [Store].[Store].CurrentMember.Properties('MEMBER_CAPTION'))", "All Stores")
    end
  end
end
