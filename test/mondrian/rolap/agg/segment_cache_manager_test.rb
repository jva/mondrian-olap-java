# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2020 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# MockCommand that executes a provided block and returns "done".
# Defined at file level to avoid constant lookup issues with JRuby Java class extension.
class MockCacheCommand < Java::MondrianRolapAgg::SegmentCacheManager::Command
  def initialize(locus, &block)
    super()
    @locus = locus
    @block = block
  end

  def call
    @block.call if @block
    "done"
  end

  def getLocus
    @locus
  end
end

# Java: mondrian/rolap/agg/SegmentCacheManagerTest.java
describe "SegmentCacheManager" do
  # Use Unsafe to allocate a MondrianServer without calling its constructor,
  # replacing Mockito's mock(MondrianServer.class) from the Java test.
  def create_mock_server
    unsafe_field = java.lang.Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe")
    unsafe_field.accessible = true
    unsafe = unsafe_field.get(nil)

    server_class = java.lang.Class.forName(
      "mondrian.server.MondrianServerImpl", true,
      Java::MondrianRolapAgg::SegmentCacheManager.java_class.getClassLoader
    )
    unsafe.allocateInstance(server_class)
  end

  def create_locus
    Java::MondrianServer::Locus.new(Java::MondrianServer::Execution.new(nil, 0), "component", "message")
  end

  before(:all) do
    @server = create_mock_server
    @locus = create_locus
  end

  # Java: SegmentCacheManagerTest#testCommandExecution
  it "executes a command on the actor thread" do
    latch = java.util.concurrent.CountDownLatch.new(1)
    manager = Java::MondrianRolapAgg::SegmentCacheManager.new(@server)
    begin
      manager.execute(MockCacheCommand.new(@locus) { latch.countDown })
      latch.await(2000, java.util.concurrent.TimeUnit::MILLISECONDS)
      assert_equal 0, latch.getCount
    ensure
      manager.shutdown
    end
  end

  # Java: SegmentCacheManagerTest#testShutdownEndOfQueue
  it "completes all queued commands before shutdown" do
    results = java.util.concurrent.ArrayBlockingQueue.new(10)
    manager = Java::MondrianRolapAgg::SegmentCacheManager.new(@server)
    executor = java.util.concurrent.Executors.newFixedThreadPool(15)
    begin
      # Add 10 commands to the exec queue
      10.times do
        executor.submit(java.lang.Runnable.impl { execute_and_collect(results, manager) })
      end

      # Then shut down
      executor.submit(java.lang.Runnable.impl { manager.shutdown })

      # Collect the results. All should have completed successfully with "done".
      collected = []
      10.times do
        value = results.poll(2000, java.util.concurrent.TimeUnit::MILLISECONDS)
        assert_equal "done", value
        collected << value
      end
      assert_equal 10, collected.size
    ensure
      executor.shutdownNow
    end
  end

  # Java: SegmentCacheManagerTest#testShutdownMiddleOfQueue
  it "returns exceptions for commands submitted after shutdown" do
    results = java.util.concurrent.ArrayBlockingQueue.new(20)
    manager = Java::MondrianRolapAgg::SegmentCacheManager.new(@server)
    executor = java.util.concurrent.Executors.newFixedThreadPool(15)
    begin
      # Submit 2 commands for exec
      2.times do
        executor.submit(java.lang.Runnable.impl { execute_and_collect(results, manager) })
      end

      # Submit shutdown
      executor.submit(java.lang.Runnable.impl { manager.shutdown })

      # Submit 18 commands post-shutdown
      18.times do
        executor.submit(java.lang.Runnable.impl { execute_and_collect(results, manager) })
      end

      # Gather results. There should be 20 full results, with those following
      # shutdown containing an exception.
      collected = []
      20.times do
        collected << results.poll(2000, java.util.concurrent.TimeUnit::MILLISECONDS)
      end
      assert_equal 20, collected.size
      assert_equal "done", collected[0]
      assert_kind_of Java::MondrianOlap::MondrianException, collected[19]
    ensure
      executor.shutdownNow
    end
  end

  private

  # Executes a command that sleeps 100ms, placing either the result or any exception into the queue.
  def execute_and_collect(queue, manager)
    result = manager.execute(MockCacheCommand.new(@locus) { java.lang.Thread.sleep(100) })
    queue.put(result)
  rescue java.lang.RuntimeException => e
    queue.put(e)
  rescue => e
    queue.put(e)
  end
end
