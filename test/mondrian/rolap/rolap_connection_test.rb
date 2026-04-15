# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2001-2005 Julian Hyde
# Copyright (C) 2005-2019 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Custom DataSourceResolver that returns a pre-configured DataSource.
# Used to replace JndiDataSourceResolver in JNDI tests, since setting up
# NamingManager.setInitialContextFactoryBuilder from JRuby is fragile.
class TestDataSourceResolver
  include Java::MondrianSpi::DataSourceResolver

  attr_reader :lookup_calls

  def initialize
    @data_sources = {}
    @lookup_calls = java.util.concurrent.atomic.AtomicInteger.new(0)
  end

  def register(name, data_source)
    @data_sources[name] = data_source
  end

  def lookup(data_source_name)
    @lookup_calls.incrementAndGet
    @data_sources[data_source_name]
  end
end

# Java: mondrian/rolap/RolapConnectionTest.java
describe "RolapConnection" do
  Util = Java::MondrianOlap::Util
  RolapConnectionProps = Java::MondrianRolap::RolapConnectionProperties
  MondrianDriverManager = Java::MondrianOlap::DriverManager

  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Build a Util.PropertyList equivalent to what TestContext.getConnectionProperties()
  # returns for the current test environment.
  def build_connection_properties
    properties = Util::PropertyList.new
    properties.put("Provider", "mondrian")
    properties.put("Jdbc", DATABASE_JDBC_URL)
    properties.put("JdbcUser", DATABASE_USER)
    properties.put("JdbcPassword", DATABASE_PASSWORD)
    properties.put("JdbcDrivers", JDBC_DRIVER)
    properties.put("Catalog", CATALOG_FILE)
    properties
  end

  # Call package-private static method RolapConnection.createDataSource via reflection.
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

  # Inject a custom DataSourceResolver into RolapConnection's private static field.
  # Returns the original resolver for restoration.
  def set_data_source_resolver(resolver)
    field = Java::MondrianRolap::RolapConnection.java_class.getDeclaredField("dataSourceResolver")
    field.setAccessible(true)
    original = field.get(nil)
    field.set(nil, resolver)
    original
  end

  # Clear the connection pool via reflection (RolapConnectionPool is package-private).
  def clear_connection_pool
    pool_class = java.lang.Class.forName(
      "mondrian.rolap.RolapConnectionPool", true,
      Java::MondrianRolap::RolapConnection.java_class.getClassLoader
    )
    instance_method = pool_class.getDeclaredMethod("instance", [].to_java(java.lang.Class))
    instance_method.setAccessible(true)
    pool = instance_method.invoke(nil)
    clear_method = pool_class.getDeclaredMethod("clearPool", [].to_java(java.lang.Class))
    clear_method.setAccessible(true)
    clear_method.invoke(pool)
  end

  # Collect full exception message chain (equivalent to TestContext.getStackTrace).
  def full_exception_chain(exception)
    messages = []
    cause = exception
    while cause
      messages << cause.getMessage.to_s if cause.getMessage
      cause = cause.respond_to?(:cause) ? cause.cause : nil
    end
    messages.join("\n")
  end

  describe "pooled and non-pooled connection with properties" do
    # Java: RolapConnectionTest#testPooledConnectionWithProperties
    it "pooled connection with properties" do
      properties = build_connection_properties
      properties.put("jdbc.charSet", "UTF-16")

      buffer = java.lang.StringBuilder.new
      data_source = create_data_source(nil, properties, buffer)
      description = buffer.toString
      assert description.start_with?("Jdbc="), "Expected description to start with 'Jdbc=', got: #{description}"

      jdbc = properties.get("Jdbc")
      if jdbc && !jdbc.start_with?("jdbc:odbc:")
        # Non-ODBC drivers may or may not reject UTF-16 charSet.
        # The Java test returns early here; we at least verified createDataSource.
        return
      end

      # JDBC-ODBC driver does not support UTF-16, so creating the connection fails.
      begin
        connection = data_source.getConnection
        connection.close
        flunk "Expected exception"
      rescue java.sql.SQLException
        # Expected
      rescue java.lang.IllegalArgumentException
        # Java bug workaround (see Java source)
      ensure
        clear_connection_pool
      end
    end

    # Java: RolapConnectionTest#testNonPooledConnectionWithProperties
    it "non-pooled connection with properties" do
      properties = build_connection_properties
      properties.put("jdbc.charSet", "UTF-16")
      properties.put(RolapConnectionProps::PoolNeeded.name, "false")

      buffer = java.lang.StringBuilder.new
      data_source = create_data_source(nil, properties, buffer)
      description = buffer.toString
      assert description.start_with?("Jdbc="), "Expected description to start with 'Jdbc=', got: #{description}"

      jdbc = properties.get("Jdbc")
      if jdbc && !jdbc.start_with?("jdbc:odbc:")
        # Non-ODBC drivers may or may not reject UTF-16 charSet.
        # The Java test returns early here; we at least verified createDataSource.
        return
      end

      # JDBC-ODBC driver does not support UTF-16, so creating the connection fails.
      begin
        connection = data_source.getConnection
        flunk "Expected exception"
      rescue java.sql.SQLException
        # Expected
      rescue java.lang.IllegalArgumentException
        # Java bug workaround (see Java source)
      ensure
        begin
          connection&.close
        rescue java.sql.SQLException
          # ignore
        end
      end
    end
  end

  describe "format locale" do
    # Helper to check locale-specific formatting.
    # Creates a connection with the specified locale and executes a query or expression.
    def check_locale(locale_name, expression, expected, is_query)
      params = CONNECTION_PARAMS.merge(locale: locale_name)
      olap = Mondrian::OLAP::Connection.create(params)
      begin
        if is_query
          mdx = "WITH MEMBER [Measures].[Foo] AS '#{expression}',\n" \
                " FORMAT_STRING = '#,##.#' \n" \
                "SELECT {[Measures].[Foo]} ON COLUMNS FROM [Sales]"
          expected_result = <<~RESULT
            Axis #0:
            {}
            Axis #1:
            {[Measures].[Foo]}
            Row #0: #{expected}
          RESULT
          assert_query_returns olap, mdx, expected_result
        else
          assert_expression_returns olap, expression, expected
        end
      ensure
        olap.close
      end
    end

    # Java: RolapConnectionTest#testFormatLocale
    it "FORMAT function uses connection locale" do
      expression = 'FORMAT(1234.56, "#,##.#")'
      check_locale("es_ES", expression, "1.234,6", false)
      check_locale("es_MX", expression, "1,234.6", false)
      check_locale("en_US", expression, "1,234.6", false)
    end

    # Java: RolapConnectionTest#testFormatStringLocale
    it "measures are formatted using connection locale" do
      check_locale("es_ES", "1234.56", "1.234,6", true)
      check_locale("es_MX", "1234.56", "1,234.6", true)
      check_locale("en_US", "1234.56", "1,234.6", true)
    end
  end

  # Java: RolapConnectionTest#testConnectSansCatalogFails
  it "connect without Catalog or CatalogContent fails" do
    properties = build_connection_properties
    properties.remove(RolapConnectionProps::Catalog.name)
    properties.remove(RolapConnectionProps::CatalogContent.name)

    error = assert_raises(Java::MondrianOlap::MondrianException) do
      MondrianDriverManager.getConnection(properties, nil)
    end
    assert error.getMessage.include?(
      "Connect string must contain property 'Catalog' or property 'CatalogContent'"
    )
  end

  describe "JNDI connection" do
    # Java: RolapConnectionTest#testJndiConnection
    it "connects via JNDI data source" do
      # Cannot guarantee that this test will work if they have chosen to
      # resolve data sources other than by JNDI.
      skip if Java::MondrianOlap::MondrianProperties.instance.DataSourceResolverClass.isSet

      # Get a regular data source via createDataSource
      properties = build_connection_properties
      buffer = java.lang.StringBuilder.new
      data_source = create_data_source(nil, properties, buffer)
      description = buffer.toString
      assert description.start_with?("Jdbc="), "Expected description to start with 'Jdbc=', got: #{description}"

      # Install a custom DataSourceResolver that returns our data source
      resolver = TestDataSourceResolver.new
      resolver.register("jnditest", data_source)
      original_resolver = set_data_source_resolver(resolver)

      begin
        # Use the datasource property to connect to the database.
        # Remove user and password, because some data sources (those using
        # pools) don't allow you to override user.
        properties2 = build_connection_properties
        properties2.remove(RolapConnectionProps::Jdbc.name)
        properties2.remove(RolapConnectionProps::JdbcUser.name)
        properties2.remove(RolapConnectionProps::JdbcPassword.name)
        properties2.put(RolapConnectionProps::DataSource.name, "jnditest")

        connection = MondrianDriverManager.getConnection(properties2, nil)
        connection.close if connection

        # If we've made it here with lookup calls,
        # we've successfully used the data source resolver (equivalent to JNDI)
        assert resolver.lookup_calls.get > 0, "Expected lookup calls, got: #{resolver.lookup_calls.get}"
      ensure
        set_data_source_resolver(original_resolver)
      end
    end
  end

  describe "data source override user/password" do
    # Java: RolapConnectionTest#testDataSourceOverrideUserPass
    it "overrides data source user and password from connection properties" do
      properties = build_connection_properties

      jdbc_user = properties.get(RolapConnectionProps::JdbcUser.name)
      jdbc_password = properties.get(RolapConnectionProps::JdbcPassword.name)
      skip "Can only run this test if username and password are explicit" unless jdbc_user && jdbc_password

      # Define a data source with bogus user and password.
      properties.put(RolapConnectionProps::JdbcUser.name, "bogususer")
      properties.put(RolapConnectionProps::JdbcPassword.name, "boguspassword")
      properties.put(RolapConnectionProps::PoolNeeded.name, "false")

      buffer = java.lang.StringBuilder.new
      data_source = create_data_source(nil, properties, buffer)
      description = buffer.toString
      assert description.start_with?("Jdbc="), "Expected Jdbc= prefix, got: #{description}"
      assert description.include?("JdbcUser=bogususer"), "Expected JdbcUser=bogususer in: #{description}"

      # Install a custom DataSourceResolver that returns our data source
      jndi_name = "jndiDataSource"
      resolver = TestDataSourceResolver.new
      resolver.register(jndi_name, data_source)
      original_resolver = set_data_source_resolver(resolver)

      begin
        # Create a property list for the actual mondrian connection.
        # Replace the original JDBC info with the data source.
        properties2 = Util::PropertyList.new
        properties.each do |entry|
          properties2.put(entry.getKey, entry.getValue)
        end
        properties2.remove(RolapConnectionProps::Jdbc.name)
        properties2.put(RolapConnectionProps::DataSource.name, jndi_name)

        # With JdbcUser and JdbcPassword credentials in the mondrian connect
        # string, the data source's "user" and "password" properties are
        # overridden and the connection succeeds.
        properties2.put(RolapConnectionProps::JdbcUser.name, jdbc_user)
        properties2.put(RolapConnectionProps::JdbcPassword.name, jdbc_password)

        connection = nil
        begin
          connection = MondrianDriverManager.getConnection(properties2, nil)
          query = connection.parseQuery("select from [Sales]")
          result = connection.execute(query)
          refute_nil result
        ensure
          connection&.close
        end

        # If we don't specify JdbcUser and JdbcPassword in the mondrian
        # connection properties, mondrian uses the data source's
        # bogus credentials, and the connection fails.
        properties2.remove(RolapConnectionProps::JdbcUser.name)
        properties2.remove(RolapConnectionProps::JdbcPassword.name)

        %w[false true].each do |pool_needed|
          # Important to test with & without pooling. Connection pools
          # typically do not let you change user, so it's important that
          # mondrian handles these right.
          properties2.put(RolapConnectionProps::PoolNeeded.name, pool_needed)
          connection = nil
          begin
            connection = MondrianDriverManager.getConnection(properties2, nil)
            flunk "Expected exception"
          rescue Java::MondrianOlap::MondrianException => e
            chain = full_exception_chain(e)
            assert chain.include?("Error while creating SQL connection: DataSource=#{jndi_name}"),
              "Expected 'Error while creating SQL connection: DataSource=#{jndi_name}' in:\n#{chain}"

            case MONDRIAN_DRIVER
            when "mysql"
              assert chain.include?("Access denied for user 'bogususer'"),
                "Expected 'Access denied for user bogususer' in:\n#{chain}"
            when "postgresql"
              assert(
                chain.match?(/password authentication failed for user "?bogususer"?/) ||
                  chain.match?(/role "?bogususer"? does not exist/),
                "Expected 'password authentication failed for user \"bogususer\"' or " \
                "'role \"bogususer\" does not exist' in error chain:\n#{chain}"
              )
            end
          ensure
            connection&.close
          end
        end
      ensure
        set_data_source_resolver(original_resolver)
        clear_connection_pool
      end
    end
  end

  describe "JDBC connection string assembly" do
    # Java: RolapConnectionTest#testGetJdbcConnectionWhenJdbcIsNull
    it "createDataSource returns blank connect info when Jdbc is null" do
      connect_info = java.lang.StringBuilder.new
      properties = build_connection_properties
      properties.remove(RolapConnectionProps::Jdbc.name)
      begin
        create_data_source(nil, properties, connect_info)
      rescue java.lang.RuntimeException
        # Expected: no DataSource or JNDI name, so creating a data source fails
      end
      assert connect_info.toString.strip.empty?,
        "Expected blank connect info, got: '#{connect_info.toString}'"
    end

    # Java: RolapConnectionTest#testJdbcConnectionString
    it "includes databaseName and integratedSecurity in connection string" do
      connect_info = java.lang.StringBuilder.new
      properties = build_connection_properties
      properties.put(RolapConnectionProps::JdbcUser.name, "sqlserver://localhost")
      properties.put("databaseName", "databaseTest")
      properties.put("integratedSecurity", "true")

      create_data_source(nil, properties, connect_info)

      connect_info_string = connect_info.toString
      refute connect_info_string.strip.empty?, "Connection info should not be blank"

      # Parse the semicolon-separated key=value pairs
      connect_info_map = {}
      connect_info_string.split(";").each do |pair|
        key_value = pair.split("=", 2)
        connect_info_map[key_value[0]] = key_value[1] if key_value.length == 2
      end

      assert_equal "databaseTest", connect_info_map["databaseName"]
      assert_equal "true", connect_info_map["integratedSecurity"]
    end

    # Java: RolapConnectionTest#testJdbcConnectionStringWithoutDatabase
    it "omits databaseName when not set" do
      connect_info = java.lang.StringBuilder.new
      properties = build_connection_properties
      properties.put(RolapConnectionProps::JdbcUser.name, "sqlserver://localhost")

      create_data_source(nil, properties, connect_info)

      refute connect_info.toString.strip.empty?, "Connection info should not be blank"
      refute connect_info.toString.include?("databaseName"),
        "Connection info should not contain databaseName: #{connect_info.toString}"
    end

    # Java: RolapConnectionTest#testJdbcConnectionStringWithoutIntegratedSecurity
    it "omits integratedSecurity when not set" do
      connect_info = java.lang.StringBuilder.new
      properties = build_connection_properties
      properties.put(RolapConnectionProps::JdbcUser.name, "sqlserver://localhost")

      create_data_source(nil, properties, connect_info)

      refute connect_info.toString.strip.empty?, "Connection info should not be blank"
      refute connect_info.toString.include?("integratedSecurity"),
        "Connection info should not contain integratedSecurity: #{connect_info.toString}"
    end
  end
end
