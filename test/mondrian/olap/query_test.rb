# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 1998-2005 Julian Hyde
# Copyright (C) 2005-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/olap/QueryTest.java
describe "Query" do
  before(:all) do
    create_olap_connection

    cell_properties = [
      Java::MondrianOlap::CellProperty.new(Java::MondrianOlap::Id::Segment.toList("Value")),
      Java::MondrianOlap::CellProperty.new(Java::MondrianOlap::Id::Segment.toList("Formatted_Value")),
      Java::MondrianOlap::CellProperty.new(Java::MondrianOlap::Id::Segment.toList("Format_String"))
    ].to_java(Java::MondrianOlap::QueryPart)

    axes = Java::MondrianOlap::QueryAxis[0].new
    formulas = Java::MondrianOlap::Formula[0].new

    connection = @olap.raw_mondrian_connection
    statement = connection.getInternalStatement
    begin
      @query_with_cell_properties = Java::MondrianOlap::Query.new(
        statement, formulas, axes, "Sales", nil, cell_properties, false
      )
      @query_without_cell_properties = Java::MondrianOlap::Query.new(
        statement, formulas, axes, "Sales", nil,
        Java::MondrianOlap::QueryPart[0].new, false
      )
    ensure
      statement.close
    end
  end

  # Java: QueryTest#testHasCellPropertyWhenQueryHasCellProperties
  it "hasCellProperty returns true for present property and false for absent" do
    assert_equal true, @query_with_cell_properties.hasCellProperty("Value")
    assert_equal false, @query_with_cell_properties.hasCellProperty("Language")
  end

  # Java: QueryTest#testIsCellPropertyEmpty
  it "isCellPropertyEmpty returns true when query has no cell properties" do
    assert_equal true, @query_without_cell_properties.isCellPropertyEmpty
  end
end
