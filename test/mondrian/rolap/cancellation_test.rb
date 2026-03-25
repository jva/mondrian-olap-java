# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (c) 2002-2017 Hitachi Vantara.  All rights reserved.
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Subclass of Execution that counts checkCancelOrTimeout calls.
# Replaces Mockito's spy() + verify() pattern from the Java test.
class CountingExecution < Java::MondrianServer::Execution
  def initialize(statement, timeout)
    super
    @check_count = java.util.concurrent.atomic.AtomicInteger.new(0)
  end

  def check_count
    @check_count.get
  end

  def checkCancelOrTimeout
    @check_count.incrementAndGet
    super
  end
end

# Java: mondrian/rolap/CancellationTest.java
describe "Cancellation" do
  before(:all) do
    create_olap_connection
  end

  # Build a NullFunDef (equivalent to CrossJoinTest.NullFunDef in Java).
  def build_null_fun_def
    null_fun_def_class = Class.new do
      include Java::MondrianOlap::FunDef

      def getSyntax; Java::MondrianOlap::Syntax::Function; end
      def getName; ""; end
      def getDescription; ""; end
      def getReturnCategory; 0; end
      def getParameterCategories; [].to_java(:int); end
      def createCall(_validator, _args); nil; end
      def getSignature; ""; end
      def unparse(_args, _pw); end
      def compileCall(_call, _compiler); nil; end
    end
    null_fun_def_class.new
  end

  # Invoke a protected/package-private method via Java reflection.
  def invoke_method(object, method_name, param_class_names, *args)
    class_loader = object.getClass.getClassLoader
    param_types = param_class_names.map do |name|
      java.lang.Class.forName(name, true, class_loader)
    end

    cls = object.getClass
    method = nil
    while cls
      begin
        method = cls.getDeclaredMethod(method_name, param_types.to_java(java.lang.Class))
        break
      rescue java.lang.NoSuchMethodException
        cls = cls.getSuperclass
      end
    end

    method.setAccessible(true)
    method.invoke(object, *args)
  end

  # Get the evaluator from a RolapResult via reflection (package-private method).
  def get_evaluator(result, positions)
    int_array_class = java.lang.Class.forName("[I")
    method = result.getClass.getDeclaredMethod("getEvaluator", [int_array_class].to_java(java.lang.Class))
    method.setAccessible(true)
    method.invoke(result, positions.to_java(:int))
  end

  # Look up a member by path segments using a schema reader.
  def lookup_member(schema_reader, *path_segments)
    segments = Java::MondrianOlap::Id::Segment.toList(*path_segments)
    schema_reader.getMemberByUniqueName(segments, true)
  end

  # Java: CancellationTest#testNonEmptyListCancellation
  it "nonEmptyList checks cancellation for each tuple" do
    # Tests that cancellation/timeout is checked in CrossJoinFunDef.nonEmptyList
    with_properties(CheckCancelOrTimeoutInterval: 1) do
      connection = @olap.raw_mondrian_connection
      query = connection.parseQuery("select store.[store name].members on 0 from sales")
      result = connection.execute(query)

      evaluator = get_evaluator(result, [0])

      list = Java::MondrianCalcImpl::UnaryTupleList.new
      result.getAxes[0].getPositions.each do |position|
        list.add(position)
      end

      statement = evaluator.getQuery.getStatement
      counting_execution = CountingExecution.new(statement, 0)
      statement.start(counting_execution)

      cross_join = Java::MondrianOlapFun::CrossJoinFunDef.new(build_null_fun_def)
      invoke_method(cross_join, "nonEmptyList",
        %w[mondrian.olap.Evaluator mondrian.calc.TupleList mondrian.mdx.ResolvedFunCall],
        evaluator, list, nil)

      # checkCancelOrTimeout should be called once for each tuple since phase interval is 1
      assert_equal list.size, counting_execution.check_count
    end
  end

  # Java: CancellationTest#testMutableCrossJoinCancellation
  it "mutableCrossJoin checks cancellation for each tuple" do
    # Tests that cancellation/timeout is checked in CrossJoinFunDef.mutableCrossJoin
    with_properties(CheckCancelOrTimeoutInterval: 1) do
      connection = @olap.raw_mondrian_connection
      schema_reader = connection.getSchemaReader.withLocus
      sales_cube = schema_reader.getCubes.to_a.detect { |c| c.getName == "Sales" }
      sales_schema_reader = sales_cube.getSchemaReader(connection.getRole).withLocus

      # Build product members (Pot Scrubbers and Pots and Pans brands)
      product_members = Java::MondrianCalcImpl::UnaryTupleList.new
      [
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pot\ Scrubbers Cormorant],
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pot\ Scrubbers Denny],
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pot\ Scrubbers Red\ Wing],
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pots\ and\ Pans Cormorant],
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pots\ and\ Pans Denny],
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pots\ and\ Pans High\ Quality],
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pots\ and\ Pans Red\ Wing],
        %w[Product All\ Products Non-Consumable Household Kitchen\ Products Pots\ and\ Pans Sunset]
      ].each do |path|
        member = lookup_member(sales_schema_reader, *path)
        product_members.add(java.util.Collections.singletonList(member))
      end

      # Execute gender query and build gender members list
      gender_query = connection.parseQuery("select Gender.members on 0 from sales")
      gender_result = connection.execute(gender_query)
      gender_members = Java::MondrianCalcImpl::UnaryTupleList.new
      gender_result.getAxes[0].getPositions.each do |position|
        gender_members.add(position)
      end

      # Create counting execution
      statement = gender_result.getQuery.getStatement
      counting_execution = CountingExecution.new(statement, 0)

      # Call mutableCrossJoin inside Locus.execute with counting execution
      cross_join_result = Java::MondrianServer::Locus.execute(
        counting_execution, "CancellationTest"
      ) do
        Java::MondrianOlapFun::CrossJoinFunDef.mutableCrossJoin(product_members, gender_members)
      end

      # checkCancelOrTimeout should be called once for each tuple from mutableCrossJoin
      # plus once for each productMembers item since it gets through SqlStatement.execute
      expected_calls = cross_join_result.size + product_members.size
      assert_equal expected_calls, counting_execution.check_count
    end
  end
end
