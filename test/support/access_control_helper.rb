# frozen_string_literal: true

# Schema variants and connections for the access control tests. The schema
# methods insert XML at the same places as TestContext#getSchema and
# TestContext#createSubstitutingCube in the Java tests.
module AccessControlHelper
  FOODMART_SCHEMA = File.read(CATALOG_FILE)

  # FoodMart schema with parameter (shared dimension), cube, virtual cube,
  # named set, role and user-defined function definitions added.
  def foodmart_schema(parameter_defs: nil, cube_defs: nil, virtual_cube_defs: nil,
                      named_set_defs: nil, udf_defs: nil, role_defs: nil)
    schema = FOODMART_SCHEMA
    schema = insert_before(schema, '<Dimension name="Store">', parameter_defs) if parameter_defs
    schema = insert_before(schema, '<Cube name="Sales" defaultMeasure="Unit Sales">', cube_defs) if cube_defs
    if virtual_cube_defs
      schema = insert_before(schema, '<VirtualCube name="Warehouse and Sales" defaultMeasure="Store Sales">',
        virtual_cube_defs)
    end
    if named_set_defs
      schema = insert_before(schema, schema.include?('<Role') ? '<Role' : '</Schema>', named_set_defs)
    end
    if role_defs
      schema = insert_before(schema, schema.include?('<UserDefinedFunction') ? '<UserDefinedFunction' : '</Schema>',
        role_defs)
    end
    schema = insert_before(schema, '</Schema>', udf_defs) if udf_defs
    schema
  end

  # Opens a connection to the FoodMart schema, or to the given schema XML,
  # with an optional role or comma-separated list of roles. The connection
  # closes after the test. The en_US locale gives the currency format of the
  # expected results, independently of the JVM default locale.
  def foodmart_connection(schema = nil, role: nil)
    params = CONNECTION_PARAMS.merge(locale: 'en_US')
    if schema
      params.delete(:catalog)
      params[:catalog_content] = schema
    end
    params[:role] = role.split(',') if role
    olap = Mondrian::OLAP::Connection.create(params)
    (@access_control_connections ||= []) << olap
    olap
  end

  def close_access_control_connections
    @access_control_connections&.each(&:close)
    @access_control_connections = nil
  end

  # Sets Mondrian properties for the block, then restores the previous values.
  def with_mondrian_properties(values)
    properties = Java::mondrian.olap.MondrianProperties.instance
    saved = values.keys.to_h { |name| [name, properties.send(name).get] }
    values.each { |name, value| properties.send(name).set(value) }
    yield
  ensure
    saved&.each { |name, value| properties.send(name).set(value) }
  end

  # Messages of an error and of all its causes, as TestContext#checkThrowable
  # searches the full stack trace for the pattern.
  def error_chain_message(error)
    messages = []
    e = error.respond_to?(:native_error) ? error.native_error : error
    while e
      messages << e.toString
      e = e.respond_to?(:cause) ? e.cause : nil
    end
    messages.join("\n")
  end

  # Asserts that the block raises an error which contains the pattern in its
  # message or in the message of one of its causes.
  def assert_error_chain_includes(pattern)
    error = assert_raises(Mondrian::OLAP::Error, Java::JavaLang::Exception) { yield }
    assert_includes error_chain_message(error), pattern
  end

  # Executes a query with the expression on the column axis, and asserts that
  # it raises an error which contains the pattern, as TestContext#assertAxisThrows.
  def assert_axis_raises(olap, expression, pattern, cube: "Sales")
    assert_error_chain_includes(pattern) { olap.execute("select {#{expression}} on columns from #{cube}") }
  end

  private

  def insert_before(schema, marker, text)
    index = schema.index(marker) or raise ArgumentError, "#{marker} not found in the FoodMart schema"
    schema[0...index] + text + schema[index..]
  end
end
