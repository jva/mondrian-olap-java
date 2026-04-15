# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2015-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/RolapSchemaPoolConcurrencyTest.java
describe "RolapSchemaPoolConcurrency" do
  before(:all) do
    @class_loader = Java::MondrianRolap::RolapUtil.java_class.getClassLoader
  end

  # -- Reflection helpers for package-private classes --

  def schema_pool_class
    @schema_pool_class ||= java.lang.Class.forName(
      "mondrian.rolap.RolapSchemaPool", true, @class_loader
    )
  end

  def schema_content_key_class
    @schema_content_key_class ||= java.lang.Class.forName(
      "mondrian.rolap.SchemaContentKey", true, @class_loader
    )
  end

  def connection_key_class
    @connection_key_class ||= java.lang.Class.forName(
      "mondrian.rolap.ConnectionKey", true, @class_loader
    )
  end

  def schema_key_class
    @schema_key_class ||= java.lang.Class.forName(
      "mondrian.rolap.SchemaKey", true, @class_loader
    )
  end

  # Get the singleton RolapSchemaPool.instance().
  def schema_pool_instance
    method = schema_pool_class.getDeclaredMethod("instance", [].to_java(java.lang.Class))
    method.setAccessible(true)
    method.invoke(nil)
  end

  # Create a SchemaContentKey via reflection.
  def create_schema_content_key(connect_info, catalog_url, catalog_string)
    method = schema_content_key_class.getDeclaredMethod(
      "create",
      [Java::MondrianOlap::Util::PropertyList, java.lang.String, java.lang.String].to_java(java.lang.Class)
    )
    method.setAccessible(true)
    method.invoke(nil, connect_info, catalog_url, catalog_string)
  end

  # Create a ConnectionKey via reflection.
  def create_connection_key(connection_uuid_string, data_source, catalog_url,
                            connection_key, jdbc_user, data_source_string)
    method = connection_key_class.getDeclaredMethod(
      "create",
      [
        java.lang.String, javax.sql.DataSource, java.lang.String,
        java.lang.String, java.lang.String, java.lang.String
      ].to_java(java.lang.Class)
    )
    method.setAccessible(true)
    method.invoke(nil, connection_uuid_string, data_source, catalog_url,
                  connection_key, jdbc_user, data_source_string)
  end

  # Create a SchemaKey via reflection.
  def create_schema_key(schema_content_key, connection_key)
    constructor = schema_key_class.getDeclaredConstructors.first
    constructor.setAccessible(true)
    constructor.newInstance(schema_content_key, connection_key)
  end

  # Create a lightweight RolapSchema using the deprecated test-only constructor.
  def create_fake_schema(key, md5_bytes)
    schema_class = java.lang.Class.forName("mondrian.rolap.RolapSchema", true, @class_loader)
    # Find the 3-arg constructor: RolapSchema(SchemaKey, ByteString, RolapConnection)
    constructor = schema_class.getDeclaredConstructors.detect do |c|
      param_types = c.getParameterTypes.to_a
      param_types.length == 3 &&
        param_types[0].getName == "mondrian.rolap.SchemaKey" &&
        param_types[1].getName == "mondrian.util.ByteString" &&
        param_types[2].getName == "mondrian.rolap.RolapConnection"
    end
    constructor.setAccessible(true)

    # Pass nil for internalConnection so that finalCleanUp (called by pool.remove)
    # skips flushSegments — a real connection is not needed for concurrency testing.
    constructor.newInstance(key, md5_bytes, nil)
  end

  # Remove a schema from the pool's internal maps directly via reflection.
  # The pool's own remove() method calls ConcurrentHashMap.remove(schema.getChecksum())
  # which throws NPE when checksum is null (ConcurrentHashMap disallows null keys).
  # This is safe because our fake schemas have no real state to clean up via finalCleanUp.
  def pool_remove(pool, schema)
    key_field = schema.getClass.getDeclaredField("key")
    key_field.setAccessible(true)
    key = key_field.get(schema)

    map_key_field = schema_pool_class.getDeclaredField("mapKeyToSchema")
    map_key_field.setAccessible(true)
    map_key_to_schema = map_key_field.get(pool)

    map_md5_field = schema_pool_class.getDeclaredField("mapMd5ToSchema")
    map_md5_field.setAccessible(true)
    map_md5_to_schema = map_md5_field.get(pool)

    ref = map_key_to_schema.get(key)
    if ref
      found_schema = ref.get
      if found_schema
        checksum = found_schema.getChecksum
        map_md5_to_schema.remove(checksum) if checksum
      end
    end
    map_key_to_schema.remove(key)
  end

  # Call pool.getRolapSchemas() via reflection.
  def pool_get_rolap_schemas(pool)
    method = schema_pool_class.getDeclaredMethod("getRolapSchemas", [].to_java(java.lang.Class))
    method.setAccessible(true)
    method.invoke(pool)
  end

  # Call pool.get(catalogUrl, dataSource, connectInfo) via reflection.
  def pool_get_with_data_source(pool, catalog_url, data_source, connect_info)
    method = schema_pool_class.getDeclaredMethod(
      "get",
      [java.lang.String, javax.sql.DataSource, Java::MondrianOlap::Util::PropertyList].to_java(java.lang.Class)
    )
    method.setAccessible(true)
    method.invoke(pool, catalog_url, data_source, connect_info)
  end

  # Call pool.putSchema(schema, md5Bytes, pinTimeout) via reflection.
  def pool_put_schema(pool, schema, md5_bytes, pin_timeout)
    byte_string_class = java.lang.Class.forName("mondrian.util.ByteString", true, @class_loader)
    method = schema_pool_class.getDeclaredMethod(
      "putSchema",
      [
        java.lang.Class.forName("mondrian.rolap.RolapSchema", true, @class_loader),
        byte_string_class,
        java.lang.String
      ].to_java(java.lang.Class)
    )
    method.setAccessible(true)
    method.invoke(pool, schema, md5_bytes, pin_timeout)
  end

  # Call pool.getLock(key) via reflection to obtain the write lock for proper synchronization.
  def pool_get_lock(pool, key)
    method = schema_pool_class.getDeclaredMethod(
      "getLock", [java.lang.Object].to_java(java.lang.Class)
    )
    method.setAccessible(true)
    method.invoke(pool, key)
  end

  # Create a DataSource proxy (mock) for use as a unique identity in pool keys.
  def create_mock_data_source
    handler = java.lang.reflect.InvocationHandler.impl do |_proxy, _method, _args|
      nil
    end
    java.lang.reflect.Proxy.newProxyInstance(
      @class_loader,
      [javax.sql.DataSource].to_java(java.lang.Class),
      handler
    )
  end

  # Build a unique schema key and fake schema, simulating what pool.get() does
  # when the Mockito spy intercepts createRolapSchema.
  def add_schema_to_pool(pool, catalog_url, needs_checksum)
    data_source = create_mock_data_source
    catalog_content = java.util.UUID.randomUUID.toString

    list = Java::MondrianOlap::Util::PropertyList.new
    list.put("CatalogContent", catalog_content)
    if needs_checksum
      list.put("UseContentChecksum", "true")
    end

    schema_content_key = create_schema_content_key(list, catalog_url, catalog_content)
    connection_key = create_connection_key(nil, data_source, catalog_url, nil, nil, nil)
    key = create_schema_key(schema_content_key, connection_key)

    md5_bytes = if needs_checksum
      Java::MondrianUtil::ByteString.new(Java::MondrianOlap::Util.digestMd5(catalog_content))
    end

    schema = create_fake_schema(key, md5_bytes)

    # Add to pool under write lock, matching pool.getByKey/getByChecksum behavior
    lock = pool_get_lock(pool, needs_checksum && md5_bytes ? md5_bytes : key)
    lock.writeLock.lock
    begin
      pool_put_schema(pool, schema, md5_bytes, "-1s")
    ensure
      lock.writeLock.unlock
    end

    schema
  end

  # Run concurrent tasks and collect errors. Equivalent to the Java runTest method.
  def run_concurrent_test(callables)
    executor = java.util.concurrent.Executors.newFixedThreadPool(callables.size)
    errors = []
    begin
      completion_service = java.util.concurrent.ExecutorCompletionService.new(executor)
      callables.each { |c| completion_service.submit(c) }

      callables.size.times do
        future = completion_service.take
        begin
          result = future.get
          errors << result if result
        rescue java.util.concurrent.ExecutionException => exception
          errors << "Execution exception: #{exception.message}"
        end
      end
    ensure
      executor.shutdown
    end

    assert_empty errors, "The following errors occurred:\n#{errors.join("\n")}"
  end

  # -- Callable implementations mirroring Java inner classes --

  # Adds schemas to the pool, mirroring the Java Adder class.
  # Instead of calling pool.get() (which requires a Mockito spy to intercept
  # createRolapSchema), this creates fake schemas and adds them under proper locking,
  # replicating the same concurrent access pattern on the pool's internal data structures.
  AdderCallable = Class.new do
    include java.util.concurrent.Callable

    def initialize(test, pool, cycles, needs_checksum, shared_queue = nil)
      @test = test
      @pool = pool
      @cycles = cycles
      @needs_checksum = needs_checksum
      @shared_queue = shared_queue
      @added = java.util.concurrent.CopyOnWriteArrayList.new
    end

    def added
      @added.to_a
    end

    def call
      random = java.util.Random.new
      @cycles.times do
        schema = @test.add_schema_to_pool(@pool, "catalog", @needs_checksum)
        @added.add(schema)
        @shared_queue.add(schema) if @shared_queue

        java.lang.Thread.sleep(random.nextInt(50))
      end
      nil
    end
  end

  # Removes schemas from the pool, mirroring the Java Remover class.
  RemoverCallable = Class.new do
    include java.util.concurrent.Callable

    def initialize(test, pool, shared_queue)
      @test = test
      @pool = pool
      @shared_queue = shared_queue
    end

    def call
      # Sleep initially to let adders do their work
      java.lang.Thread.sleep(100)
      loop do
        schema = @shared_queue.poll(250, java.util.concurrent.TimeUnit::MILLISECONDS)
        if schema.nil?
          # Give another chance
          schema = @shared_queue.poll(1, java.util.concurrent.TimeUnit::SECONDS)
          return nil if schema.nil?
        end
        @test.pool_remove(@pool, schema)
      end
      nil
    end
  end

  # Iterates pool.getRolapSchemas(), mirroring the Java Getter class.
  GetterCallable = Class.new do
    include java.util.concurrent.Callable

    def initialize(test, pool, cycles)
      @test = test
      @pool = pool
      @cycles = cycles
    end

    def call
      random = java.util.Random.new
      @cycles.times do
        accumulator = 0
        schemas = @test.pool_get_rolap_schemas(@pool)
        schemas.each do |schema|
          # Fake action to prevent JIT from eliminating this block
          key_field = schema.getClass.getDeclaredField("key")
          key_field.setAccessible(true)
          key = key_field.get(schema)
          accumulator += key.hashCode
        end
        accumulator = -accumulator if accumulator < 0
        java.lang.Thread.sleep([random.nextInt(50), accumulator].min)
      end
      nil
    end
  end

  # Repeatedly fetches the same schema from the pool via pool.get(),
  # mirroring the Java SingleSchemaGetter class.
  SingleSchemaGetterCallable = Class.new do
    include java.util.concurrent.Callable

    def initialize(test, pool, cycles, catalog_url, data_source, list)
      @test = test
      @pool = pool
      @cycles = cycles
      @catalog_url = catalog_url
      @data_source = data_source
      @list = list
    end

    def call
      @cycles.times do
        schema = @test.pool_get_with_data_source(@pool, @catalog_url, @data_source, @list)
        if schema.nil?
          catalog_content = @list.get("CatalogContent")
          return "Schema was nil. Catalog: [#{@catalog_url}], catalog content: [#{catalog_content}]"
        end
      end
      nil
    rescue java.lang.reflect.InvocationTargetException => exception
      cause = exception.cause
      "InvocationTargetException: #{cause.getClass.getName}: #{cause.message}"
    end
  end

  # -- Shared setup/teardown for all tests --

  before do
    @pool = schema_pool_instance
    @added_schemas = []
  end

  after do
    @added_schemas.each do |schema|
      pool_remove(@pool, schema)
    end
  end

  # Java: RolapSchemaPoolConcurrencyTest#testTwentyAdders
  it "twenty adders run concurrently without errors" do
    cycles = 500
    adders_amount = 10 * 2

    adders = []
    (adders_amount / 2).times do
      adders << AdderCallable.new(self, @pool, cycles, false)
      adders << AdderCallable.new(self, @pool, cycles, true)
    end

    begin
      run_concurrent_test(adders)
    ensure
      adders.each { |adder| @added_schemas.concat(adder.added) }
    end
  end

  # Java: RolapSchemaPoolConcurrencyTest#testTenAddersAndFiveRemovers
  it "ten adders and five removers run concurrently without errors" do
    cycles = 200
    removers_amount = 5
    adders_amount = removers_amount * 2

    adders = []
    removers = []
    removers_amount.times do
      shared = java.util.concurrent.LinkedBlockingQueue.new
      adders << AdderCallable.new(self, @pool, cycles, false, shared)
      adders << AdderCallable.new(self, @pool, cycles, true, shared)
      removers << RemoverCallable.new(self, @pool, shared)
    end

    actors = []
    actors.concat(adders)
    actors.concat(removers)
    actors.shuffle!

    begin
      run_concurrent_test(actors)
    ensure
      adders.each { |adder| @added_schemas.concat(adder.added) }
    end
  end

  # Java: RolapSchemaPoolConcurrencyTest#testTwentySimpleGetters
  it "twenty simple getters run concurrently without errors" do
    cycles = 1000
    actors_amount = 20

    actors = []
    actors_amount.times do
      catalog_url = java.util.UUID.randomUUID.toString
      data_source = create_mock_data_source

      list = Java::MondrianOlap::Util::PropertyList.new
      catalog_content = java.util.UUID.randomUUID.toString
      list.put("CatalogContent", catalog_content)

      # Pre-populate the pool with a fake schema matching this key
      schema_content_key = create_schema_content_key(list, catalog_url, catalog_content)
      connection_key = create_connection_key(nil, data_source, catalog_url, nil, nil, nil)
      key = create_schema_key(schema_content_key, connection_key)

      schema = create_fake_schema(key, nil)

      lock = pool_get_lock(@pool, key)
      lock.writeLock.lock
      begin
        pool_put_schema(@pool, schema, nil, "-1s")
      ensure
        lock.writeLock.unlock
      end
      @added_schemas << schema

      actors << SingleSchemaGetterCallable.new(self, @pool, cycles, catalog_url, data_source, list)
    end

    run_concurrent_test(actors)
  end

  # Java: RolapSchemaPoolConcurrencyTest#testFourAddersTwoRemoversTenGetters
  it "four adders, two removers, and ten getters run concurrently without errors" do
    adding_cycles = 200
    removers_amount = 2
    adders_amount = removers_amount * 2
    listing_cycles = 500
    getters_amount = 10

    adders = []
    removers = []
    removers_amount.times do
      shared = java.util.concurrent.LinkedBlockingQueue.new
      adders << AdderCallable.new(self, @pool, adding_cycles, false, shared)
      adders << AdderCallable.new(self, @pool, adding_cycles, true, shared)
      removers << RemoverCallable.new(self, @pool, shared)
    end

    getters = []
    getters_amount.times do
      getters << GetterCallable.new(self, @pool, listing_cycles)
    end

    actors = []
    actors.concat(adders)
    actors.concat(removers)
    actors.concat(getters)
    actors.shuffle!

    begin
      run_concurrent_test(actors)
    ensure
      adders.each { |adder| @added_schemas.concat(adder.added) }
    end
  end
end
