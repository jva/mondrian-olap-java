# frozen_string_literal: true

require_relative "test_helper"

java_import "mondrian.rolap.RolapUtil"
java_import "mondrian.rolap.SqlStatement"

# Regression test for the SegmentCacheManager actor deadlock.
#
# SqlStatement.execute used to acquire a permit of the JVM wide, fair querySemaphore before it
# ran the segment load callback. The callback sends a command to the SegmentCacheManager actor
# and waits for the answer, and it kept the permit while it waited. The actor runs SQL of its
# own, through Aggregation.optimizePredicates and RolapStar.Column.getCardinality, and that SQL
# needs a permit too. The permit holders then waited for the actor, and the actor waited for
# them.
#
# The semaphore is fair, so each freed permit went to the next queued loader thread, which
# wedged in the same place. The wedged set only grew, and the engine never recovered.
#
# The fix acquires the permit after the callback. No query runs while the callback waits, so
# the permit covers only the query itself.
#
# SegmentLoader#load had the same cycle later in the load. It kept the statement open while
# setDataToSegments put the segments in the bounded actor queue. A full queue blocked the
# permit holder, and no actor drained the queue while it waited for a permit. The loader now
# closes the statement after it copies the rows.
describe "SqlStatement and the query semaphore" do
  # Records the free permit count where SqlStatement calls the hook. That call is the last
  # observable point before the segment load callback waits for the actor.
  class PermitProbeHook
    include Java::MondrianRolap::RolapUtil::ExecuteQueryHook

    attr_reader :records

    def initialize(semaphore)
      @semaphore = semaphore
      @records = []
    end

    def onExecuteQuery(sql)
      @records << [sql, @semaphore.availablePermits]
    end
  end

  # Records the free permit count when the segment loader writes a segment to the cache. The
  # loader calls SegmentCache.put just before loadSucceeded puts the event in the bounded actor
  # queue, and a full queue blocks the loader thread.
  class PermitProbeCacheHandler
    include java.lang.reflect.InvocationHandler

    attr_reader :records

    def initialize(delegate, semaphore)
      @delegate = delegate
      @semaphore = semaphore
      @records = []
    end

    def invoke(_proxy, method, args)
      @records << @semaphore.availablePermits if method.getName == "put"
      args ? method.invoke(@delegate, *args.to_a) : method.invoke(@delegate)
    rescue java.lang.reflect.InvocationTargetException => e
      raise e.cause
    end
  end

  before(:all) do
    create_olap_connection
    @olap.execute("SELECT {[Measures].[Unit Sales]} ON 0 FROM [Sales]")
  end

  let(:rolap_connection) { @olap.raw_mondrian_connection }

  let(:query_semaphore) do
    field = SqlStatement.java_class.getDeclaredField("querySemaphore")
    field.setAccessible(true)
    field.get(nil)
  end

  let(:segment_mdx) do
    <<~MDX
      SELECT {[Measures].[Store Sales]} ON 0,
             {[Time].[1997].[Q1].Children} ON 1
      FROM [Sales]
    MDX
  end

  def flush_sales_segments
    cache_control = rolap_connection.getCacheControl(nil)
    cube = rolap_connection.getSchema.lookupCube("Sales", true)
    cache_control.flush(cache_control.createMeasuresRegion(cube))
  end

  # SegmentCacheManager.compositeCache is final, so only reflection can put the probe there.
  def with_segment_cache_probe(semaphore)
    cache_mgr = rolap_connection.getServer.getAggregationManager.cacheMgr
    cache_field = cache_mgr.java_class.getDeclaredField("compositeCache")
    cache_field.setAccessible(true)
    original = cache_field.get(cache_mgr)
    handler = PermitProbeCacheHandler.new(original, semaphore)
    probe = java.lang.reflect.Proxy.newProxyInstance(
      original.getClass.getClassLoader,
      [Java::MondrianSpi::SegmentCache.java_class].to_java(java.lang.Class),
      handler
    )
    cache_field.set(cache_mgr, probe)
    yield
    handler
  ensure
    cache_field&.set(cache_mgr, original)
  end

  it "holds no query permit when the segment load hands over to the actor" do
    semaphore = query_semaphore
    total = semaphore.availablePermits
    assert_operator total, :>, 0, "expected the query semaphore to have free permits"

    # Drop the cached segments of the cube, so that the query runs segment SQL whatever the
    # other tests of this process loaded before.
    cache_control = rolap_connection.getCacheControl(nil)
    cube = rolap_connection.getSchema.lookupCube("Sales", true)
    cache_control.flush(cache_control.createMeasuresRegion(cube))

    hook = PermitProbeHook.new(semaphore)
    RolapUtil.setHook(hook)
    begin
      @olap.execute(<<~MDX)
        SELECT {[Measures].[Store Sales]} ON 0,
               {[Time].[1997].[Q1].Children} ON 1
        FROM [Sales]
      MDX
    ensure
      RolapUtil.setHook(nil)
    end

    segment_records = hook.records.select { |sql, _| sql =~ /\bsum\(/i }
    refute_empty segment_records, "expected the query to run segment SQL"

    segment_records.each do |sql, permits|
      assert_equal total, permits,
        "A query permit is already held when the segment load hands over to the actor. " \
        "Holding it across the actor round trip is what makes the deadlock.\nSQL: #{sql}"
    end
  end

  it "holds no query permit when the segment load sends the segment to the actor" do
    semaphore = query_semaphore
    total = semaphore.availablePermits

    flush_sales_segments
    handler = with_segment_cache_probe(semaphore) { @olap.execute(segment_mdx) }

    refute_empty handler.records, "expected the query to load a segment"

    handler.records.each do |permits|
      assert_equal total, permits,
        "A query permit is still held when the segment load sends the segment to the actor. " \
        "A full actor queue then blocks the permit holder"
    end
  end

  it "runs no segment SQL for a query that timed out while it waited for a permit" do
    semaphore = query_semaphore
    total = semaphore.availablePermits

    # Load the members first, so that only the segment SQL waits for a permit below.
    @olap.execute(segment_mdx)
    flush_sales_segments

    timeout = Java::MondrianOlap::MondrianProperties.instance.QueryTimeout
    saved_timeout = timeout.get
    timeout.set(1)
    semaphore.acquire(total)
    releaser = Thread.new do
      sleep 2
      semaphore.release(total)
    end
    begin
      handler = with_segment_cache_probe(semaphore) do
        assert_raises(Mondrian::OLAP::Error) { @olap.execute(segment_mdx) }
        # The segment load runs on its own thread and outlives the timed out query. Keep the
        # probe until that thread closes its statement.
        releaser.join
        deadline = Time.now + 10
        executing = Java::MondrianUtil::Counters::SQL_STATEMENT_EXECUTING_IDS
        sleep 0.05 until executing.isEmpty || Time.now > deadline
        assert_empty executing.to_a, "The segment load did not finish in time, so the probe cannot see its SQL"
      end
    ensure
      releaser.join
      timeout.set(saved_timeout)
    end

    assert_empty handler.records,
      "The query timed out while it waited for a permit, but it still ran its segment SQL"
  end
end
