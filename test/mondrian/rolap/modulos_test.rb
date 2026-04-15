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

Modulos = Java::MondrianRolap::Modulos
RolapAxis = Java::MondrianRolap::RolapAxis
UnaryTupleList = Java::MondrianCalcImpl::UnaryTupleList

# Java: mondrian/rolap/ModulosTest.java
describe "Modulos" do
  def new_position_list(size)
    UnaryTupleList.new(java.util.Collections.nCopies(size, nil))
  end

  def create_axes(*sizes)
    sizes.map { |s| RolapAxis.new(new_position_list(s)) }.to_java(Java::MondrianOlap::Axis)
  end

  describe "many-dimensional (3 axes)" do
    # Java: ModulosTest#testMany
    it "computes cell position from ordinal for 3 axes using Many implementation" do
      axes = create_axes(4, 3, 3)

      modulos = Modulos::Generator.createMany(axes)
      ordinal = 23

      pos = modulos.getCellPos(ordinal)
      assert_equal 3, pos.length, "Pos length equals 3"
      assert_equal 3, pos[0], "Pos[0] equals 3"
      assert_equal 2, pos[1], "Pos[1] equals 2"
      assert_equal 1, pos[2], "Pos[2] equals 1"
    end
  end

  describe "one-dimensional" do
    # Java: ModulosTest#testOne
    it "produces identical results from Many and One implementations" do
      axes = create_axes(53)

      modulos_many = Modulos::Generator.createMany(axes)
      modulos = Modulos::Generator.create(axes)

      # Test getCellPos for various ordinals
      [43, 23, 7].each do |ordinal|
        pos_many = modulos_many.getCellPos(ordinal)
        pos = modulos.getCellPos(ordinal)
        assert_equal pos_many.to_a, pos.to_a, "Pos are not equal for ordinal #{ordinal}"
      end

      # Test getCellOrdinal for various positions
      [23, 11, 7].each do |p|
        pos = [p].to_java(:int)
        o_many = modulos_many.getCellOrdinal(pos)
        o = modulos.getCellOrdinal(pos)
        assert_equal o_many, o, "Ordinals are not equal for pos #{p}"
      end
    end
  end

  describe "two-dimensional" do
    # Java: ModulosTest#testTwo
    it "produces identical results from Many and Two implementations" do
      axes = create_axes(23, 13)

      modulos_many = Modulos::Generator.createMany(axes)
      modulos = Modulos::Generator.create(axes)

      # Test getCellPos for various ordinals
      [23, 11, 7].each do |ordinal|
        pos_many = modulos_many.getCellPos(ordinal)
        pos = modulos.getCellPos(ordinal)
        assert_equal pos_many.to_a, pos.to_a, "Pos are not equal for ordinal #{ordinal}"
      end

      # Test getCellOrdinal for various positions
      [[3, 2], [2, 2], [1, 2]].each do |p0, p1|
        pos = [p0, p1].to_java(:int)
        o_many = modulos_many.getCellOrdinal(pos)
        o = modulos.getCellOrdinal(pos)
        assert_equal o_many, o, "Ordinals are not equal for pos [#{p0}, #{p1}]"
      end
    end
  end

  describe "three-dimensional" do
    # Java: ModulosTest#testThree
    it "produces identical results from Many and Three implementations" do
      axes = create_axes(4, 3, 2)

      modulos_many = Modulos::Generator.createMany(axes)
      modulos = Modulos::Generator.create(axes)

      # Test getCellPos for various ordinals
      [23, 11, 7].each do |ordinal|
        pos_many = modulos_many.getCellPos(ordinal)
        pos = modulos.getCellPos(ordinal)
        assert_equal pos_many.to_a, pos.to_a, "Pos are not equal for ordinal #{ordinal}"
      end

      # Test getCellOrdinal for various positions
      [[3, 2, 1], [2, 2, 1], [1, 2, 1]].each do |p0, p1, p2|
        pos = [p0, p1, p2].to_java(:int)
        o_many = modulos_many.getCellOrdinal(pos)
        o = modulos.getCellOrdinal(pos)
        assert_equal o_many, o, "Ordinals are not equal for pos [#{p0}, #{p1}, #{p2}]"
      end
    end
  end
end
