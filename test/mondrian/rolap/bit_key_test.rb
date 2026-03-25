# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2005-2005 Julian Hyde
# Copyright (C) 2005-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

BitKey = Java::MondrianRolap::BitKey
AbstractBitKey = Java::MondrianRolap::BitKey::AbstractBitKey

# Java: mondrian/rolap/BitKeyTest.java
describe "BitKey" do
  def make_and_set(size, positions)
    bit_key = BitKey::Factory.makeBitKey(size)
    positions.each { |p| bit_key.set(p) }
    bit_key
  end

  # -- Equality helpers --

  def do_test_equals(size0, size1, positions_array)
    positions_array.each_with_index do |positions, i|
      bit_key0 = make_and_set(size0, positions)
      bit_key1 = make_and_set(size1, positions)
      assert_equal true, bit_key0.equals(bit_key1),
        "BitKey not equals size0=#{size0}, size1=#{size1}, i=#{i}"
    end
  end

  def do_test_not_equals(size0, positions0, size1, positions1)
    bit_key0 = make_and_set(size0, positions0)
    bit_key1 = make_and_set(size1, positions1)
    assert_equal false, bit_key0.equals(bit_key1),
      "BitKey not equals size0=#{size0}, size1=#{size1}"
  end

  # -- Hash code helper --

  def do_hash_code(bit_keys)
    bit_keys.each_with_index do |bit_key1, i1|
      bit_keys.each_with_index do |bit_key2, i2|
        label = "(#{i1}, #{i2})"
        assert_equal bit_key1, bit_key2, label
        assert_equal bit_key1.hashCode, bit_key2.hashCode, label
        assert_equal 0, bit_key1.compareTo(bit_key2), label
      end
    end
  end

  # -- Bitwise operation test driver --

  def do_test_op
    size0 = 40
    size1 = 100
    size2 = 400

    positions0 = [0]
    positions1 = [1]
    yield size0, positions0, size0, positions1

    positions2 = [0, 1, 10, 20]
    positions3 = [1, 2, 10, 11]
    yield size0, positions2, size0, positions3

    positions4 = [0, 1, 10, 20]
    positions5 = [1, 2, 10, 65, 66]
    yield size0, positions4, size1, positions5
    yield size1, positions5, size0, positions4

    positions6 = [0, 1, 10, 20, 64, 65, 66]
    positions7 = [1, 2, 10, 65, 66]
    yield size1, positions6, size1, positions7

    positions8 = [0, 1, 10, 20]
    positions9 = [1, 2, 10, 165, 366]
    yield size0, positions8, size2, positions9
    yield size2, positions9, size0, positions8

    positions10 = [0, 1, 10, 20, 100]
    positions11 = [1, 2, 10, 165, 366]
    yield size1, positions10, size2, positions11
    yield size2, positions11, size1, positions10

    positions12 = [0, 1, 10, 20, 100, 165, 367]
    positions13 = [1, 2, 10, 165, 366]
    yield size2, positions12, size2, positions13
    yield size2, positions13, size2, positions12

    positions14 = [63]
    positions15 = [63, 127, 191]
    yield size1, positions14, size1, positions14
    yield size2, positions15, size2, positions15
  end

  # Java: BitKeyTest#testBadSize
  it "negative size throws IllegalArgumentException" do
    [-1, -10].each do |size|
      assert_raises(Java::JavaLang::IllegalArgumentException) do
        BitKey::Factory.makeBitKey(size)
      end
    end
  end

  # Java: BitKeyTest#testGoodSize
  it "non-negative sizes do not throw" do
    [0, 1, 10].each do |size|
      bit_key = BitKey::Factory.makeBitKey(size)
      refute_nil bit_key
    end
  end

  # Java: BitKeyTest#testSizeTypes
  it "returns correct implementation type for size" do
    {
      0 => BitKey::Small, 63 => BitKey::Small,
      64 => BitKey::Mid128, 65 => BitKey::Mid128, 127 => BitKey::Mid128,
      128 => BitKey::Big, 129 => BitKey::Big, 1280 => BitKey::Big
    }.each do |size, expected_class|
      bit_key = BitKey::Factory.makeBitKey(size)
      assert_equal expected_class.java_class.getName, bit_key.getClass.getName,
        "BitKey size #{size}"
    end
  end

  # Java: BitKeyTest#testEquals
  it "equals across different representations" do
    positions_array0 = [
      [0, 1, 2, 3],
      [3, 17, 33, 63],
      [1, 2, 3, 20, 21, 33, 61, 62, 63]
    ]
    do_test_equals(0, 0, positions_array0)
    do_test_equals(0, 64, positions_array0)
    do_test_equals(64, 0, positions_array0)
    do_test_equals(0, 128, positions_array0)
    do_test_equals(128, 0, positions_array0)
    do_test_equals(64, 128, positions_array0)
    do_test_equals(128, 64, positions_array0)

    positions_array1 = [
      [0, 1, 2, 3],
      [3, 17, 33, 63],
      [1, 2, 3, 20, 21, 33, 61, 62, 63],
      [1, 2, 3, 20, 21, 33, 61, 62, 55, 56, 127]
    ]
    do_test_equals(65, 65, positions_array1)
    do_test_equals(65, 128, positions_array1)
    do_test_equals(128, 65, positions_array1)
    do_test_equals(128, 128, positions_array1)

    positions_array2 = [
      [0, 1, 2, 3],
      [1, 2, 3, 20, 21, 33, 61, 62, 55, 56, 127, 128],
      [1, 2, 499],
      [1, 2, 200, 300, 499]
    ]
    do_test_equals(500, 500, positions_array2)
    do_test_equals(500, 700, positions_array2)
    do_test_equals(700, 500, positions_array2)
    do_test_equals(700, 700, positions_array2)
  end

  # Java: BitKeyTest#testHashCode
  it "hashCode is consistent across representations" do
    small = BitKey::Factory.makeBitKey(10)
    mid = BitKey::Factory.makeBitKey(70)
    big255 = BitKey::Factory.makeBitKey(255)
    big256 = BitKey::Factory.makeBitKey(256)
    big257 = BitKey::Factory.makeBitKey(257)

    bit_keys = [small, mid, big255, big256, big257]
    do_hash_code(bit_keys)

    bit_keys.each { |k| k.set(0, true) }
    do_hash_code(bit_keys)

    bit_keys = [mid, big255, big256, big257]
    bit_keys.each { |k| k.set(50, true) }
    do_hash_code(bit_keys)

    bit_keys = [big255, big256, big257]
    bit_keys.each do |k|
      k.set(128, true)
      k.set(50, false)
    end
    do_hash_code(bit_keys)
  end

  # Java: BitKeyTest#testNotEquals
  it "not equals for different bit patterns" do
    positions0 = [0, 1, 2, 3, 4]
    positions1 = [0, 1, 2, 3]
    do_test_not_equals(0, positions0, 0, positions1)
    do_test_not_equals(0, positions1, 0, positions0)
    do_test_not_equals(0, positions0, 64, positions1)
    do_test_not_equals(0, positions1, 64, positions0)
    do_test_not_equals(64, positions0, 0, positions1)
    do_test_not_equals(64, positions1, 0, positions0)
    do_test_not_equals(0, positions0, 128, positions1)
    do_test_not_equals(128, positions1, 0, positions0)
    do_test_not_equals(64, positions0, 128, positions1)
    do_test_not_equals(128, positions1, 64, positions0)
    do_test_not_equals(128, positions0, 128, positions1)
    do_test_not_equals(128, positions1, 128, positions0)

    positions2 = [0, 1]
    positions3 = [0, 1, 113]
    do_test_not_equals(0, positions2, 127, positions3)
    do_test_not_equals(127, positions3, 0, positions2)

    positions4 = [0, 1, 100, 121]
    positions5 = [0, 1, 100, 121, 200]
    do_test_not_equals(127, positions4, 300, positions5)
    do_test_not_equals(300, positions5, 127, positions4)

    positions6 = [0, 1, 100, 121, 200]
    positions7 = [0, 1, 100, 121, 130, 200]
    do_test_not_equals(200, positions6, 300, positions7)
    do_test_not_equals(300, positions7, 200, positions6)
  end

  # Java: BitKeyTest#testClear
  it "clear resets all bits" do
    bit_key_0 = BitKey::Factory.makeBitKey(0)
    bit_key_64 = BitKey::Factory.makeBitKey(64)
    bit_key_128 = BitKey::Factory.makeBitKey(128)

    # Small
    bit_key0 = make_and_set(20, [0, 1, 2, 3, 4])
    bit_key0.clear
    assert_equal true, bit_key0.equals(bit_key_0)
    assert_equal true, bit_key0.equals(bit_key_64)
    assert_equal true, bit_key0.equals(bit_key_128)

    # Mid128
    bit_key1 = make_and_set(68, [0, 1, 2, 3, 4, 45, 67])
    bit_key1.clear
    assert_equal true, bit_key1.equals(bit_key_0)
    assert_equal true, bit_key1.equals(bit_key_64)
    assert_equal true, bit_key1.equals(bit_key_128)

    # Big
    bit_key2 = make_and_set(400, [0, 1, 2, 3, 4, 45, 67, 213, 333])
    bit_key2.clear
    assert_equal true, bit_key2.equals(bit_key_0)
    assert_equal true, bit_key2.equals(bit_key_64)
    assert_equal true, bit_key2.equals(bit_key_128)
  end

  # Java: BitKeyTest#testNewBitKeyIsTheSameAsAClearedBitKey
  it "new BitKey equals a cleared BitKey" do
    bit_key = BitKey::Factory.makeBitKey(8)
    bit_key.set(1)
    assert_equal false, BitKey::Factory.makeBitKey(8).equals(bit_key)
    bit_key.clear
    assert_equal BitKey::Factory.makeBitKey(8), bit_key
  end

  # Java: BitKeyTest#testEmptyCopyCreatesBitKeyOfTheSameSize
  it "emptyCopy creates BitKey of the same size" do
    bit_key = BitKey::Factory.makeBitKey(8)
    assert_equal bit_key, bit_key.emptyCopy
  end

  # Java: BitKeyTest#testIsSuperSetOf
  it "isSuperSetOf" do
    bit_key0 = make_and_set(20, [0, 2, 3, 4, 23, 30])
    bit_key1 = make_and_set(20, [0, 2, 23])

    assert_equal true, bit_key0.isSuperSetOf(bit_key1), "BitKey 1 not subset of 0"
    assert_equal false, bit_key1.isSuperSetOf(bit_key0), "BitKey 0 is subset of 1"

    bit_key2 = make_and_set(65, [0, 1, 2, 3, 4, 23, 30, 113])
    assert_equal true, bit_key2.isSuperSetOf(bit_key0), "BitKey 0 not subset of 2"
    assert_equal true, bit_key2.isSuperSetOf(bit_key1), "BitKey 1 not subset of 2"
    assert_equal false, bit_key0.isSuperSetOf(bit_key2), "BitKey 2 is subset of 0"
    assert_equal false, bit_key1.isSuperSetOf(bit_key2), "BitKey 2 is subset of 1"

    bit_key3 = make_and_set(213, [0, 1, 2, 3, 4, 23, 30, 113, 145, 233, 234])
    assert_equal true, bit_key3.isSuperSetOf(bit_key0), "BitKey 0 not subset of 3"
    assert_equal true, bit_key3.isSuperSetOf(bit_key1), "BitKey 1 not subset of 3"
    assert_equal true, bit_key3.isSuperSetOf(bit_key2), "BitKey 2 not subset of 3"
    assert_equal false, bit_key0.isSuperSetOf(bit_key3), "BitKey 3 is subset of 0"
    assert_equal false, bit_key1.isSuperSetOf(bit_key3), "BitKey 3 is subset of 1"
    assert_equal false, bit_key2.isSuperSetOf(bit_key3), "BitKey 3 is subset of 2"
  end

  # Java: BitKeyTest#testOr
  it "or operation" do
    do_test_op do |size0, positions0, size1, positions1|
      bit_key0 = make_and_set(size0, positions0)
      bit_key1 = make_and_set(size1, positions1)
      bit_key = bit_key0.or(bit_key1)
      max = (positions0 + positions1).max || 0
      (0..max).each do |position|
        expected = positions0.include?(position) || positions1.include?(position)
        assert_equal expected, bit_key.get(position)
      end
    end
  end

  # Java: BitKeyTest#testOrNot
  it "orNot operation" do
    do_test_op do |size0, positions0, size1, positions1|
      bit_key0 = make_and_set(size0, positions0)
      bit_key1 = make_and_set(size1, positions1)
      bit_key = bit_key0.orNot(bit_key1)
      max = (positions0 + positions1).max || 0
      (0..max).each do |position|
        expected = positions0.include?(position) ^ positions1.include?(position)
        assert_equal expected, bit_key.get(position)
      end
    end
  end

  # Java: BitKeyTest#testAnd
  it "and operation" do
    do_test_op do |size0, positions0, size1, positions1|
      bit_key0 = make_and_set(size0, positions0)
      bit_key1 = make_and_set(size1, positions1)
      bit_key = bit_key0.and(bit_key1)
      max = (positions0 + positions1).max || 0
      (0..max).each do |position|
        expected = positions0.include?(position) && positions1.include?(position)
        assert_equal expected, bit_key.get(position)
      end
    end
  end

  # Java: BitKeyTest#testAndNot
  it "andNot operation" do
    do_test_op do |size0, positions0, size1, positions1|
      bit_key0 = make_and_set(size0, positions0)
      bit_key1 = make_and_set(size1, positions1)
      bit_key = bit_key0.andNot(bit_key1)
      max = (positions0 + positions1).max || 0
      (0..max).each do |position|
        expected = positions0.include?(position) && !positions1.include?(position)
        assert_equal expected, bit_key.get(position)
      end
    end
  end

  # Java: BitKeyTest#testIntersects
  it "intersects operation" do
    do_test_op do |size0, positions0, size1, positions1|
      bit_key0 = make_and_set(size0, positions0)
      bit_key1 = make_and_set(size1, positions1)
      result = bit_key0.intersects(bit_key1)
      expected = (positions0 & positions1).any?
      assert_equal expected, result
    end
  end

  # Java: BitKeyTest#testToBitSet
  it "toBitSet" do
    do_test_op do |size0, positions0, _size1, _positions1|
      bit_key0 = make_and_set(size0, positions0)
      bit_set = bit_key0.toBitSet
      actual_positions = []
      i = bit_set.nextSetBit(0)
      while i >= 0
        actual_positions << i
        i = bit_set.nextSetBit(i + 1)
      end
      assert_equal positions0.sort, actual_positions
    end
  end

  # Java: BitKeyTest#testCompareTo
  it "compareTo" do
    do_test_op do |size0, positions0, size1, positions1|
      bit_key0 = make_and_set(size0, positions0)
      bit_key1 = make_and_set(size1, positions1)
      c = bit_key0.compareTo(bit_key1)
      s0 = bit_key0.toString.sub("0x", "")
      s1 = bit_key1.toString.sub("0x", "")
      max_len = [s0.length, s1.length].max
      s0 = s0.rjust(max_len, "0")
      s1 = s1.rjust(max_len, "0")
      assert_equal c, (s0 <=> s1)
      assert_equal(-c, bit_key1.compareTo(bit_key0))
      assert_equal 0, bit_key0.compareTo(bit_key0)
      assert_equal 0, bit_key1.compareTo(bit_key1)
    end
  end

  # Java: BitKeyTest#testCreateFromBitSet
  it "create from BitSet" do
    bit_set = java.util.BitSet.new(72)
    bit_set.set(2)
    bit_set.set(3)
    bit_set.set(5)
    bit_set.set(11)
    bit_key = BitKey::Factory.makeBitKey(bit_set)
    assert_equal "0x0000000000000000000000000000000000000000000000000000100000101100",
      bit_key.toString

    empty_bit_set = java.util.BitSet.new(77)
    bit_key = BitKey::Factory.makeBitKey(empty_bit_set)
    assert_equal true, bit_key.isEmpty
  end

  # Java: BitKeyTest#testIsEmpty
  it "isEmpty" do
    small = BitKey::Factory.makeBitKey(3)
    assert_equal true, small.isEmpty
    small.set(2)
    assert_equal false, small.isEmpty

    medium = BitKey::Factory.makeBitKey(66)
    assert_equal true, medium.isEmpty
    medium.set(2)
    assert_equal false, medium.isEmpty
    medium.set(2, false)
    assert_equal true, medium.isEmpty
    medium.set(65)
    assert_equal false, medium.isEmpty

    large = BitKey::Factory.makeBitKey(131)
    assert_equal true, large.isEmpty
    large.set(2)
    assert_equal false, large.isEmpty
    large.set(129)
    assert_equal false, large.isEmpty
    large.set(129, false)
    large.set(2, false)
    assert_equal true, large.isEmpty
  end

  # Java: BitKeyTest#testIterator
  it "iterator, cardinality, and nextSetBit" do
    test_cases = [
      # Small
      [1], [2, 3, 4, 7, 14], [3, 6, 9, 12, 15, 24, 35, 48],
      [60, 62], [1, 3, 60, 63], [63], [0, 1, 62, 63],
      # Mid128
      [65], [1, 65], [1, 63, 64, 65, 66, 127], [127],
      # Big
      [128], [192], [1, 128], [0, 1, 127, 193],
      [0, 1, 127, 128, 191, 192, 193],
      [0, 1, 62, 63, 64, 127, 128, 191, 192, 193],
      [567], []
    ]
    test_cases.each do |bit_positions|
      max_position = bit_positions.max || 0
      bit_key = BitKey::Factory.makeBitKey(max_position)
      bit_positions.each { |p| bit_key.set(p) }

      # Verify iteration order
      actual = []
      bit_key.each { |i| actual << i.to_i }
      assert_equal bit_positions, actual

      # Check cardinality
      assert_equal bit_positions.length, bit_key.cardinality

      # Check nextSetBit
      index = -1
      iterator = bit_key.iterator
      while iterator.hasNext
        index = bit_key.nextSetBit(index + 1)
        assert_equal index, iterator.next.to_i
      end
      assert_equal(-1, bit_key.nextSetBit(index + 1))
    end
  end

  # Java: BitKeyTest#testCompareUnsigned
  it "compareUnsigned" do
    assert_equal 0, AbstractBitKey.compareUnsigned(0, 0)
    assert_equal 0, AbstractBitKey.compareUnsigned(10, 10)
    assert_equal 0, AbstractBitKey.compareUnsigned(-3, -3)
    assert_equal(-1, AbstractBitKey.compareUnsigned(0, 1))
    assert_equal 1, AbstractBitKey.compareUnsigned(1, 0)
    # negative numbers are interpreted as large unsigned
    assert_equal 1, AbstractBitKey.compareUnsigned(-1, 1)
    assert_equal 1, AbstractBitKey.compareUnsigned(-1, 0)
    # -1 is a larger unsigned number than -2
    assert_equal 1, AbstractBitKey.compareUnsigned(-1, -2)
    assert_equal(-1, AbstractBitKey.compareUnsigned(-2, -1))
  end

  # Java: BitKeyTest#testCompareUnsignedLongArrays
  it "compareUnsignedArrays" do
    cmp = ->(a, b) { AbstractBitKey.compareUnsignedArrays(a.to_java(:long), b.to_java(:long)) }

    # empty arrays are equal
    assert_equal 0, cmp.call([], [])
    # empty array does not equal other
    assert_equal(-1, cmp.call([], [1]))
    # empty array with left-padding
    assert_equal 0, cmp.call([], [0, 0])
    assert_equal 0, cmp.call([0], [])
    assert_equal 0, cmp.call([0, 0], [0, 0])
    # 0x00000050000001 > 00000040000002
    assert_equal 1, cmp.call([1, 5], [2, 4])
    # 0x00000050000001 < 00000050000002
    assert_equal(-1, cmp.call([1, 5], [2, 5]))
    # as above, with zero padding
    assert_equal(-1, cmp.call([1, 5], [2, 5, 0, 0]))
    assert_equal(-1, cmp.call([1, 5, 0, 0, 0], [2, 5, 0, 0]))
    assert_equal(-1, cmp.call([1, 5, 0, 0, 0], [2, 5]))
    # negative numbers are interpreted as large unsigned
    assert_equal 1, cmp.call([1, 5], [-2, 4])
  end
end
