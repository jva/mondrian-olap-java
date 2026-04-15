# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2015-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/TopCountWithTwoParamsVersusHeadTest.java
#
# According to MSDN, when TOPCOUNT function is called with two parameters
# it should mimic the behaviour of HEAD function.
# These tests compare results of both functions called with same parameters.
describe "TopCountWithTwoParamsVersusHeadTest" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Executes the TOPCOUNT query and the equivalent HEAD query (by replacing
  # TOPCOUNT with HEAD), then asserts both produce identical results.
  # Flushes the schema cache between the two executions, matching the
  # Java test's behavior.
  def assert_results_are_equal(test_case, topcount_query)
    raise ArgumentError,
      "'TOPCOUNT' was not found. Please ensure you are using upper case:\n\t\t#{topcount_query}" \
      unless topcount_query.include?("TOPCOUNT")

    head_query = topcount_query.gsub("TOPCOUNT", "HEAD")

    topcount_result = format_result(@olap.execute(topcount_query))
    Mondrian::OLAP::Connection.flush_schema_cache
    head_result = format_result(@olap.execute(head_query))

    assert_equal topcount_result, head_result,
      "[#{test_case}]: TOPCOUNT() and HEAD() results of the query differ. The query:\n\t\t#{topcount_query}"
  end

  # Java: TopCountWithTwoParamsVersusHeadTest#test_States
  it "states" do
    assert_results_are_equal(
      "States",
      "SELECT TOPCOUNT([Customers].[State Province].members, 3) ON COLUMNS " \
      "FROM [Sales] "
    )
  end

  # Java: TopCountWithTwoParamsVersusHeadTest#test_Cities
  it "cities" do
    assert_results_are_equal(
      "Cities",
      "SELECT TOPCOUNT([Customers].[City].members, 30) ON COLUMNS " \
      "FROM [Sales] "
    )
  end

  # Java: TopCountWithTwoParamsVersusHeadTest#test_ShowsNotMoreThanExist
  it "shows not more than exist" do
    assert_results_are_equal(
      "Not more than exists",
      "SELECT TOPCOUNT([Customers].[Country].members, 5) ON COLUMNS " \
      "FROM [Sales] "
    )
  end

  # Java: TopCountWithTwoParamsVersusHeadTest#test_DoesNotIgnoreNonEmpty
  it "does not ignore NON EMPTY" do
    assert_results_are_equal(
      "Does not ignore NON EMPTY",
      "SELECT NON EMPTY TOPCOUNT([Customers].[State Province].members, 3) ON COLUMNS " \
      "FROM [Sales] "
    )
  end
end
