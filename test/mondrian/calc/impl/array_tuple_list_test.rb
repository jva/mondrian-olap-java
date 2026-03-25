# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2020 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/calc/impl/ArrayTupleListTest.java
describe "ArrayTupleList" do
  # Minimal Member stub replacing Mockito mock.
  # The test only stores and retrieves members; no Member methods are called.
  class self::MemberStub
    include Java::MondrianOlap::Member

    def compareTo(other); 0; end
    def getAnnotationMap; java.util.Collections.emptyMap; end
  end

  before(:all) do
    @member1 = self.class::MemberStub.new
    @member2 = self.class::MemberStub.new
  end

  def add_tuples(list, count)
    count.times { list.addTuple(@member1, @member2) }
  end

  # Java: ArrayTupleListTest#testGrowListBeyondInitialCapacity
  it "grows list beyond initial capacity" do
    with_properties(ResultLimit: 0) do
      list = Java::MondrianCalcImpl::ArrayTupleList.new(2, 10)
      add_tuples(list, 50)

      assert_equal 50, list.size
      50.times do |i|
        assert_equal @member1, list.get(i).get(0)
        assert_equal @member2, list.get(i).get(1)
      end
    end
  end

  # Java: ArrayTupleListTest#testAttemptToGrowBeyondResultLimit
  it "raises when growing beyond ResultLimit" do
    with_properties(ResultLimit: 30) do
      list = Java::MondrianCalcImpl::ArrayTupleList.new(2, 10)
      error = assert_raises(Java::MondrianOlap::ResourceLimitExceededException) do
        add_tuples(list, 32)
      end
      assert_includes error.message, "result (31) exceeded limit (30)"
    end
  end
end
