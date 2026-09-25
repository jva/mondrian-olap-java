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
end
