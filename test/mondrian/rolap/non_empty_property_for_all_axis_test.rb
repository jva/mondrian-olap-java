# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2006-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/NonEmptyPropertyForAllAxisTest.java
describe "NonEmptyPropertyForAllAxis" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Java: NonEmptyPropertyForAllAxisTest#testNonEmptyForAllAxesWithPropertySet
  it "applies non-empty on all axes when property is set" do
    with_properties(EnableNonEmptyOnAllAxis: true) do
      assert_query_returns @olap,
        "select {[Country].[USA].[OR].Children} on 0," \
        " {[Promotions].Members} on 1 " \
        "from [Sales] " \
        "where [Product].[All Products].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Light Beer]",
        <<~RESULT
          Axis #0:
          {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Light Beer]}
          Axis #1:
          {[Customers].[USA].[OR].[Albany]}
          {[Customers].[USA].[OR].[Corvallis]}
          {[Customers].[USA].[OR].[Lake Oswego]}
          {[Customers].[USA].[OR].[Lebanon]}
          {[Customers].[USA].[OR].[Portland]}
          {[Customers].[USA].[OR].[Woodburn]}
          Axis #2:
          {[Promotions].[All Promotions]}
          {[Promotions].[Cash Register Lottery]}
          {[Promotions].[No Promotion]}
          {[Promotions].[Saving Days]}
          Row #0: 4
          Row #0: 6
          Row #0: 5
          Row #0: 10
          Row #0: 6
          Row #0: 3
          Row #1:
          Row #1: 2
          Row #1:
          Row #1: 2
          Row #1:
          Row #1:
          Row #2: 4
          Row #2: 4
          Row #2: 3
          Row #2: 8
          Row #2: 6
          Row #2: 3
          Row #3:
          Row #3:
          Row #3: 2
          Row #3:
          Row #3:
          Row #3:
        RESULT
    end
  end

  # Java: NonEmptyPropertyForAllAxisTest#testNonEmptyForAllAxesWithOutPropertySet
  it "does not apply non-empty when property is not set" do
    assert_query_returns @olap,
      "SELECT {customers.USA.CA.[Santa Cruz].[Brian Merlo]} on 0, " \
      "[product].[product category].members on 1 FROM [sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Customers].[USA].[CA].[Santa Cruz].[Brian Merlo]}
        Axis #2:
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine]}
        {[Product].[Drink].[Beverages].[Carbonated Beverages]}
        {[Product].[Drink].[Beverages].[Drinks]}
        {[Product].[Drink].[Beverages].[Hot Beverages]}
        {[Product].[Drink].[Beverages].[Pure Juice Beverages]}
        {[Product].[Drink].[Dairy].[Dairy]}
        {[Product].[Food].[Baked Goods].[Bread]}
        {[Product].[Food].[Baking Goods].[Baking Goods]}
        {[Product].[Food].[Baking Goods].[Jams and Jellies]}
        {[Product].[Food].[Breakfast Foods].[Breakfast Foods]}
        {[Product].[Food].[Canned Foods].[Canned Anchovies]}
        {[Product].[Food].[Canned Foods].[Canned Clams]}
        {[Product].[Food].[Canned Foods].[Canned Oysters]}
        {[Product].[Food].[Canned Foods].[Canned Sardines]}
        {[Product].[Food].[Canned Foods].[Canned Shrimp]}
        {[Product].[Food].[Canned Foods].[Canned Soup]}
        {[Product].[Food].[Canned Foods].[Canned Tuna]}
        {[Product].[Food].[Canned Foods].[Vegetables]}
        {[Product].[Food].[Canned Products].[Fruit]}
        {[Product].[Food].[Dairy].[Dairy]}
        {[Product].[Food].[Deli].[Meat]}
        {[Product].[Food].[Deli].[Side Dishes]}
        {[Product].[Food].[Eggs].[Eggs]}
        {[Product].[Food].[Frozen Foods].[Breakfast Foods]}
        {[Product].[Food].[Frozen Foods].[Frozen Desserts]}
        {[Product].[Food].[Frozen Foods].[Frozen Entrees]}
        {[Product].[Food].[Frozen Foods].[Meat]}
        {[Product].[Food].[Frozen Foods].[Pizza]}
        {[Product].[Food].[Frozen Foods].[Vegetables]}
        {[Product].[Food].[Meat].[Meat]}
        {[Product].[Food].[Produce].[Fruit]}
        {[Product].[Food].[Produce].[Packaged Vegetables]}
        {[Product].[Food].[Produce].[Specialty]}
        {[Product].[Food].[Produce].[Vegetables]}
        {[Product].[Food].[Seafood].[Seafood]}
        {[Product].[Food].[Snack Foods].[Snack Foods]}
        {[Product].[Food].[Snacks].[Candy]}
        {[Product].[Food].[Starchy Foods].[Starchy Foods]}
        {[Product].[Non-Consumable].[Carousel].[Specialty]}
        {[Product].[Non-Consumable].[Checkout].[Hardware]}
        {[Product].[Non-Consumable].[Checkout].[Miscellaneous]}
        {[Product].[Non-Consumable].[Health and Hygiene].[Bathroom Products]}
        {[Product].[Non-Consumable].[Health and Hygiene].[Cold Remedies]}
        {[Product].[Non-Consumable].[Health and Hygiene].[Decongestants]}
        {[Product].[Non-Consumable].[Health and Hygiene].[Hygiene]}
        {[Product].[Non-Consumable].[Health and Hygiene].[Pain Relievers]}
        {[Product].[Non-Consumable].[Household].[Bathroom Products]}
        {[Product].[Non-Consumable].[Household].[Candles]}
        {[Product].[Non-Consumable].[Household].[Cleaning Supplies]}
        {[Product].[Non-Consumable].[Household].[Electrical]}
        {[Product].[Non-Consumable].[Household].[Hardware]}
        {[Product].[Non-Consumable].[Household].[Kitchen Products]}
        {[Product].[Non-Consumable].[Household].[Paper Products]}
        {[Product].[Non-Consumable].[Household].[Plastic Products]}
        {[Product].[Non-Consumable].[Periodicals].[Magazines]}
        Row #0: 2
        Row #1: 2
        Row #2:
        Row #3:
        Row #4:
        Row #5:
        Row #6:
        Row #7:
        Row #8:
        Row #9:
        Row #10:
        Row #11:
        Row #12:
        Row #13:
        Row #14:
        Row #15:
        Row #16:
        Row #17:
        Row #18:
        Row #19:
        Row #20:
        Row #21:
        Row #22: 1
        Row #23:
        Row #24:
        Row #25:
        Row #26:
        Row #27:
        Row #28: 1
        Row #29:
        Row #30:
        Row #31:
        Row #32:
        Row #33:
        Row #34:
        Row #35:
        Row #36:
        Row #37:
        Row #38:
        Row #39:
        Row #40:
        Row #41:
        Row #42:
        Row #43:
        Row #44:
        Row #45:
        Row #46:
        Row #47:
        Row #48:
        Row #49:
        Row #50: 1
        Row #51:
        Row #52:
        Row #53:
        Row #54: 2
      RESULT
  end

  # Java: NonEmptyPropertyForAllAxisTest#testSlicerAxisDoesNotGetNonEmptyApplied
  it "does not apply non-empty to slicer axis" do
    with_properties(EnableNonEmptyOnAllAxis: true) do
      mdx = "select from [Sales]\nwhere [Time].[1997]\n"
      connection = @olap.raw_mondrian_connection
      query = connection.parseQuery(mdx)
      assert_equal mdx, query.toString
    end
  end
end
