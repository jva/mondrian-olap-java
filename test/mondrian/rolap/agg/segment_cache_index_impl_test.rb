# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2019-2019 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/rolap/cache/SegmentCacheIndexImplTest.java
describe "SegmentCacheIndexImpl" do
  SegmentCacheIndexImpl = Java::MondrianRolapCache::SegmentCacheIndexImpl
  SegmentHeader = Java::MondrianSpi::SegmentHeader
  SegmentBody = Java::MondrianSpi::SegmentBody
  ByteString = Java::MondrianUtil::ByteString
  BitKey = Java::MondrianRolap::BitKey

  # Java: SegmentCacheIndexImplTest#testNoHeaderOnLoad
  # This should not fail when loadSucceeded is called with a header that was
  # never registered in the index.
  it "does not fail when loadSucceeded called with unregistered header" do
    index = SegmentCacheIndexImpl.new(
      [java.lang.Thread.currentThread].to_java(java.lang.Thread)
    )

    checksum = ByteString.new([0].to_java(:byte))
    bit_key = BitKey::Factory.makeBitKey(0)
    header = SegmentHeader.new(
      "schema", checksum, "cube", "measure",
      java.util.Collections.emptyList,
      java.util.Collections.emptyList,
      "fact_table", bit_key,
      java.util.Collections.emptyList
    )

    body_handler = Class.new {
      include java.lang.reflect.InvocationHandler
      def invoke(_proxy, _method, _args)
        nil
      end
    }.new

    body = java.lang.reflect.Proxy.newProxyInstance(
      SegmentBody.java_class.getClassLoader,
      [SegmentBody.java_class].to_java(java.lang.Class),
      body_handler
    )

    # This should not fail — the header was never registered, so loadSucceeded
    # should silently discard the data and return without error.
    index.loadSucceeded(header, body)
    # No exception means success
    assert true
  end
end
