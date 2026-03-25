# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2001-2005 Julian Hyde
# Copyright (C) 2005-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/olap/fun/SetFunDefTest.java
describe "SetFunDef" do
  before(:all) do
    create_olap_connection
  end

  private

  def assert_query_fails_in_set_validation(query)
    error = assert_raises(Mondrian::OLAP::Error) { @olap.execute(query) }
    assert_equal "Mondrian Error:All arguments to function '{}' must have same hierarchy.",
      root_cause_message(error)
  end

  def root_cause_message(exception)
    cause = exception
    cause = cause.cause while cause.cause && cause.cause != cause
    cause.message
  end

  public

  # Java: SetFunDefTest#testSetWithMembersFromDifferentHierarchies
  it "rejects set with members from different hierarchies" do
    assert_query_fails_in_set_validation(
      "with member store.x as " \
      "'{[Gender].[M],[Store].[USA].[CA]}' " \
      " SELECT store.x on 0, [measures].[customer count] on 1 from sales")
  end

  # Java: SetFunDefTest#testSetWith2TuplesWithDifferentHierarchies
  it "rejects set with 2 tuples from different hierarchies" do
    assert_query_fails_in_set_validation(
      "with member store.x as '{([Gender].[M],[Store].[All Stores].[USA].[CA])," \
      "([Store].[USA].[OR],[Gender].[F])}'\n" \
      " SELECT store.x on 0, [measures].[customer count] on 1 from sales")
  end
end
