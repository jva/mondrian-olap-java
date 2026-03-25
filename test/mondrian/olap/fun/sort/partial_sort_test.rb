# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2001-2005 Julian Hyde
# Copyright (C) 2005-2020 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../../test_helper"

# Test input for stable partial sort: an item with an explicit index.
# Sort should not permute items with equal keys.
class SortItem
  include java.lang.Comparable

  attr_reader :index, :key

  def initialize(index, key)
    @index = index
    @key = key
  end

  def compareTo(other)
    @key <=> other.key
  end

  def to_s
    "Item(#{@index}, #{@key})"
  end
end

# Comparator that compares SortItems by key
class ItemKeyComparator
  include java.util.Comparator

  def compare(x, y)
    x.key <=> y.key
  end
end

# Java: mondrian/olap/fun/sort/PartialSortTest.java
describe "PartialSort" do
  Sorter = Java::MondrianOlapFunSort::Sorter
  ComparatorUtils = Java::OrgApacheCommonsCollections::ComparatorUtils
  ReverseComparator = Java::OrgApacheCommonsCollectionsComparators::ReverseComparator

  # -- helper methods --

  def new_random_integers(length, min_value, max_value)
    delta = max_value - min_value
    Array.new(length) { java.lang.Integer.new(min_value + rand(delta)) }.to_java(java.lang.Object)
  end

  # Calls partialSort (package-private) via reflection
  def do_partial_sort(items, descending, limit)
    comp = ComparatorUtils.naturalComparator
    comp = ComparatorUtils.reversedComparator(comp) if descending

    method = Sorter.java_class.declared_method(:partialSort, java.lang.Object[].java_class,
      java.util.Comparator.java_class, Java::int)
    method.accessible = true
    method.invoke(nil, items, comp, java.lang.Integer.new(limit))
  end

  # Checks that a Java Integer[] array is partially sorted.
  # JRuby auto-converts Java Integers to Ruby integers on array access.
  def partially_sorted_java?(vec, limit, descending)
    (1...limit).each do |i|
      delta = vec[i] - vec[i - 1]
      return false if descending ? delta > 0 : delta < 0
    end
    bound = vec[limit - 1]
    (limit...vec.length).each do |i|
      delta = vec[i] - bound
      return false if descending ? delta > 0 : delta < 0
    end
    true
  end

  # Checks that a Ruby int array is partially sorted
  def partially_sorted_ints?(vec, limit, descending)
    (1...limit).each do |i|
      delta = vec[i] - vec[i - 1]
      return false if descending ? delta > 0 : delta < 0
    end
    bound = vec[limit - 1]
    (limit...vec.length).each do |i|
      delta = vec[i] - bound
      return false if descending ? delta > 0 : delta < 0
    end
    true
  end

  # Checks that a Ruby array is partially sorted using natural comparison
  def partially_sorted?(vec, limit, descending)
    (1...limit).each do |i|
      delta = vec[i] <=> vec[i - 1]
      if descending
        return false if delta > 0
      else
        return false if delta < 0
      end
    end
    bound = vec[limit - 1]
    (limit...vec.length).each do |i|
      delta = vec[i] <=> bound
      return false if descending ? delta > 0 : delta < 0
    end
    true
  end

  # Checks SortItem array is partially sorted by key, with stable index ordering for ties
  def stably_sorted?(vec, limit, descending)
    (1...limit).each do |i|
      delta = vec[i].key <=> vec[i - 1].key
      if delta == 0
        return false if vec[i].index < vec[i - 1].index
      elsif descending
        return false if delta > 0
      else
        return false if delta < 0
      end
    end
    bound_key = vec[limit - 1].key
    (limit...vec.length).each do |i|
      delta = vec[i].key <=> bound_key
      return false if descending ? delta > 0 : delta < 0
    end
    true
  end

  def new_partly_sorted_items(length, limit, descending)
    factor = descending ? -1 : 1
    key = descending ? (2 * length) : 0
    Array.new(length) do |i|
      if i < limit
        item = SortItem.new(i, key)
        key += factor * (i % 3)
        item
      else
        SortItem.new(i, key + factor * rand(length))
      end
    end
  end

  def new_random_items(length, min_key, max_key)
    delta = max_key - min_key
    Array.new(length) { |i| SortItem.new(i, min_key + rand(delta)) }
  end

  def do_stable_partial_sort(vec, descending, limit)
    comp = ItemKeyComparator.new
    comp = ReverseComparator.new(comp) if descending
    java_list = java.util.ArrayList.new(vec.to_a)
    sorted = Sorter.stablePartialSort(java_list, comp, limit)
    sorted.to_a
  end

  def random_integer_tests(length, limit)
    vec = new_random_integers(length, 0, length)
    do_partial_sort(vec, true, limit)
    assert_equal true, partially_sorted_java?(vec, limit, true)

    vec = new_random_integers(length, 0, length)
    do_partial_sort(vec, false, limit)
    assert_equal true, partially_sorted_java?(vec, limit, false)

    # wider range of values
    vec = new_random_integers(length, 10, 4 * length)
    do_partial_sort(vec, true, limit)
    assert_equal true, partially_sorted_java?(vec, limit, true)

    vec = new_random_integers(length, 10, 4 * length)
    do_partial_sort(vec, false, limit)
    assert_equal true, partially_sorted_java?(vec, limit, false)

    # narrower range of values
    vec = new_random_integers(length, 0, length / 10)
    do_partial_sort(vec, true, limit)
    assert_equal true, partially_sorted_java?(vec, limit, true)

    vec = new_random_integers(length, 0, length / 10)
    do_partial_sort(vec, false, limit)
    assert_equal true, partially_sorted_java?(vec, limit, false)
  end

  def random_item_tests(length, limit)
    vec = new_random_items(length, 0, length)
    vec = do_stable_partial_sort(vec, true, limit)
    assert_equal true, stably_sorted?(vec, limit, true)

    vec = new_random_items(length, 0, length)
    vec = do_stable_partial_sort(vec, false, limit)
    assert_equal true, stably_sorted?(vec, limit, false)

    # wider range of values
    vec = new_random_items(length, 10, 4 * length)
    vec = do_stable_partial_sort(vec, true, limit)
    assert_equal true, stably_sorted?(vec, limit, true)

    vec = new_random_items(length, 10, 4 * length)
    vec = do_stable_partial_sort(vec, false, limit)
    assert_equal true, stably_sorted?(vec, limit, false)

    # narrower range of values
    vec = new_random_items(length, 0, length / 10)
    vec = do_stable_partial_sort(vec, true, limit)
    assert_equal true, stably_sorted?(vec, limit, true)

    vec = new_random_items(length, 0, length / 10)
    vec = do_stable_partial_sort(vec, false, limit)
    assert_equal true, stably_sorted?(vec, limit, false)
  end

  # -- predicate validation tests --

  # Java: PartialSortTest#testPredicate1
  it "validates isPartiallySorted predicate on int arrays" do
    size = 10_000
    error_count = 0

    # all sorted, ascending
    key = 0
    vec = Array.new(size) do |i|
      v = key
      key += i % 3
      v
    end
    error_count += 1 if partially_sorted_ints?(vec, size, true)
    error_count += 1 unless partially_sorted_ints?(vec, size, false)

    # partially sorted, ascending
    key = 0
    limit = 2000
    limit.times do |i|
      vec[i] = key
      key += i % 3
    end
    (limit...size).each do |i|
      vec[i] = 2 * key + rand(1000)
    end
    error_count += 1 if partially_sorted_ints?(vec, limit, true)
    error_count += 1 unless partially_sorted_ints?(vec, limit, false)

    # all sorted, descending
    key = 2 * size
    size.times do |i|
      vec[i] = key
      key -= i % 3
    end
    error_count += 1 unless partially_sorted_ints?(vec, size, true)
    error_count += 1 if partially_sorted_ints?(vec, size, false)

    # partially sorted, descending
    key = 2 * size
    limit = 2000
    limit.times do |i|
      vec[i] = key
      key -= i % 3
    end
    (limit...size).each do |i|
      vec[i] = key - rand(size)
    end
    error_count += 1 unless partially_sorted_ints?(vec, limit, true)
    error_count += 1 if partially_sorted_ints?(vec, limit, false)

    assert_equal 0, error_count
  end

  # Java: PartialSortTest#testPredicate2
  it "validates isPartiallySorted predicate on Integer arrays" do
    size = 10_000
    error_count = 0

    # all sorted, ascending
    key = 0
    vec = Array.new(size) do |i|
      v = key
      key += i % 3
      v
    end
    error_count += 1 if partially_sorted?(vec, size, true)
    error_count += 1 unless partially_sorted?(vec, size, false)

    # partially sorted, ascending
    key = 0
    limit = 2000
    limit.times do |i|
      vec[i] = key
      key += i % 3
    end
    (limit...size).each do |i|
      vec[i] = 2 * key + rand(1000)
    end
    error_count += 1 if partially_sorted?(vec, limit, true)
    error_count += 1 unless partially_sorted?(vec, limit, false)

    # all sorted, descending
    key = 2 * size
    size.times do |i|
      vec[i] = key
      key -= i % 3
    end
    error_count += 1 unless partially_sorted?(vec, size, true)
    error_count += 1 if partially_sorted?(vec, size, false)

    # partially sorted, descending
    key = 2 * size
    limit = 2000
    limit.times do |i|
      vec[i] = key
      key -= i % 3
    end
    (limit...size).each do |i|
      vec[i] = key - rand(size)
    end
    error_count += 1 unless partially_sorted?(vec, limit, true)
    error_count += 1 if partially_sorted?(vec, limit, false)

    assert_equal 0, error_count
  end

  # -- partialSort tests --

  # Java: PartialSortTest#testQuick
  it "partial sorts a small random array descending" do
    length = 40
    limit = 4
    vec = new_random_integers(length, 0, length)
    do_partial_sort(vec, true, limit)
    assert_equal true, partially_sorted_java?(vec, limit, true)
  end

  # Java: PartialSortTest#testOnAlreadySorted
  it "partial sorts an already sorted array ascending" do
    length = 200
    limit = 8
    vec = (0...length).map { |i| java.lang.Integer.new(i) }.to_java(java.lang.Object)
    do_partial_sort(vec, false, limit)
    assert_equal true, partially_sorted_java?(vec, limit, false)
  end

  # Java: PartialSortTest#testOnAlreadyReverseSorted
  it "partial sorts an already reverse-sorted array ascending" do
    length = 200
    limit = 8
    vec = (0...length).map { |i| java.lang.Integer.new(length - i) }.to_java(java.lang.Object)
    do_partial_sort(vec, false, limit)
    assert_equal true, partially_sorted_java?(vec, limit, false)
  end

  # Java: PartialSortTest#testOnRandomIntegers
  it "partial sorts random integers of various sizes" do
    random_integer_tests(100, 20)
    random_integer_tests(50_000, 10)
    random_integer_tests(50_000, 500)
    random_integer_tests(50_000, 12_000)
  end

  # Java: PartialSortTest#testOnManyRandomIntegers
  it "partial sorts large arrays of random integers" do
    random_integer_tests(1_000_000, 5000)
    random_integer_tests(1_000_000, 10)
  end

  # -- stable partial sort tests --

  # Java: PartialSortTest#testPredicateIsStablySorted
  it "validates isStablySorted predicate on Item arrays" do
    vec = new_partly_sorted_items(24, 4, false)
    assert_equal true, stably_sorted?(vec, 4, false)
    assert_equal false, stably_sorted?(vec, 4, true)

    vec = new_partly_sorted_items(24, 8, true)
    assert_equal true, stably_sorted?(vec, 4, true)
    assert_equal false, stably_sorted?(vec, 4, false)

    vec = new_partly_sorted_items(1000, 100, true)
    assert_equal true, stably_sorted?(vec, 100, true)
    assert_equal true, stably_sorted?(vec, 20, true)
    assert_equal true, stably_sorted?(vec, 4, true)
  end

  # Java: PartialSortTest#testStableQuick
  it "stable partial sorts a small random array descending" do
    length = 40
    limit = 4
    vec = new_random_items(length, 0, length)
    vec = do_stable_partial_sort(vec, true, limit)
    assert_equal true, stably_sorted?(vec, limit, true)
  end

  # Java: PartialSortTest#testStableOnRandomItems
  it "stable partial sorts random items of various sizes" do
    random_item_tests(100, 20)
    random_item_tests(50_000, 10)
    random_item_tests(50_000, 500)
    random_item_tests(50_000, 12_000)
  end

  # Java: PartialSortTest#testSpeed
  # Skipped: performance/logging test, not applicable to JRuby migration
end
