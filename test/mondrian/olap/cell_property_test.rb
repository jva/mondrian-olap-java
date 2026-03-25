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

# Java: mondrian/olap/CellPropertyTest.java
describe "CellProperty" do
  before do
    segments = Java::MondrianOlap::Id::Segment.toList("Format_String")
    @cell_property = Java::MondrianOlap::CellProperty.new(segments)
  end

  # Java: CellPropertyTest#testIsNameEquals
  it "isNameEquals matches exact name" do
    assert_equal true, @cell_property.isNameEquals("Format_String")
  end

  # Java: CellPropertyTest#testIsNameEqualsDoesCaseInsensitiveMatch
  it "isNameEquals does case insensitive match" do
    assert_equal true, @cell_property.isNameEquals("format_string")
  end

  # Java: CellPropertyTest#testIsNameEqualsParameterShouldNotBeQuoted
  it "isNameEquals does not match when parameter is quoted" do
    assert_equal false, @cell_property.isNameEquals("[Format_String]")
  end
end
