# frozen_string_literal: true

require_relative "test_helper"

# Util.lookup resolves an identifier like [Store].[USA].[WA].[VALUE] as a
# property reference when no member has that name. The member of the property
# reference must pass the same role check as a direct member reference.
# Otherwise a role that denies [WA] or [Measures].[Store Sales] does not stop
# a query that reads the cell value through the VALUE property.
describe "Property reference role access" do
  before(:all) do
    @schema = define_schema do
      cube 'Sales' do
        table 'sales_fact_1997'
        dimension 'Store', foreign_key: 'store_id' do
          hierarchy has_all: true, all_member_name: 'All Stores', primary_key: 'store_id' do
            table 'store'
            level 'Store Country', column: 'store_country', unique_members: true
            level 'Store State', column: 'store_state', unique_members: true
            level 'Store City', column: 'store_city', unique_members: false
          end
        end
        measure 'Unit Sales', column: 'unit_sales', aggregator: 'sum'
        measure 'Store Sales', column: 'store_sales', aggregator: 'sum'
      end
      role 'No WA' do
        schema_grant access: 'none' do
          cube_grant cube: 'Sales', access: 'all' do
            hierarchy_grant hierarchy: '[Measures]', access: 'custom' do
              member_grant member: '[Measures].[Unit Sales]', access: 'all'
            end
            hierarchy_grant hierarchy: '[Store]', access: 'custom', rollup_policy: 'partial' do
              member_grant member: '[Store].[USA]', access: 'all'
              member_grant member: '[Store].[USA].[WA]', access: 'none'
            end
          end
        end
      end
    end
    @olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS.except(:catalog).merge(schema: @schema))
  end

  after(:all) do
    @olap&.close
  end

  after do
    @olap.role_name = nil
  end

  def calculated_value(formula)
    @olap.from('Sales').
      with_member('[Measures].[m]').as(formula).
      columns('[Measures].[m]').execute.values[0]
  end

  def unit_sales(member)
    @olap.from('Sales').columns('[Measures].[Unit Sales]').where(member).execute.values[0]
  end

  def assert_not_found(formula, object_name = formula)
    error = assert_raises(Mondrian::OLAP::Error) { calculated_value(formula) }
    assert_match(/MDX object '#{Regexp.escape(object_name)}' not found in cube 'Sales'/, error.root_cause_message)
  end

  describe "without a role" do
    it "should read the value of a member through the VALUE property" do
      assert_equal unit_sales('[Store].[USA].[WA]'), calculated_value('[Store].[USA].[WA].[VALUE]')
    end

    it "should read the value of a measure through the VALUE property" do
      refute_nil calculated_value('[Measures].[Store Sales].[VALUE]')
    end
  end

  describe "with a role" do
    before do
      @olap.role_name = 'No WA'
    end

    it "should not resolve a property of a denied member" do
      assert_not_found '[Store].[USA].[WA].[VALUE]'
    end

    # The parser resolves the member of an unbracketed property separately.
    it "should not resolve a property of a denied member without brackets" do
      assert_not_found '[Store].[USA].[WA].VALUE', '[Store].[USA].[WA]'
    end

    it "should not resolve the key of a denied member" do
      assert_not_found '[Store].[USA].[WA].[MEMBER_KEY]'
    end

    it "should not resolve a property of a child of a denied member" do
      assert_not_found '[Store].[USA].[WA].[Seattle].[VALUE]'
    end

    it "should not resolve a property of a denied measure" do
      assert_not_found '[Measures].[Store Sales].[VALUE]'
    end

    it "should resolve a property of a permitted member" do
      assert_equal unit_sales('[Store].[USA].[CA]'), calculated_value('[Store].[USA].[CA].[VALUE]')
    end

    it "should apply the partial rollup to a property of a member with partial access" do
      usa = unit_sales('[Store].[USA]')
      assert_equal unit_sales('[Store].[USA].[CA]') + unit_sales('[Store].[USA].[OR]'), usa
      assert_equal usa, calculated_value('[Store].[USA].[VALUE]')
    end
  end
end
