# frozen_string_literal: true

module SqlCapture
  class SqlLogger
    include Java::MondrianRolap::RolapUtil::ExecuteQueryHook

    attr_reader :queries

    # TODO: Evaluate switching to Concurrent::Array (concurrent-ruby gem) for
    # consistency with eazybi once the full test suite is ported.
    def initialize
      @queries = java.util.concurrent.CopyOnWriteArrayList.new
    end

    def onExecuteQuery(sql)
      @queries << sql
    end
  end

  # Captures all SQL executed during the block.
  # Returns an array of SQL strings.
  def capture_sql
    logger = SqlLogger.new
    previous_hook = Java::MondrianRolap::RolapUtil.getHook
    Java::MondrianRolap::RolapUtil.setHook(logger)
    begin
      yield
    ensure
      Java::MondrianRolap::RolapUtil.setHook(previous_hook)
    end
    logger.queries
  end
end
