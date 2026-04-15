# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2015-2017 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "aggregation_on_invalid_role_test"

# Java: mondrian/rolap/agg/AggregationOnInvalidRoleWhenNotIgnoringTest.java
describe "AggregationOnInvalidRoleWhenNotIgnoring" do
  before(:all) do
    temp_olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
    @jdbc_connection = temp_olap.raw_mondrian_connection.getDataSource.getConnection
    temp_olap.close
    create_mondrian_2225_tables(@jdbc_connection)
  end

  after(:all) do
    drop_mondrian_2225_tables(@jdbc_connection)
    @jdbc_connection&.close
  end

  # Java: AggregationOnInvalidRoleWhenNotIgnoringTest#test_ThrowsException_WhenNonIgnoringInvalidMembers
  it "throws exception when not ignoring invalid members" do
    with_properties(UseAggregates: true, ReadAggregates: true, IgnoreInvalidMembers: false) do
      Mondrian::OLAP::Connection.flush_schema_cache
      schema = build_mondrian_2225_schema(MONDRIAN_2225_CUBE, MONDRIAN_2225_ROLE)
      params = CONNECTION_PARAMS.merge(catalog_content: schema, role: "Test")
      params.delete(:catalog)
      assert_raises(Mondrian::OLAP::Error) do
        olap = Mondrian::OLAP::Connection.create(params)
        begin
          olap.execute(MONDRIAN_2225_ANALYZER_QUERY)
        ensure
          olap.close
        end
      end
    end
  end
end
