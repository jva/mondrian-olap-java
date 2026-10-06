# frozen_string_literal: true

require_relative 'support/database_setup'

require 'minitest/autorun'
require 'minitest/reporters'
require 'minitest/hooks/default'
require 'pry'

require_relative 'support/query_helper'
require_relative 'support/mondrian_properties'
require_relative 'support/schema_helper'
require_relative 'support/native_registry_helper'

Minitest::Reporters.use! Minitest::Reporters::DefaultReporter.new(color: true)

class Minitest::Spec
  include QueryHelper
  include MondrianPropertiesHelper
  include SchemaHelper
  include NativeRegistryHelper

  def assert_like(expected, actual, msg = nil)
    expected_normalized = expected.gsub(/>\s*\n\s*/, '> ').gsub(/\s+/, ' ').strip
    actual_normalized = actual.gsub(/>\s*\n\s*/, '> ').gsub(/\s+/, ' ').strip
    assert_equal expected_normalized, actual_normalized, msg
  end

  # Wrapper to bypass Oracle's default uppercasing of object names.
  def define_schema(name = nil, attributes = {}, &block)
    if name.is_a?(Hash) && attributes.empty?
      attributes = name
      name = nil
    end
    Mondrian::OLAP::Schema.define(name, {upcase_data_dictionary: false}.merge(attributes), &block)
  end

  def new_olap_connection
    @olap = Mondrian::OLAP::Connection.new(CONNECTION_PARAMS)
  end

  def create_olap_connection
    @olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
  end

  # Mondrian builds the member SQL of a virtual cube with a plain UNION, and ClickHouse rejects it.
  def skip_virtual_cube_union_on_clickhouse
    skip "ClickHouse requires UNION ALL or UNION DISTINCT in virtual cube member SQL" if MONDRIAN_DRIVER == "clickhouse"
  end
end
