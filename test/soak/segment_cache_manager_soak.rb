# frozen_string_literal: true

# Soak test for the SegmentCacheManager actor deadlock.
#
# SqlStatement.execute acquires a permit of the JVM wide, fair querySemaphore before it runs
# the segment load callback. The callback sends a command to the SegmentCacheManager actor
# and waits for the answer, and it keeps the permit while it waits. The actor runs SQL of its
# own, through Aggregation.optimizePredicates and RolapStar.Column.getCardinality, and that
# SQL needs a permit too. When the permit holders wait for the actor, the actor waits for
# them. The semaphore is fair, so each freed permit goes to the next queued loader thread,
# which wedges in the same place. The wedged set only grows, and the engine never recovers.
#
# This test does not assert a result. It runs a parallel query load and watches the JVM for
# the stack signature of the deadlock. It can miss, so a green run proves nothing. A red run
# always means a real defect.
#
# Parameters come from the environment, so that CI and a local sweep can use the same file.

require 'java'

def soak_int(name, default)
  (ENV[name] || default).to_i
end

SOAK_SECONDS        = soak_int('SOAK_SECONDS', 60)
SOAK_QUERY_LIMIT    = soak_int('SOAK_QUERY_LIMIT', 4)
SOAK_ACTOR_THREADS  = soak_int('SOAK_ACTOR_THREADS', 2)
SOAK_QUERY_THREADS  = soak_int('SOAK_QUERY_THREADS', 40)
SOAK_SEGMENT_DELAY  = soak_int('SOAK_SEGMENT_DELAY_MS', 200)
SOAK_DETECT_SECONDS = soak_int('SOAK_DETECT_SECONDS', 5)
SOAK_FLUSH_MS       = soak_int('SOAK_FLUSH_MS', 500)
SOAK_DUMP_PATH      = ENV['SOAK_DUMP_PATH'] || 'tmp/soak-threads.txt'

# SqlStatement reads mondrian.query.limit once, when the class loads. Set every property
# before database_setup requires mondrian/olap.
java.lang.System.setProperty('mondrian.query.limit', SOAK_QUERY_LIMIT.to_s)
java.lang.System.setProperty(
  'mondrian.rolap.agg.SegmentCacheManager.actorThreads', SOAK_ACTOR_THREADS.to_s
)
# The default of 20 would cap the number of MDX queries that run at the same time, and the
# deadlock needs many more threads queued for a permit than the semaphore can admit.
java.lang.System.setProperty('mondrian.rolap.maxQueryThreads', (SOAK_QUERY_THREADS * 2).to_s)

require_relative '../support/database_setup'

java_import 'java.lang.management.ManagementFactory'
java_import 'mondrian.rolap.RolapUtil'

