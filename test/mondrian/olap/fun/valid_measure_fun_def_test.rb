# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/olap/fun/ValidMeasureFunDefTest.java
describe "ValidMeasureFunDef" do
  before(:all) do
    create_olap_connection
  end

  # Java: ValidMeasureFunDefTest#testSecondHierarchyInDimension
  # Test for MONDRIAN-1032 issue.
  it "handles second hierarchy in dimension via ValidMeasure" do
    schema = <<~XML
      <?xml version="1.0"?>
      <Schema name="FoodMart">
        <Dimension name="Product">
          <Hierarchy hasAll="true" primaryKey="product_id" primaryKeyTable="product">
            <Join leftKey="product_class_id" rightKey="product_class_id">
              <Table name="product"/>
              <Table name="product_class"/>
            </Join>
            <Level name="Product Name" table="product" column="product_name" uniqueMembers="true"/>
          </Hierarchy>
          <Hierarchy name="BrandOnly" hasAll="true" primaryKey="product_id" primaryKeyTable="product">
            <Join leftKey="product_class_id" rightKey="product_class_id">
              <Table name="product"/>
              <Table name="product_class"/>
            </Join>
            <Level name="Product" table="product" column="brand_name" uniqueMembers="false"/>
          </Hierarchy>
        </Dimension>
        <Cube name="Sales" defaultMeasure="Unit Sales">
          <Table name="sales_fact_1997"/>
          <DimensionUsage name="Product" source="Product" foreignKey="product_id"/>
        </Cube>
        <Cube name="Sales 1" cache="true" enabled="true">
          <Table name="sales_fact_1997"/>
          <Measure name="Unit Sales1" column="unit_sales" aggregator="sum" formatString="Standard"/>
        </Cube>
        <VirtualCube enabled="true" name="Virtual Cube">
          <VirtualCubeDimension cubeName="Sales" highCardinality="false" name="Product"/>
          <VirtualCubeMeasure cubeName="Sales 1" name="[Measures].[Unit Sales1]" visible="true"/>
        </VirtualCube>
      </Schema>
    XML

    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    olap = Mondrian::OLAP::Connection.create(params)
    begin
      assert_query_returns olap,
        "with member [Measures].[TestValid] as ValidMeasure([Measures].[Unit Sales1])\n" \
        "select [Measures].[TestValid] on columns,\n" \
        "TopCount([Product.BrandOnly].[Product].members, 1) on rows\n" \
        "from [Virtual Cube]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[TestValid]}
          Axis #2:
          {[Product.BrandOnly].[ADJ]}
          Row #0: 266,773
        RESULT
    ensure
      olap.close
    end
  end

  # Java: ValidMeasureFunDefTest#testValidMeasureWithNullTuple
  it "returns null for ValidMeasure with null tuple" do
    assert_query_returns @olap,
      "with member measures.vm as " \
      "'ValidMeasure((Measures.[Unit Sales], Store.[All Stores].Parent))' " \
      "select measures.vm on 0 from [warehouse and sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[vm]}
        Row #0:
      RESULT
  end
end
