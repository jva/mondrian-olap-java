# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (c) 2002-2017 Hitachi Vantara. All rights reserved.
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Load servlet API and JSP API JARs needed by XmlaSupport/MockHttpServletRequest
require File.expand_path("~/.m2/repository/javax/servlet/servlet-api/2.4/servlet-api-2.4.jar")
require File.expand_path("~/.m2/repository/javax/servlet/jsp-api/2.0/jsp-api-2.0.jar")

# Java: mondrian/xmla/XmlaErrorTest.java
describe "XmlaError" do
  XmlaSupport = Java::MondrianTui::XmlaSupport
  XmlaException = Java::MondrianXmla::XmlaException
  XmlaConstants = Java::MondrianXmla::XmlaConstants
  MockHttpServletRequest = Java::MondrianTui::MockHttpServletRequest
  MockHttpServletResponse = Java::MondrianTui::MockHttpServletResponse
  Base64 = Java::MondrianUtil::Base64
  XmlaRequestCallback = Java::MondrianXmla::XmlaRequestCallback

  # Fault code categories
  CLIENT_FAULT_FC = XmlaConstants::CLIENT_FAULT_FC
  MUST_UNDERSTAND_FAULT_FC = XmlaConstants::MUST_UNDERSTAND_FAULT_FC
  FAULT_ACTOR = XmlaConstants::FAULT_ACTOR
  MONDRIAN_NAMESPACE = XmlaConstants::MONDRIAN_NAMESPACE

  # Error codes
  USM_DOM_PARSE_CODE = XmlaConstants::USM_DOM_PARSE_CODE
  USM_DOM_PARSE_FAULT_FS = XmlaConstants::USM_DOM_PARSE_FAULT_FS
  HSB_BAD_SOAP_BODY_CODE = XmlaConstants::HSB_BAD_SOAP_BODY_CODE
  HSB_BAD_SOAP_BODY_FAULT_FS = XmlaConstants::HSB_BAD_SOAP_BODY_FAULT_FS
  CHH_AUTHORIZATION_CODE = XmlaConstants::CHH_AUTHORIZATION_CODE
  CHH_AUTHORIZATION_FAULT_FS = XmlaConstants::CHH_AUTHORIZATION_FAULT_FS
  HSH_MUST_UNDERSTAND_CODE = XmlaConstants::HSH_MUST_UNDERSTAND_CODE
  HSH_MUST_UNDERSTAND_FAULT_FS = XmlaConstants::HSH_MUST_UNDERSTAND_FAULT_FS
  HSB_BAD_REQUEST_TYPE_CODE = XmlaConstants::HSB_BAD_REQUEST_TYPE_CODE
  HSB_BAD_REQUEST_TYPE_FAULT_FS = XmlaConstants::HSB_BAD_REQUEST_TYPE_FAULT_FS
  HSB_BAD_RESTRICTIONS_CODE = XmlaConstants::HSB_BAD_RESTRICTIONS_CODE
  HSB_BAD_RESTRICTIONS_FAULT_FS = XmlaConstants::HSB_BAD_RESTRICTIONS_FAULT_FS
  HSB_BAD_PROPERTIES_CODE = XmlaConstants::HSB_BAD_PROPERTIES_CODE
  HSB_BAD_PROPERTIES_FAULT_FS = XmlaConstants::HSB_BAD_PROPERTIES_FAULT_FS
  HSB_BAD_COMMAND_CODE = XmlaConstants::HSB_BAD_COMMAND_CODE
  HSB_BAD_COMMAND_FAULT_FS = XmlaConstants::HSB_BAD_COMMAND_FAULT_FS
  HSB_BAD_PROPERTIES_LIST_CODE = XmlaConstants::HSB_BAD_PROPERTIES_LIST_CODE
  HSB_BAD_PROPERTIES_LIST_FAULT_FS = XmlaConstants::HSB_BAD_PROPERTIES_LIST_FAULT_FS
  HSB_BAD_RESTRICTION_LIST_CODE = XmlaConstants::HSB_BAD_RESTRICTION_LIST_CODE
  HSB_BAD_RESTRICTION_LIST_FAULT_FS = XmlaConstants::HSB_BAD_RESTRICTION_LIST_FAULT_FS
  HSB_BAD_STATEMENT_CODE = XmlaConstants::HSB_BAD_STATEMENT_CODE
  HSB_BAD_STATEMENT_FAULT_FS = XmlaConstants::HSB_BAD_STATEMENT_FAULT_FS
  HSB_DRILL_THROUGH_FORMAT_CODE = XmlaConstants::HSB_DRILL_THROUGH_FORMAT_CODE
  HSB_DRILL_THROUGH_FORMAT_FAULT_FS = XmlaConstants::HSB_DRILL_THROUGH_FORMAT_FAULT_FS

  before(:all) do
    create_olap_connection
    connect_string = @olap.raw_mondrian_connection.getConnectInfo.toString
    catalog_urls = java.util.TreeMap.new
    catalog_urls.put("FoodMart", CATALOG_FILE)
    @servlet_cache = java.util.HashMap.new
    @servlet = XmlaSupport.makeServlet(connect_string, catalog_urls, nil, @servlet_cache)

    # Suppress stderr during tests since XMLA error processing writes SAX errors to stderr
    @original_err = java.lang.System.err
    java.lang.System.setErr(java.io.PrintStream.new(java.io.ByteArrayOutputStream.new))
  end

  after(:all) do
    java.lang.System.setErr(@original_err) if @original_err
    @olap&.close
  end

  # Extracts child Element nodes from a DOM node
  def get_child_elements(node)
    nlist = node.getChildNodes
    elements = []
    (0...nlist.getLength).each do |i|
      child = nlist.item(i)
      elements << child if child.getNodeType == Java::OrgW3cDom::Node::ELEMENT_NODE
    end
    elements
  end

  # Extracts text content from a DOM node
  def get_node_content(node)
    nlist = node.getChildNodes
    (0...nlist.getLength).each do |i|
      child = nlist.item(i)
      if child.getNodeType == Java::OrgW3cDom::Node::TEXT_NODE ||
         child.getNodeType == Java::OrgW3cDom::Node::CDATA_SECTION_NODE
        return child.getData
      end
    end
    nil
  end

  # Sends a SOAP request to the servlet and asserts the expected SOAP Fault
  def assert_soap_fault(request_text, fault_code:, fault_string:, fault_actor:, error_ns: nil, error_code: nil)
    bytes = XmlaSupport.processSoapXmla(request_text, @servlet)
    fault_nodes = XmlaSupport.extractFaultNodesFromSoap(bytes)

    refute_nil fault_nodes, "Expected SOAP Fault but got none"
    assert fault_nodes.length >= 3, "SOAP Fault node has #{fault_nodes.length} children, expected at least 3"

    assert_equal fault_code, get_node_content(fault_nodes[0]), "faultcode mismatch"
    assert_equal fault_string, get_node_content(fault_nodes[1]), "faultstring mismatch"
    assert_equal fault_actor, get_node_content(fault_nodes[2]), "faultactor mismatch"

    if error_code
      assert fault_nodes.length > 3, "Expected detail element in SOAP Fault"
      detail_children = get_child_elements(fault_nodes[3])
      assert_equal 1, detail_children.length, "SOAP Fault detail node should have 1 child"

      error_node = detail_children[0]
      assert_equal error_ns, error_node.getNamespaceURI if error_ns

      error_children = get_child_elements(error_node)
      assert_equal 2, error_children.length, "SOAP Fault detail error node should have 2 children"
      assert_equal error_code, get_node_content(error_children[0]), "error code mismatch"
    end
  end

  # Sends a SOAP request via MockHttpServletRequest and asserts the expected SOAP Fault.
  # Used when custom HTTP headers need to be set (e.g., authorization tests).
  def assert_servlet_fault(request, expected_fault)
    response = MockHttpServletResponse.new
    response.setCharacterEncoding("UTF-8")
    @servlet.service(request, response)

    status_code = response.getStatusCode
    assert [200, 401].include?(status_code), "Bad status code: #{status_code}"

    bytes = response.toByteArray
    fault_nodes = XmlaSupport.extractFaultNodesFromSoap(bytes)

    refute_nil fault_nodes, "Expected SOAP Fault but got none"
    assert fault_nodes.length >= 3, "SOAP Fault node has #{fault_nodes.length} children, expected at least 3"

    assert_equal expected_fault[:fault_code], get_node_content(fault_nodes[0]), "faultcode mismatch"
    assert_equal expected_fault[:fault_string], get_node_content(fault_nodes[1]), "faultstring mismatch"
    assert_equal expected_fault[:fault_actor], get_node_content(fault_nodes[2]), "faultactor mismatch"

    if expected_fault[:error_code]
      assert fault_nodes.length > 3, "Expected detail element in SOAP Fault"
      detail_children = get_child_elements(fault_nodes[3])
      assert_equal 1, detail_children.length
      error_node = detail_children[0]
      assert_equal expected_fault[:error_ns], error_node.getNamespaceURI if expected_fault[:error_ns]
      error_children = get_child_elements(error_node)
      assert_equal 2, error_children.length
      assert_equal expected_fault[:error_code], get_node_content(error_children[0]), "error code mismatch"
    end
  end

  # Asserts that a SOAP request succeeds (no fault)
  def assert_no_soap_fault(request)
    response = MockHttpServletResponse.new
    response.setCharacterEncoding("UTF-8")
    @servlet.service(request, response)

    status_code = response.getStatusCode
    if status_code == 100
      # HTTP 100 Continue — clear Expect and Authorization headers, retry
      request.clearHeader(XmlaRequestCallback::EXPECT)
      request.clearHeader(XmlaRequestCallback::AUTHORIZATION)
      response = MockHttpServletResponse.new
      response.setCharacterEncoding("UTF-8")
      @servlet.service(request, response)
      status_code = response.getStatusCode
    end

    assert_equal 200, status_code, "Expected HTTP 200 but got #{status_code}"
    bytes = response.toByteArray
    fault_nodes = XmlaSupport.extractFaultNodesFromSoap(bytes)
    assert(fault_nodes.nil? || fault_nodes.length == 0, "Expected no SOAP Fault but got one")
  end

  def format_fault_code(fault_fc, code)
    XmlaException.formatFaultCode(fault_fc, code)
  end

  # Request XML payloads from XmlaErrorTest.ref.xml

  REQUEST_JUNK = "\n"

  REQUEST_BAD_XML_01 = <<~XML
    <soapenv:FOOEnvelope
        xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
        xmlns:xsd="http://www.w3.org/2001/XMLSchema"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <soapenv:Body>
    <ns1:Discover
        soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
        xmlns:ns1="urn:schemas-microsoft-com:xml-analysis">
        <ns1:RequestType xsi:type="xsd:string">DISCOVER_DATASOURCES</ns1:RequestType>
        <ns1:Restrictions>
            <ns1:RestrictionList/>
        </ns1:Restrictions>
        <ns1:Properties>
        </ns1:Properties>
    </ns1:Discover>
        </soapenv:Body>
    </soapenv:Envelope>
  XML

  REQUEST_BAD_XML_02 = <<~XML
    <soapenv:Envelope
        xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelopeFOO/"
        xmlns:xsd="http://www.w3.org/2001/XMLSchema"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <soapenv:Body>
    <ns1:Discover
        soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
        xmlns:ns1="urn:schemas-microsoft-com:xml-analysis">
        <ns1:RequestType xsi:type="xsd:string">DISCOVER_DATASOURCES</ns1:RequestType>
        <ns1:Restrictions>
            <ns1:RestrictionList/>
        </ns1:Restrictions>
        <ns1:Properties>
        </ns1:Properties>
    </ns1:Discover>
        </soapenv:Body>
    </soapenv:Envelope>
  XML

  REQUEST_BAD_ACTION_01 = <<~XML
    <soapenv:Envelope
        xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
        xmlns:xsd="http://www.w3.org/2001/XMLSchema"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <soapenv:Body>
    <ns1:FOODiscover
        soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
        xmlns:ns1="urn:schemas-microsoft-com:xml-analysis">
        <ns1:RequestType xsi:type="xsd:string">DISCOVER_DATASOURCES</ns1:RequestType>
        <ns1:Restrictions>
            <ns1:RestrictionList/>
        </ns1:Restrictions>
        <ns1:Properties>
        </ns1:Properties>
    </ns1:FOODiscover>
        </soapenv:Body>
    </soapenv:Envelope>
  XML

  REQUEST_BAD_ACTION_02 = <<~XML
    <soapenv:Envelope
        xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
        xmlns:xsd="http://www.w3.org/2001/XMLSchema"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <soapenv:Body>
    <ns1:Discover
        soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
        xmlns:ns1="urn:schemas-microsoft-com:xml-analysis">
        <ns1:RequestType xsi:type="xsd:string">DISCOVER_DATASOURCES</ns1:RequestType>
        <ns1:Restrictions>
            <ns1:RestrictionList/>
        </ns1:Restrictions>
        <ns1:Properties>
        </ns1:Properties>
    </ns1:Discover>
    <ns1:Discover
        soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
        xmlns:ns1="urn:schemas-microsoft-com:xml-analysis">
        <ns1:RequestType xsi:type="xsd:string">DISCOVER_DATASOURCES</ns1:RequestType>
        <ns1:Restrictions>
            <ns1:RestrictionList/>
        </ns1:Restrictions>
        <ns1:Properties>
        </ns1:Properties>
    </ns1:Discover>
        </soapenv:Body>
    </soapenv:Envelope>
  XML

  REQUEST_BAD_ACTION_03 = <<~XML
    <soapenv:Envelope
        xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
        xmlns:xsd="http://www.w3.org/2001/XMLSchema"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <soapenv:Body>
    <ns1:Discover
        soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
        xmlns:ns1="urn:schemas-microsoft-com:xml-analysis">
        <ns1:RequestType xsi:type="xsd:string">DISCOVER_DATASOURCES</ns1:RequestType>
        <ns1:Restrictions>
            <ns1:RestrictionList/>
        </ns1:Restrictions>
        <ns1:Properties>
        </ns1:Properties>
    </ns1:Discover>
        <ns2:Execute xmlns="urn:schemas-microsoft-com:xml-analysis"
            xmlns:ns2="urn:schemas-microsoft-com:xml-analysis">
          <ns2:Command>
            <ns2:Statement/>
          </ns2:Command>
          <ns2:Properties>
            <ns2:PropertyList>
              <ns2:LocaleIdentifier>1033</ns2:LocaleIdentifier>
              <ns2:DataSourceInfo>MondrianFoodMart</ns2:DataSourceInfo>
            </ns2:PropertyList>
          </ns2:Properties>
        </ns2:Execute>
        </soapenv:Body>
    </soapenv:Envelope>
  XML

  REQUEST_BAD_SOAP_01 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Header/>
      <Body>
        <Execute xmlns="urn:schemas-microsoft-com:xml-analysis">
          <Command>
            <Statement/>
          </Command>
          <Properties>
            <PropertyList>
              <LocaleIdentifier>1033</LocaleIdentifier>
              <DataSourceInfo>MondrianFoodMart</DataSourceInfo>
            </PropertyList>
          </Properties>
        </Execute>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_SOAP_02 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <Execute xmlns="urn:schemas-microsoft-com:xml-analysis">
          <Command>
            <Statement/>
          </Command>
          <Properties>
            <PropertyList>
              <LocaleIdentifier>1033</LocaleIdentifier>
              <DataSourceInfo>MondrianFoodMart</DataSourceInfo>
            </PropertyList>
          </Properties>
        </Execute>
      </Body>
      <Body>
        <Execute xmlns="urn:schemas-microsoft-com:xml-analysis">
          <Command>
            <Statement/>
          </Command>
          <Properties>
            <PropertyList>
              <LocaleIdentifier>1033</LocaleIdentifier>
              <DataSourceInfo>MondrianFoodMart</DataSourceInfo>
            </PropertyList>
          </Properties>
        </Execute>
      </Body>
    </Envelope>
  XML

  REQUEST_AUTH = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
      </Header>
      <Body>
        <Execute xmlns="urn:schemas-microsoft-com:xml-analysis">
          <Command>
            <Statement/>
          </Command>
          <Properties>
            <PropertyList>
              <LocaleIdentifier>1033</LocaleIdentifier>
              <DataSourceInfo>MondrianFoodMart</DataSourceInfo>
            </PropertyList>
          </Properties>
        </Execute>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_HEADER_01 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <XA:Foo mustUnderstand="1"
                xmlns:XA="urn:schemas-microsoft-com:xml-analysis" />
      </Header>
      <Body>
        <Execute xmlns="urn:schemas-microsoft-com:xml-analysis">
          <Command>
            <Statement/>
          </Command>
          <Properties>
            <PropertyList>
              <LocaleIdentifier>1033</LocaleIdentifier>
              <DataSourceInfo>MondrianFoodMart</DataSourceInfo>
            </PropertyList>
          </Properties>
        </Execute>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_BODY_01 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <Execute xmlns="urn:schemas-microsoft-com:xml-analysis">
          <Command>
            <Statement/>
          </Command>
          <Properties>
            <PropertyList>
              <LocaleIdentifier>1033</LocaleIdentifier>
              <DataSourceInfo>MondrianFoodMart</DataSourceInfo>
            </PropertyList>
          </Properties>
        </Execute>
        <Discover xmlns="urn:schemas-microsoft-com:xml-analysis">
          <RequestType>DISCOVER_DATASOURCES</RequestType>
          <Restrictions>
            <RestrictionList/>
          </Restrictions>
          <Properties>
            <PropertyList>
              <Content>Data</Content>
            </PropertyList>
          </Properties>
        </Discover>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_BODY_02 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <FooExecute xmlns="urn:schemas-microsoft-com:xml-analysis">
          <Command>
            <Statement/>
          </Command>
          <Properties>
            <PropertyList>
              <LocaleIdentifier>1033</LocaleIdentifier>
              <DataSourceInfo>MondrianFoodMart</DataSourceInfo>
            </PropertyList>
          </Properties>
        </FooExecute>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_BODY_03 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <Execute xmlns="urn:schemas-microsoft-com:xml-analysis-FOO">
          <Command>
            <Statement/>
          </Command>
          <Properties>
            <PropertyList>
              <LocaleIdentifier>1033</LocaleIdentifier>
              <DataSourceInfo>MondrianFoodMart</DataSourceInfo>
            </PropertyList>
          </Properties>
        </Execute>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_BODY_04 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <Discover xmlns="urn:schemas-microsoft-com:xml-analysis">
          <FOORequestType>DISCOVER_DATASOURCES</FOORequestType>
          <Restrictions>
            <RestrictionList/>
          </Restrictions>
          <Properties>
            <PropertyList>
              <Content>Data</Content>
            </PropertyList>
          </Properties>
        </Discover>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_BODY_05 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <Discover xmlns="urn:schemas-microsoft-com:xml-analysis">
          <RequestType>DISCOVER_DATASOURCES</RequestType>
          <FOORestrictions>
            <RestrictionList/>
          </FOORestrictions>
          <Properties>
            <PropertyList>
              <Content>Data</Content>
            </PropertyList>
          </Properties>
        </Discover>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_BODY_06 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <Discover xmlns="urn:schemas-microsoft-com:xml-analysis">
          <RequestType>DISCOVER_DATASOURCES</RequestType>
          <Restrictions>
            <RestrictionList/>
          </Restrictions>
          <FOOProperties>
            <PropertyList>
              <Content>Data</Content>
            </PropertyList>
          </FOOProperties>
        </Discover>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_BODY_07 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <Execute xmlns="urn:schemas-microsoft-com:xml-analysis">
          <FooCommand>
            <Statement/>
          </FooCommand>
          <Properties>
            <PropertyList>
              <LocaleIdentifier>1033</LocaleIdentifier>
              <DataSourceInfo>MondrianFoodMart</DataSourceInfo>
            </PropertyList>
          </Properties>
        </Execute>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_BODY_08 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <Execute xmlns="urn:schemas-microsoft-com:xml-analysis">
          <Command>
            <Statement/>
          </Command>
          <FooProperties>
            <PropertyList>
              <LocaleIdentifier>1033</LocaleIdentifier>
              <DataSourceInfo>MondrianFoodMart</DataSourceInfo>
            </PropertyList>
          </FooProperties>
        </Execute>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_BODY_09 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <Discover xmlns="urn:schemas-microsoft-com:xml-analysis">
          <RequestType>DISCOVER_DATASOURCES</RequestType>
          <Restrictions>
            <RestrictionList/>
            <RestrictionList/>
          </Restrictions>
          <Properties>
            <PropertyList>
              <Content>Data</Content>
            </PropertyList>
          </Properties>
        </Discover>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_BODY_10 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <Discover xmlns="urn:schemas-microsoft-com:xml-analysis">
          <RequestType>DISCOVER_DATASOURCES</RequestType>
          <Restrictions>
            <RestrictionList/>
          </Restrictions>
          <Properties>
            <PropertyList>
              <Content>Data</Content>
            </PropertyList>
            <PropertyList/>
          </Properties>
        </Discover>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_BODY_11 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <Execute xmlns="urn:schemas-microsoft-com:xml-analysis">
          <Command>
            <Statement/>
          </Command>
          <Properties>
            <PropertyList/>
            <PropertyList>
              <LocaleIdentifier>1033</LocaleIdentifier>
              <DataSourceInfo>MondrianFoodMart</DataSourceInfo>
            </PropertyList>
          </Properties>
        </Execute>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_BODY_12 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <Execute xmlns="urn:schemas-microsoft-com:xml-analysis">
          <Command>
            <Statement/>
            <Statement/>
          </Command>
          <Properties>
            <PropertyList>
              <LocaleIdentifier>1033</LocaleIdentifier>
              <DataSourceInfo>MondrianFoodMart</DataSourceInfo>
            </PropertyList>
          </Properties>
        </Execute>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_BODY_13 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <Execute xmlns="urn:schemas-microsoft-com:xml-analysis">
          <Command>
            <Statement>
    DRILLTHROUGH MAXROWS -1000
    SELECT {[Customers].[USA].[CA].[Berkeley]} ON 0,
    {[Time].[1997]} ON 1,
    {[Product].[Drink]} ON 2
    FROM Sales
            </Statement>
          </Command>
          <Properties>
            <PropertyList>
              <LocaleIdentifier>1033</LocaleIdentifier>
              <DataSourceInfo>MondrianFoodMart</DataSourceInfo>
            </PropertyList>
          </Properties>
        </Execute>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_BODY_14 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <Execute xmlns="urn:schemas-microsoft-com:xml-analysis">
          <Command>
            <Statement>
    DRILLTHROUGH MAXROWS 1000 FIRSTROWSET -200
    SELECT {[Customers].[USA].[CA].[Berkeley]} ON 0,
    {[Time].[1997]} ON 1,
    {[Product].[Drink]} ON 2
    FROM Sales
            </Statement>
          </Command>
          <Properties>
            <PropertyList>
              <LocaleIdentifier>1033</LocaleIdentifier>
              <DataSourceInfo>MondrianFoodMart</DataSourceInfo>
            </PropertyList>
          </Properties>
        </Execute>
      </Body>
    </Envelope>
  XML

  REQUEST_BAD_BODY_15 = <<~XML
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
      <Header>
        <Foo>Have a nice day</Foo>
      </Header>
      <Body>
        <Execute xmlns="urn:schemas-microsoft-com:xml-analysis">
          <Command>
            <Statement>
    SELECT {[Customers].[USA].[CA].[Berkeley]} ON 0,
    {[Time].[1997]} ON 1,
    {[Product].[Drink]} ON 2
    DRILLTHROUGH MAXROWS 1000 FIRSTROWSET 200
    FROM Sales
            </Statement>
          </Command>
          <Properties>
            <PropertyList>
              <LocaleIdentifier>1033</LocaleIdentifier>
              <DataSourceInfo>MondrianFoodMart</DataSourceInfo>
            </PropertyList>
          </Properties>
        </Execute>
      </Body>
    </Envelope>
  XML

  describe "bad XML" do
    # Java: XmlaErrorTest#testJunk
    it "rejects junk input that is not XML" do
      assert_soap_fault REQUEST_JUNK,
        fault_code: format_fault_code(CLIENT_FAULT_FC, USM_DOM_PARSE_CODE),
        fault_string: USM_DOM_PARSE_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: USM_DOM_PARSE_CODE
    end

    # Java: XmlaErrorTest#testBadXml01
    it "rejects bad SOAP envelope element tag" do
      assert_soap_fault REQUEST_BAD_XML_01,
        fault_code: format_fault_code(CLIENT_FAULT_FC, USM_DOM_PARSE_CODE),
        fault_string: USM_DOM_PARSE_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: USM_DOM_PARSE_CODE
    end

    # Java: XmlaErrorTest#testBadXml02
    it "rejects bad SOAP namespace" do
      assert_soap_fault REQUEST_BAD_XML_02,
        fault_code: format_fault_code(CLIENT_FAULT_FC, USM_DOM_PARSE_CODE),
        fault_string: USM_DOM_PARSE_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: USM_DOM_PARSE_CODE
    end
  end

  describe "bad action" do
    # Java: XmlaErrorTest#testBadAction01
    it "rejects unknown SOAP action element" do
      assert_soap_fault REQUEST_BAD_ACTION_01,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_BAD_SOAP_BODY_CODE),
        fault_string: HSB_BAD_SOAP_BODY_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_BAD_SOAP_BODY_CODE
    end

    # Java: XmlaErrorTest#testBadAction02
    it "rejects multiple action elements in SOAP body" do
      assert_soap_fault REQUEST_BAD_ACTION_02,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_BAD_SOAP_BODY_CODE),
        fault_string: HSB_BAD_SOAP_BODY_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_BAD_SOAP_BODY_CODE
    end

    # Java: XmlaErrorTest#testBadAction03
    it "rejects mixed Discover and Execute elements in SOAP body" do
      assert_soap_fault REQUEST_BAD_ACTION_03,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_BAD_SOAP_BODY_CODE),
        fault_string: HSB_BAD_SOAP_BODY_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_BAD_SOAP_BODY_CODE
    end
  end

  describe "bad SOAP structure" do
    # Java: XmlaErrorTest#testBadSoap01
    it "rejects duplicate Header elements" do
      assert_soap_fault REQUEST_BAD_SOAP_01,
        fault_code: format_fault_code(CLIENT_FAULT_FC, USM_DOM_PARSE_CODE),
        fault_string: USM_DOM_PARSE_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: USM_DOM_PARSE_CODE
    end

    # Java: XmlaErrorTest#testBadSoap02
    it "rejects duplicate Body elements" do
      assert_soap_fault REQUEST_BAD_SOAP_02,
        fault_code: format_fault_code(CLIENT_FAULT_FC, USM_DOM_PARSE_CODE),
        fault_string: USM_DOM_PARSE_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: USM_DOM_PARSE_CODE
    end
  end

  describe "authorization" do
    # Tests testAuth01-05 require a custom XmlaRequestCallback registered with the servlet.
    # The Java test uses an inner Callback class that is instantiated via Class.forName() during
    # servlet init, which is not compatible with JRuby classes. These tests verify callback-driven
    # authorization fault handling. The original Java comments note these tests "can be removed
    # if desired" since authorization is normally handled at the webserver level.

    # Java: XmlaErrorTest#testAuth01
    it("rejects missing authorization header") { skip "requires Java callback class for servlet init" }

    # Java: XmlaErrorTest#testAuth02
    it("rejects badly encoded authorization") { skip "requires Java callback class for servlet init" }

    # Java: XmlaErrorTest#testAuth03
    it("accepts valid authorization credentials") { skip "requires Java callback class for servlet init" }

    # Java: XmlaErrorTest#testAuth04
    it("rejects bad username") { skip "requires Java callback class for servlet init" }

    # Java: XmlaErrorTest#testAuth05
    it("rejects bad password") { skip "requires Java callback class for servlet init" }
  end

  describe "bad header" do
    # Java: XmlaErrorTest#testBadHeader01
    it "rejects mustUnderstand header element" do
      assert_soap_fault REQUEST_BAD_HEADER_01,
        fault_code: format_fault_code(MUST_UNDERSTAND_FAULT_FC, HSH_MUST_UNDERSTAND_CODE),
        fault_string: HSH_MUST_UNDERSTAND_FAULT_FS,
        fault_actor: FAULT_ACTOR
      # Headers errors do not have detail sections
    end
  end

  describe "bad body" do
    # Java: XmlaErrorTest#testBadBody01
    it "rejects multiple action elements in body" do
      assert_soap_fault REQUEST_BAD_BODY_01,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_BAD_SOAP_BODY_CODE),
        fault_string: HSB_BAD_SOAP_BODY_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_BAD_SOAP_BODY_CODE
    end

    # Java: XmlaErrorTest#testBadBody02
    it "rejects unknown action element name" do
      assert_soap_fault REQUEST_BAD_BODY_02,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_BAD_SOAP_BODY_CODE),
        fault_string: HSB_BAD_SOAP_BODY_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_BAD_SOAP_BODY_CODE
    end

    # Java: XmlaErrorTest#testBadBody03
    it "rejects action element with wrong namespace" do
      assert_soap_fault REQUEST_BAD_BODY_03,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_BAD_SOAP_BODY_CODE),
        fault_string: HSB_BAD_SOAP_BODY_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_BAD_SOAP_BODY_CODE
    end

    # Java: XmlaErrorTest#testBadBody04
    it "rejects bad Discover RequestType element" do
      assert_soap_fault REQUEST_BAD_BODY_04,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_BAD_REQUEST_TYPE_CODE),
        fault_string: HSB_BAD_REQUEST_TYPE_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_BAD_REQUEST_TYPE_CODE
    end

    # Java: XmlaErrorTest#testBadBody05
    it "rejects bad Discover Restrictions element" do
      assert_soap_fault REQUEST_BAD_BODY_05,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_BAD_RESTRICTIONS_CODE),
        fault_string: HSB_BAD_RESTRICTIONS_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_BAD_RESTRICTIONS_CODE
    end

    # Java: XmlaErrorTest#testBadBody06
    it "rejects bad Discover Properties element" do
      assert_soap_fault REQUEST_BAD_BODY_06,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_BAD_PROPERTIES_CODE),
        fault_string: HSB_BAD_PROPERTIES_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_BAD_PROPERTIES_CODE
    end

    # Java: XmlaErrorTest#testBadBody07
    it "rejects bad Execute Command element" do
      assert_soap_fault REQUEST_BAD_BODY_07,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_BAD_COMMAND_CODE),
        fault_string: HSB_BAD_COMMAND_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_BAD_COMMAND_CODE
    end

    # Java: XmlaErrorTest#testBadBody08
    it "rejects bad Execute Properties element" do
      assert_soap_fault REQUEST_BAD_BODY_08,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_BAD_PROPERTIES_CODE),
        fault_string: HSB_BAD_PROPERTIES_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_BAD_PROPERTIES_CODE
    end

    # Java: XmlaErrorTest#testBadBody09
    it "rejects too many Discover RestrictionList elements" do
      assert_soap_fault REQUEST_BAD_BODY_09,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_BAD_RESTRICTION_LIST_CODE),
        fault_string: HSB_BAD_RESTRICTION_LIST_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_BAD_RESTRICTION_LIST_CODE
    end

    # Java: XmlaErrorTest#testBadBody10
    it "rejects too many Discover PropertyList elements" do
      assert_soap_fault REQUEST_BAD_BODY_10,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_BAD_PROPERTIES_LIST_CODE),
        fault_string: HSB_BAD_PROPERTIES_LIST_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_BAD_PROPERTIES_LIST_CODE
    end

    # Java: XmlaErrorTest#testBadBody11
    it "rejects too many Execute PropertyList elements" do
      assert_soap_fault REQUEST_BAD_BODY_11,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_BAD_PROPERTIES_LIST_CODE),
        fault_string: HSB_BAD_PROPERTIES_LIST_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_BAD_PROPERTIES_LIST_CODE
    end

    # Java: XmlaErrorTest#testBadBody12
    it "rejects too many Statement elements in Command" do
      assert_soap_fault REQUEST_BAD_BODY_12,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_BAD_STATEMENT_CODE),
        fault_string: HSB_BAD_STATEMENT_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_BAD_STATEMENT_CODE
    end

    # Java: XmlaErrorTest#testBadBody13
    it "rejects DRILLTHROUGH with negative MAXROWS" do
      assert_soap_fault REQUEST_BAD_BODY_13,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_DRILL_THROUGH_FORMAT_CODE),
        fault_string: HSB_DRILL_THROUGH_FORMAT_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_DRILL_THROUGH_FORMAT_CODE
    end

    # Java: XmlaErrorTest#testBadBody14
    it "rejects DRILLTHROUGH with negative FIRSTROWSET" do
      assert_soap_fault REQUEST_BAD_BODY_14,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_DRILL_THROUGH_FORMAT_CODE),
        fault_string: HSB_DRILL_THROUGH_FORMAT_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_DRILL_THROUGH_FORMAT_CODE
    end

    # Java: XmlaErrorTest#testBadBody15
    it "rejects DRILLTHROUGH in wrong position in MDX" do
      assert_soap_fault REQUEST_BAD_BODY_15,
        fault_code: format_fault_code(CLIENT_FAULT_FC, HSB_DRILL_THROUGH_FORMAT_CODE),
        fault_string: HSB_DRILL_THROUGH_FORMAT_FAULT_FS,
        fault_actor: FAULT_ACTOR,
        error_ns: MONDRIAN_NAMESPACE,
        error_code: HSB_DRILL_THROUGH_FORMAT_CODE
    end
  end
end
