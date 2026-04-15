# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2019 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/RolapSchemaPoolTest.java
describe "RolapSchemaPool" do
  Util = Java::MondrianOlap::Util
  RolapConnectionProps = Java::MondrianRolap::RolapConnectionProperties

  before(:all) do
    create_olap_connection
    @class_loader = Java::MondrianRolap::RolapConnection.java_class.getClassLoader
  end

  after(:all) do
    @olap.close if @olap
  end

  # Access the package-private RolapSchemaPool class via reflection.
  def schema_pool_class
    @schema_pool_class ||= java.lang.Class.forName(
      "mondrian.rolap.RolapSchemaPool", true, @class_loader
    )
  end

  # Get the singleton RolapSchemaPool.instance().
  def schema_pool_instance
    method = schema_pool_class.getDeclaredMethod("instance", [].to_java(java.lang.Class))
    method.setAccessible(true)
    method.invoke(nil)
  end

  # Call pool.clear() via reflection.
  def pool_clear(pool)
    method = schema_pool_class.getDeclaredMethod("clear", [].to_java(java.lang.Class))
    method.setAccessible(true)
    method.invoke(pool)
  end

  # Call pool.get(catalogUrl, connectionKey, jdbcUser, dataSourceStr, connectInfo)
  # via reflection.
  def pool_get(pool, catalog_url, connection_key, jdbc_user, data_source_string, connect_info)
    method = schema_pool_class.getDeclaredMethod(
      "get",
      [
        java.lang.String, java.lang.String, java.lang.String,
        java.lang.String, Util::PropertyList
      ].to_java(java.lang.Class)
    )
    method.setAccessible(true)
    method.invoke(pool, catalog_url, connection_key, jdbc_user, data_source_string, connect_info)
  end

  # Call pool.get(catalogUrl, dataSource, connectInfo) via reflection.
  def pool_get_with_data_source(pool, catalog_url, data_source, connect_info)
    method = schema_pool_class.getDeclaredMethod(
      "get",
      [
        java.lang.String, javax.sql.DataSource, Util::PropertyList
      ].to_java(java.lang.Class)
    )
    method.setAccessible(true)
    method.invoke(pool, catalog_url, data_source, connect_info)
  end

  # Build a Util.PropertyList equivalent to what TestContext.getDefaultConnectString()
  # returns for the current test environment.
  def build_connect_info
    properties = Util::PropertyList.new
    properties.put("Provider", "mondrian")
    properties.put("Jdbc", DATABASE_JDBC_URL)
    properties.put("JdbcUser", DATABASE_USER)
    properties.put("JdbcPassword", DATABASE_PASSWORD)
    properties.put("JdbcDrivers", JDBC_DRIVER)
    properties.put("Catalog", CATALOG_FILE)
    properties
  end

  # Get the FoodMart catalog URL as a string, matching the Java test's getFoodmartCatalogUrl().
  def foodmart_catalog_url
    file = java.io.File.new(CATALOG_FILE)
    Java::MondrianOlap::Util.toURL(file).toString
  end

  # Call RolapConnection.createDataSource via reflection.
  def create_data_source(data_source, properties, buffer)
    cls = Java::MondrianRolap::RolapConnection.java_class
    method = cls.getDeclaredMethod(
      "createDataSource",
      [javax.sql.DataSource, Util::PropertyList, java.lang.StringBuilder].to_java(java.lang.Class)
    )
    method.setAccessible(true)
    method.invoke(nil, data_source, properties, buffer)
  rescue java.lang.reflect.InvocationTargetException => e
    raise e.cause
  end

  # Java: RolapSchemaPoolTest#testBasicSchemaFetch
  it "returns the same schema for identical arguments" do
    pool = schema_pool_instance
    pool_clear(pool)

    catalog_url = foodmart_catalog_url
    connect_info = build_connect_info

    schema = pool_get(pool, catalog_url, "connectionKeyA", "joeTheUser", "aDataSource", connect_info)
    schema_a = pool_get(pool, catalog_url, "connectionKeyA", "joeTheUser", "aDataSource", connect_info)

    # Same arguments, same object
    assert_equal true, schema.equal?(schema_a)
  end

  # Java: RolapSchemaPoolTest#testSchemaFetchCatalogUrlJdbcUuid
  it "uses JdbcConnectionUuid as pool key when set" do
    pool = schema_pool_instance
    pool_clear(pool)
    uuid = "UUID-1"

    catalog_url = foodmart_catalog_url
    connect_info = build_connect_info
    connect_info.put(RolapConnectionProps::JdbcConnectionUuid.name, uuid)

    # Put in pool
    schema = pool_get(pool, catalog_url, "connectionKeyA", "joeTheUser", "aDataSource", connect_info)

    # Same catalogUrl, same JdbcUuid
    connect_info_a = build_connect_info
    connect_info_a.put(RolapConnectionProps::JdbcConnectionUuid.name, uuid)
    same_schema = pool_get(pool, catalog_url, "aDifferentConnectionKey", "mrDoeTheOtherUser", "someDataSource", connect_info_a)

    # Must fetch the same object
    assert_equal true, schema.equal?(same_schema)

    connect_info.put(RolapConnectionProps::JdbcConnectionUuid.name, "SomethingCompletelyDifferent")
    new_schema = pool_get(pool, catalog_url, "connectionKeyA", "joeTheUser", "aDataSource", connect_info)

    # Must create a new object
    assert_equal false, schema.equal?(new_schema)
  end

  # Java: RolapSchemaPoolTest#testSchemaFetchMd5JdbcUid
  it "returns the same schema when using JdbcConnectionUuid and UseContentChecksum" do
    pool = schema_pool_instance
    pool_clear(pool)
    uuid = "UUID-1"

    catalog_url = foodmart_catalog_url
    connect_info = build_connect_info
    connect_info.put(RolapConnectionProps::JdbcConnectionUuid.name, uuid)
    connect_info.put(RolapConnectionProps::UseContentChecksum.name, "true")

    schema = pool_get(pool, catalog_url, "connectionKeyA", "joeTheUser", "aDataSource", connect_info)

    # Same connect info with a DynamicSchemaProcessor that returns the same content
    connect_info_dyn = connect_info.clone
    connect_info_dyn.put(
      RolapConnectionProps::DynamicSchemaProcessor.name,
      "mondrian.spi.impl.FilterDynamicSchemaProcessor"
    )
    schema_dyn = pool_get(pool, catalog_url, "connectionKeyB", "jed", "dsName", connect_info_dyn)

    assert_equal true, schema.equal?(schema_dyn)

    # Same content via CatalogContent property
    catalog_content = Util.readVirtualFileAsString(catalog_url)
    connect_info_content = connect_info.clone
    connect_info_content.remove(RolapConnectionProps::Catalog.name)
    connect_info_content.put(RolapConnectionProps::CatalogContent.name, catalog_content)
    schema_content = pool_get(pool, catalog_url, "connectionKeyC", "--", "--", connect_info_content)

    assert_equal true, schema.equal?(schema_content)

    # Same content via DataSource
    connect_info_ds = connect_info.clone
    buffer = java.lang.StringBuilder.new
    data_source = create_data_source(nil, connect_info_ds, buffer)
    schema_ds = pool_get_with_data_source(pool, catalog_url, data_source, connect_info_ds)

    assert_equal true, schema.equal?(schema_ds)
  end
end
