# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (c) 2002-2017 Hitachi Vantara. All rights reserved.
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/olap4j/XmlaExtraTest.java
describe "XmlaExtra" do
  Util = Java::MondrianOlap::Util
  RolapConnectionProperties = Java::MondrianRolap::RolapConnectionProperties

  # Java: XmlaExtraTest#testGetDataSourceDoesntLeakPassword
  it "PropertyList.remove strips Jdbc, JdbcUser, and JdbcPassword" do
    sensitive_dsi = "Provider=Mondrian;Jdbc=foo;JdbcPassword=bar;JdbcUser=bacon"
    properties = Util.parseConnectString(sensitive_dsi)

    # Confirm the sensitive properties are present before removal
    refute_nil properties.get(RolapConnectionProperties::Jdbc.name)
    refute_nil properties.get(RolapConnectionProperties::JdbcUser.name)
    refute_nil properties.get(RolapConnectionProperties::JdbcPassword.name)

    # Remove them — same logic as MondrianOlap4jExtra.getDataSources
    removed = properties.remove(RolapConnectionProperties::Jdbc.name)
    removed |= properties.remove(RolapConnectionProperties::JdbcUser.name)
    removed |= properties.remove(RolapConnectionProperties::JdbcPassword.name)

    assert_equal true, removed

    # After removal, verify they are gone
    assert_nil properties.get(RolapConnectionProperties::Jdbc.name)
    assert_nil properties.get(RolapConnectionProperties::JdbcUser.name)
    assert_nil properties.get(RolapConnectionProperties::JdbcPassword.name)

    # Provider should still be present
    assert_equal "Mondrian", properties.get("Provider")
  end

  # Java: XmlaExtraTest#testGetDataSourceDoesntLeakPassword (end-to-end)
  it "getDataSources strips sensitive JDBC properties end-to-end" do
    # FIXME: Cannot test getDataSources end-to-end without Mockito with current investigation level.
    #
    # The Java test uses Mockito to mock four concrete/package-private classes
    # (MondrianServer, RolapConnection, MondrianOlap4jConnection,
    # MondrianOlap4jExtra) and inject a controlled DataSourceInfo string
    # containing "Jdbc=foo;JdbcPassword=bar;JdbcUser=bacon" into the
    # server.getDatabases() return value. It then calls the real
    # getDataSources method and verifies those properties are stripped.
    #
    # JRuby cannot use Mockito, and java.lang.reflect.Proxy only works with
    # interfaces — these are all concrete classes. The real ImplicitRepository
    # returns DataSourceInfo set to just the schema name (e.g. "FoodMart"),
    # which never contains JDBC properties, so calling getDataSources on a
    # real connection would pass trivially without exercising the stripping
    # code path.
    #
    # The test above verifies the stripping logic (Util.parseConnectString +
    # PropertyList.remove) works correctly on the same input the Java test
    # uses, but does not exercise it through getDataSources itself.
    skip "FIXME: requires Mockito to inject sensitive DataSourceInfo into server.getDatabases()"
  end
end
