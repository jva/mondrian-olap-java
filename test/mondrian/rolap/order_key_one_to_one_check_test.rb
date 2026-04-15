# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2004-2005 Julian Hyde
# Copyright (C) 2005-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# JRuby equivalent of Java TestAppender — extends Log4j AbstractAppender
# to capture log events for assertion. Uses a Java CopyOnWriteArrayList
# for thread safety since Log4j may call append from different threads.
# Defined at file level to avoid constant lookup issues when extending
# Java classes.
class LogEventCapture < Java::OrgApacheLoggingLog4jCoreAppender::AbstractAppender
  def initialize(name = "LogEventCapture")
    @log_events = java.util.concurrent.CopyOnWriteArrayList.new
    super(
      name,
      nil,
      Java::OrgApacheLoggingLog4jCoreLayout::PatternLayout.createDefaultLayout,
      true,
      Java::OrgApacheLoggingLog4jCoreConfig::Property::EMPTY_ARRAY
    )
  end

  attr_reader :log_events

  def append(event)
    @log_events.add(event.toImmutable)
  end

  def clear_events
    @log_events.clear
  end
end

# Schema with a deliberately broken Quarter level: ordinalColumn="month_of_year"
# creates a non-1:1 relationship between the Quarter member and its ordinal,
# which Mondrian detects and logs as errors.
ORDER_KEY_TEST_SCHEMA = <<~XML
  <?xml version="1.0"?>
  <Schema name="FoodMart 2358">
    <Dimension name="Time" type="TimeDimension">
      <Hierarchy hasAll="false" primaryKey="time_id">
        <Table name="time_by_day"/>
        <Level name="Year" column="the_year" type="Numeric" uniqueMembers="true"
            levelType="TimeYears"/>
        <Level name="Quarter" column="quarter" ordinalColumn="month_of_year" uniqueMembers="false" levelType="TimeQuarters"/>
        <Level name="Month" column="month_of_year" uniqueMembers="false" type="Numeric"
            levelType="TimeMonths"/>
      </Hierarchy>
    </Dimension>
  <Cube name="Sales" defaultMeasure="Unit Sales">
    <Table name="sales_fact_1997"/>
    <DimensionUsage name="Time" source="Time" foreignKey="time_id"/>
    <Measure name="Unit Sales" column="unit_sales" aggregator="sum"
        formatString="Standard"/>
  </Cube>
  </Schema>
XML

# Java: mondrian/rolap/OrderKeyOneToOneCheckTest.java
describe "OrderKeyOneToOneCheck" do
  Log4jLoggerConfig = Java::OrgApacheLoggingLog4jCoreConfig::LoggerConfig

  before(:all) do
    @member_source_appender = LogEventCapture.new("MemberSourceAppender")
    @sql_reader_appender = LogEventCapture.new("SqlReaderAppender")

    # Get Mondrian's internal LoggerContext via reflection. JRuby's
    # LogManager.getContext(false) returns a different context due to
    # classloader differences, so we must use the context that Mondrian's
    # static LOGGER fields are bound to.
    ms_logger_field = Java::MondrianRolap::SqlMemberSource.java_class.getDeclaredField("LOGGER")
    ms_logger_field.accessible = true
    @log4j_ctx = ms_logger_field.get(nil).getContext
    @log4j_config = @log4j_ctx.getConfiguration

    @member_source_appender.start
    @log4j_config.addAppender(@member_source_appender)
    ms_logger_config = Log4jLoggerConfig.new(
      "mondrian.rolap.SqlMemberSource",
      Java::OrgApacheLoggingLog4j::Level::ERROR,
      true
    )
    ms_logger_config.addAppender(@member_source_appender, nil, nil)
    @log4j_config.addLogger("mondrian.rolap.SqlMemberSource", ms_logger_config)

    @sql_reader_appender.start
    @log4j_config.addAppender(@sql_reader_appender)
    sr_logger_config = Log4jLoggerConfig.new(
      "mondrian.rolap.SqlTupleReader",
      Java::OrgApacheLoggingLog4j::Level::ERROR,
      true
    )
    sr_logger_config.addAppender(@sql_reader_appender, nil, nil)
    @log4j_config.addLogger("mondrian.rolap.SqlTupleReader", sr_logger_config)

    @log4j_ctx.updateLoggers
  end

  after(:all) do
    @member_source_appender.stop
    @sql_reader_appender.stop
    @log4j_config.removeLogger("mondrian.rolap.SqlMemberSource")
    @log4j_config.removeLogger("mondrian.rolap.SqlTupleReader")
    @log4j_ctx.updateLoggers
  end

  def create_order_key_connection
    Mondrian::OLAP::Connection.flush_schema_cache
    params = CONNECTION_PARAMS.merge(catalog_content: ORDER_KEY_TEST_SCHEMA)
    params.delete(:catalog)
    Mondrian::OLAP::Connection.create(params)
  end

  # Java: OrderKeyOneToOneCheckTest#testMemberSource
  it "member source detects order key one-to-one violation" do
    @member_source_appender.clear_events
    @sql_reader_appender.clear_events

    olap = create_order_key_connection
    begin
      mdx = <<~MDX
        with member [Measures].[Count Month] as 'Count(Descendants(Time.CurrentMember, [Time].[Month]))'
        select [Measures].[Count Month] on 0,
        [Time].[1997] on 1
        from [Sales]
      MDX

      olap.execute(mdx)

      assert_equal 8, @sql_reader_appender.log_events.size,
        "Running with modified schema should log 8 errors on sqlReader"
      assert_equal 8, @member_source_appender.log_events.size,
        "Running with modified schema should log 8 errors on memberSource"
    ensure
      olap.close
    end
  end

  # Java: OrderKeyOneToOneCheckTest#testSqlReader
  it "sql reader detects order key one-to-one violation" do
    @member_source_appender.clear_events
    @sql_reader_appender.clear_events

    olap = create_order_key_connection
    begin
      mdx = <<~MDX
        select [Time].[Quarter].Members on 0
        from [Sales]
      MDX

      olap.execute(mdx)

      assert_equal 16, @sql_reader_appender.log_events.size,
        "Running with modified schema should log 16 errors on sqlReader"
    ensure
      olap.close
    end
  end
end