# Holds a permit for longer, so that the loader threads exhaust the semaphore. The hook runs
# inside SqlStatement.execute, after the permit is acquired and before the callback.
class SegmentDelayHook
  include Java::MondrianRolap::RolapUtil::ExecuteQueryHook

  def initialize(delay_ms)
    @delay_ms = delay_ms
  end

  def onExecuteQuery(sql)
    java.lang.Thread.sleep(@delay_ms) if @delay_ms.positive? && sql =~ /\bsum\(/i
  end
end

# Watches for an actor thread parked in querySemaphore.acquire.
#
# ThreadMXBean.findDeadlockedThreads does not see this cycle. A Semaphore parks on AQS with no
# owning thread, so the JVM deadlock detector has nothing to follow. The signature is the
# evidence instead: an actor thread inside both SqlStatement.execute and Semaphore.acquire.
#
# A short wait is normal and resolves in milliseconds. Only a wait that persists is the latch,
# so the watchdog reports a thread that holds the signature for SOAK_DETECT_SECONDS.
class DeadlockWatchdog
  ACTOR_PREFIX = 'mondrian.rolap.agg.SegmentCacheManager$ACTOR'

  attr_reader :sightings, :max_persisted

  def initialize(detect_seconds, dump_path)
    @detect_seconds = detect_seconds
    @dump_path = dump_path
    @thread_bean = ManagementFactory.getThreadMXBean
    @wedged_since = {}
    @sightings = 0
    @max_persisted = 0.0
  end

  def start
    @thread = Thread.new do
      begin
        loop do
          check
          sleep 0.5
        end
      rescue StandardError => e
        warn "Watchdog failed: #{e.class}: #{e.message}"
        warn e.backtrace.first(5).join("\n")
        exit!(2)
      end
    end
    self
  end

  private

  # Java 21 added a dumpAllThreads(boolean, boolean, int) overload, so the two argument call
  # has to name its signature.
  def dump_all_threads
    @thread_bean.java_send(:dumpAllThreads, [Java::boolean, Java::boolean], true, true)
  end

  def check
    now = Time.now
    seen = []
    wedged_actors.each do |info|
      id = info.getThreadId
      seen << id
      @sightings += 1 unless @wedged_since.key?(id)
      @wedged_since[id] ||= now
      persisted = now - @wedged_since[id]
      @max_persisted = persisted if persisted > @max_persisted
      next if persisted < @detect_seconds

      report(info)
    end
    @wedged_since.delete_if { |id, _| !seen.include?(id) }
  end

  def wedged_actors
    dump_all_threads.select do |info|
      next false unless info.getThreadName.to_s.start_with?(ACTOR_PREFIX)

      frames = info.getStackTrace
      in_semaphore = frames.any? do |f|
        f.getClassName == 'java.util.concurrent.Semaphore' && f.getMethodName == 'acquire'
      end
      in_semaphore && frames.any? { |f| f.getClassName == 'mondrian.rolap.SqlStatement' }
    end
  end

  def report(info)
    write_dump
    puts
    puts '=' * 78
    puts 'DEADLOCK DETECTED: a SegmentCacheManager actor thread is parked in ' \
         'querySemaphore.acquire.'
    puts "Thread: #{info.getThreadName} (#{info.getThreadState}), held for at least " \
         "#{@detect_seconds}s."
    puts '=' * 78
    info.getStackTrace.first(12).each { |f| puts "    at #{f}" }
    puts
    puts "Full thread dump written to #{@dump_path}"
    $stdout.flush
    # The wedged threads never finish, so a normal exit would hang.
    exit!(1)
  end

  def write_dump
    require 'fileutils'
    FileUtils.mkdir_p(File.dirname(@dump_path))
    File.open(@dump_path, 'w') do |file|
      file.puts "Soak parameters: query_limit=#{SOAK_QUERY_LIMIT} " \
                "actor_threads=#{SOAK_ACTOR_THREADS} query_threads=#{SOAK_QUERY_THREADS} " \
                "segment_delay_ms=#{SOAK_SEGMENT_DELAY} driver=#{MONDRIAN_DRIVER}"
      file.puts "Java: #{java.lang.System.getProperty('java.version')}"
      file.puts
      dump_all_threads.each { |i| file.puts i.to_s }
    end
  rescue StandardError => e
    puts "Could not write the thread dump: #{e.class}: #{e.message}"
  end
end

# Every thread must load a different segment, or the first thread warms the cache and the
# others only read it. Then the loader threads never compete for the permits.
#
# The queries constrain two or more members of a level on purpose, because
# Aggregation.optimizePredicates reads a column cardinality only for a list predicate that
# holds at least two values. "Warehouse and Sales" is a virtual cube, so one batch carries
# cell requests for more than one star.
SLICES = [
  '[Store].[USA].[CA]', '[Store].[USA].[OR]', '[Store].[USA].[WA]',
  '[Store].[Mexico].[DF]', '[Store].[Mexico].[Guerrero]', '[Store].[Mexico].[Jalisco]',
  '[Store].[Mexico].[Veracruz]', '[Store].[Mexico].[Yucatan]', '[Store].[Mexico].[Zacatecas]',
  '[Store].[Canada].[BC]', '[Store].[USA]', '[Store].[Mexico]'
].freeze

QUARTERS = %w([Time].[1997].[Q1] [Time].[1997].[Q2] [Time].[1997].[Q3] [Time].[1997].[Q4]).freeze

CUBES = [
  ['[Sales]', '[Measures].[Store Sales], [Measures].[Unit Sales]'],
  ['[Warehouse and Sales]', '[Measures].[Store Sales], [Measures].[Warehouse Sales]']
].freeze

QUERIES = SLICES.product(QUARTERS, CUBES).map do |slice, quarter, (cube, measures)|
  <<~MDX
    SELECT {#{measures}} ON 0,
           CROSSJOIN({[Product].[Drink], [Product].[Food], [Product].[Non-Consumable]},
                     {#{quarter}.Children}) ON 1
    FROM #{cube}
    WHERE {#{slice}}
  MDX
end.freeze

puts "==> Soak: #{SOAK_SECONDS}s, query_limit=#{SOAK_QUERY_LIMIT}, " \
     "actor_threads=#{SOAK_ACTOR_THREADS}, query_threads=#{SOAK_QUERY_THREADS}, " \
     "segment_delay_ms=#{SOAK_SEGMENT_DELAY}"

watchdog = DeadlockWatchdog.new(SOAK_DETECT_SECONDS, SOAK_DUMP_PATH).start
RolapUtil.setHook(SegmentDelayHook.new(SOAK_SEGMENT_DELAY))

olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
deadline = Time.now + SOAK_SECONDS
queries = java.util.concurrent.atomic.AtomicLong.new
errors = java.util.concurrent.atomic.AtomicLong.new
flushes = java.util.concurrent.atomic.AtomicLong.new

# The schema flush runs while the queries run, not between them. A flush leaves the column
# cardinalities of the new star unknown, so the actor must run SQL for them. The flush has to
# happen while the loader threads already hold every permit, or the actor gets a permit at
# once and nothing wedges.
flusher = Thread.new do
  while Time.now < deadline
    olap.flush_schema_cache
    flushes.incrementAndGet
    sleep SOAK_FLUSH_MS / 1000.0
  end
rescue StandardError
  nil
end

workers = Array.new(SOAK_QUERY_THREADS) do |i|
  Thread.new do
    n = i
    while Time.now < deadline
      begin
        olap.execute(QUERIES[n % QUERIES.size])
        queries.incrementAndGet
      rescue StandardError
        errors.incrementAndGet
      end
      n += SOAK_QUERY_THREADS
    end
  end
end

workers.each(&:join)
flusher.join

RolapUtil.setHook(nil)
puts "==> Soak finished: #{queries.get} queries, #{flushes.get} schema flushes, " \
     "#{errors.get} query errors, no deadlock detected."
puts format('==> Actor waited for a permit %d times, longest wait %.1fs (detection needs %ds).',
            watchdog.sightings, watchdog.max_persisted, SOAK_DETECT_SECONDS)
puts '==> A green soak does not prove the defect is absent. It only means it did not latch.'

# A soak that loaded no segments proves nothing and must not report success. It means the
# queries do not run on this driver, not that the engine is sound.
if queries.get.zero? || errors.get > queries.get
  warn "==> The soak did no useful work: #{queries.get} queries succeeded and " \
       "#{errors.get} failed. Check the queries against the #{MONDRIAN_DRIVER} driver."
  exit!(3)
end

exit!(0)
