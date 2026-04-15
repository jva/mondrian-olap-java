# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2015-2017 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/RolapNativeSqlInjectionTest.java
describe "RolapNativeSqlInjectionTest" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  def root_cause_message(exception)
    cause = exception
    cause = cause.cause while cause.cause && cause.cause != cause
    cause.message
  end

  # Java: RolapNativeSqlInjectionTest#testMondrian2436
  it "rejects SQL injection attempt in native filter condition" do
    mdx = <<~MDX
      select {[Measures].[Store Sales]} on columns,
      filter([Customers].[Name].Members, (([Measures].[Store Sales]) > '(select 1000)')) on rows
      from [Sales]
    MDX

    with_properties(EnableNativeFilter: true, EnableNativeCrossJoin: true) do
      olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        error = assert_raises(Mondrian::OLAP::Error) { olap.execute(mdx) }
        assert_equal "Expected to get decimal, but got (select 1000)", root_cause_message(error)
      ensure
        olap.close
      end
    end
  end
end
