# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2021 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/RolapEvaluatorTest.java
describe "RolapEvaluator" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Execute MDX via the internal Mondrian API and return the RolapResult.
  def execute_internal(mdx)
    connection = @olap.raw_mondrian_connection
    query = connection.parseQuery(mdx)
    connection.execute(query)
  end

  # Access the package-private getRootEvaluator() method on RolapResult via reflection.
  def get_root_evaluator(result)
    method = result.getClass.getDeclaredMethod("getRootEvaluator")
    method.setAccessible(true)
    method.invoke(result)
  end

  # Quote a table.column identifier pair using the current dialect.
  def q(table, column)
    dialect = @olap.raw_mondrian_connection.getSchema.getDialect
    dialect.quoteIdentifier(table, column)
  end

  # Java: RolapEvaluatorTest#testGetSlicerPredicateInfo
  it "slicer predicate info for compound crossjoin" do
    result = execute_internal(
      "select from sales " \
      "WHERE {[Time].[1997].Q1, [Time].[1997].Q2} " \
      "* { Store.[USA].[CA], Store.[USA].[WA]}"
    )
    evaluator = get_root_evaluator(result)
    slicer_predicate_info = evaluator.getSlicerPredicateInfo

    store_state = q("store", "store_state")
    the_year = q("time_by_day", "the_year")
    quarter = q("time_by_day", "quarter")

    expected = "(((#{store_state}, #{the_year}, #{quarter}) in " \
      "(('CA', 1997, 'Q1'), ('WA', 1997, 'Q1'), ('CA', 1997, 'Q2'), ('WA', 1997, 'Q2'))))"
    assert_equal expected, slicer_predicate_info.getPredicateString
    assert_equal true, slicer_predicate_info.isSatisfiable
  end

  # Java: RolapEvaluatorTest#testSlicerPredicateUnsatisfiable
  # Commented out in the original Java test.
  # it "slicer predicate unsatisfiable for virtual cube" do
  #   skip "Commented out in original Java test"
  # end

  # Java: RolapEvaluatorTest#testListColumnPredicateInfo
  it "list column predicate info for product family slicer" do
    result = execute_internal(
      "select from sales " \
      "WHERE {[Product].[Drink],[Product].[Non-Consumable]} "
    )
    evaluator = get_root_evaluator(result)
    slicer_predicate_info = evaluator.getSlicerPredicateInfo

    product_family = q("product_class", "product_family")

    expected = "#{product_family} in ('Drink', 'Non-Consumable')"
    assert_equal expected, slicer_predicate_info.getPredicateString
    assert_equal true, slicer_predicate_info.isSatisfiable
  end

  # Java: RolapEvaluatorTest#testOrPredicateInfo
  it "or predicate info for mixed-level product slicer" do
    result = execute_internal(
      "select from sales " \
      "WHERE {[Product].[Drink].[Beverages],[Product].[Food].[Produce],[Product].[Non-Consumable]} "
    )
    evaluator = get_root_evaluator(result)
    slicer_predicate_info = evaluator.getSlicerPredicateInfo

    product_family = q("product_class", "product_family")
    product_department = q("product_class", "product_department")

    expected = "((((#{product_family}, #{product_department}) in " \
      "(('Drink', 'Beverages'), ('Food', 'Produce')))) or #{product_family} = 'Non-Consumable')"
    assert_equal expected, slicer_predicate_info.getPredicateString
    assert_equal true, slicer_predicate_info.isSatisfiable
  end
end
