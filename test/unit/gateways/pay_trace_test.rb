require 'test_helper'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PayTraceGateway < Gateway
      def acquire_access_token
        @options[:access_token] = SecureRandom.hex(16)
      end
    end
  end
end

class PayTraceTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = PayTraceGateway.new(username: 'username', password: 'password', integrator_id: 'uniqueintegrator')
    @credit_card = credit_card
    @amount = 100

    @options = {
      billing_address: address
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 392483066, response.authorization
  end

  def test_successful_purchase_with_level_3_data
    @gateway.expects(:ssl_post).times(2).returns(successful_purchase_response).then.returns(successful_level_3_response)

    options = {
      visa_or_mastercard: 'visa',
      invoice_id: 'inv12345',
      customer_reference_id: '123abcd',
      tax_amount: 499,
      national_tax_amount: 172,
      merchant_tax_id: '3456defg',
      customer_tax_id: '3456test',
      commodity_code: '4321',
      discount_amount: 99,
      freight_amount: 75,
      duty_amount: 32,
      source_address: {
        zip: '94947'
      },
      shipping_address: {
        zip: '94948',
        country: 'US'
      },
      additional_tax_amount: 4,
      additional_tax_rate: 1,
      line_items: [
        {
          additional_tax_amount: 0,
            additional_tax_rate: 8,
            amount: 1999,
            commodity_code: '123commodity',
            description: 'plumbing',
            discount_amount: 327,
            product_id: 'skucode123',
            quantity: 4,
            unit_of_measure: 'EACH',
            unit_cost: 424
        }
      ]
    }

    response = @gateway.purchase(100, @credit_card, options)
    assert_success response
    assert_equal 170, response.params['response_code']
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal PayTraceGateway::STANDARD_ERROR_CODE[:declined], response.error_code
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_equal true, response.success?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'Your transaction was not approved.', response.message
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_capture_response)
    transaction_id = 10598543

    response = @gateway.capture(transaction_id, @options)
    assert_success response
    assert_equal 'Your transaction was successfully captured.', response.message
  end

  def test_successful_level_3_data_field_mapping
    authorization = 123456789
    options = {
      visa_or_mastercard: 'visa',
      address: {
        zip: '99201'
      }
    }
    stub_comms(@gateway) do
      @gateway.capture(authorization, options)
    end.check_request do |endpoint, data, _headers|
      next unless endpoint == 'https://api.paytrace.com/v1/level_three/visa'

      assert_match(/"source_address":{"zip":"99201"}/, data)
    end.respond_with(successful_level_3_visa)
  end

  def test_failed_capture
    @gateway.expects(:ssl_post).returns(failed_capture_response)

    response = @gateway.capture('', @options)
    assert_failure response
    assert_equal 'One or more errors has occurred.', response.message
  end

  def test_successful_refund
    transaction_id = 105968532
    @gateway.expects(:ssl_post).returns(successful_refund_response)

    response = @gateway.refund(transaction_id)
    assert_success response
    assert_equal 'Your transaction successfully refunded.', response.message
  end

  def test_failed_refund
    @gateway.expects(:ssl_post).returns(failed_refund_response)

    response = @gateway.refund('', @options.merge(amount: @amount))
    assert_failure response
    assert_equal 'One or more errors has occurred.', response.message
  end

  def test_successful_void
    transaction_id = 105968551
    @gateway.expects(:ssl_post).returns(successful_void_response)

    assert void = @gateway.void(transaction_id, @options)
    assert_success void
    assert_equal 'Your transaction was successfully voided.', void.message
  end

  def test_failed_void
    @gateway.expects(:ssl_post).returns(failed_void_response)

    response = @gateway.void('')
    assert_failure response
    assert_equal 'One or more errors has occurred.', response.message
  end

  def test_successful_verify
    @gateway.expects(:ssl_post).times(2).returns(successful_authorize_response).then.returns(successful_void_response)

    response = @gateway.verify(@credit_card, @options)
    assert_success response
  end

  def test_successful_verify_with_failed_void
    @gateway.expects(:ssl_post).times(2).returns(successful_authorize_response).then.returns(failed_void_response)

    response = @gateway.verify(@credit_card, @options)
    assert_success response
  end

  def test_failed_verify
    @gateway.expects(:ssl_post).times(1).returns(failed_authorize_response)

    response = @gateway.verify(@credit_card, @options)
    assert_failure response
    assert_equal 'Your transaction was not approved.', response.message
  end

  def test_successful_customer_creation
    @gateway.expects(:ssl_post).returns(successful_create_customer_response)

    response = @gateway.store(@credit_card, @options)
    assert_success response
    assert_equal true, response.success?
  end

  def test_duplicate_customer_creation
    options = {
      customer_id: '7cad678781bf0456d50e1478',
      billing_address: {
        address1: '8320 This Way Lane',
        city: 'Placeville',
        state: 'CA',
        zip: '85284'
      }
    }
    @gateway.expects(:ssl_post).returns(failed_customer_creation_response)
    response = @gateway.store(@credit_card, options)
    assert_failure response
    assert_equal false, response.success?
    assert_match 'Please provide a unique customer ID.', response.params['errors'].to_s
  end

  def test_scrub
    assert @gateway.supports_scrubbing?
    assert_equal @gateway.scrub(pre_scrubbed), post_scrubbed
  end

  private

  def pre_scrubbed
    <<-PRE_SCRUBBED
      opening connection to api.paytrace.com:443...
      opened
      starting SSL for api.paytrace.com:443...
      SSL established
      <- "POST /v1/transactions/sale/keyed HTTP/1.1\r\nContent-Type: application/json\r\nAuthorization: Bearer 96e647567627164796f6e63704370727565646c697e236f6d6:5427e43707866415555426a68723848763574533d476a466:QryC8bI6hfidGVcFcwnago3t77BSzW8ItUl9GWhsx9Y\r\nConnection: close\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept: */*\r\nUser-Agent: Ruby\r\nHost: api.paytrace.com\r\nContent-Length: 335\r\n\r\n"
      <- "{\"amount\":\"1.00\",\"credit_card\":{\"number\":\"4012000098765439\",\"expiration_month\":9,\"expiration_year\":2022},\"billing_address\":{\"name\":\"Longbob Longsen\",\"street_address\":\"456 My Street\",\"city\":\"Ottawa\",\"state\":\"ON\",\"zip\":\"K1C2N6\"},\"password\":\"ErNsphFQUEbjx2Hx6uT3MgJf\",\"username\":\"integrations@spreedly.com\",\"integrator_id\":\"9575315uXt4u\"}"
      -> "HTTP/1.1 200 OK\r\n"
      -> "Date: Thu, 03 Jun 2021 22:03:24 GMT\r\n"
      -> "Content-Type: application/json; charset=utf-8\r\n"
      -> "Transfer-Encoding: chunked\r\n"
      -> "Connection: close\r\n"
      -> "Status: 200 OK\r\n"
      -> "Cache-Control: max-age=0, private, must-revalidate\r\n"
      -> "Referrer-Policy: strict-origin-when-cross-origin\r\n"
      -> "X-Permitted-Cross-Domain-Policies: none\r\n"
      -> "X-XSS-Protection: 1; mode=block\r\n"
      -> "X-Request-Id: f008583e-3755-4eca-b8a0-83d8d82cefca\r\n"
      -> "X-Download-Options: noopen\r\n"
      -> "ETag: W/\"4edcbabd892d2f033a4cbc7932f26fae\"\r\n"
      -> "X-Frame-Options: SAMEORIGIN\r\n"
      -> "X-Runtime: 1.984489\r\n"
      -> "X-Content-Type-Options: nosniff\r\n"
      -> "X-Frame-Options: SAMEORIGIN\r\n"
      -> "X-XSS-Protection: 1; mode=block\r\n"
      -> "X-Content-Type-Options: nosniff\r\n"
      -> "Content-Security-Policy: frame-ancestors 'self';\r\n"
      -> "Strict-Transport-Security: max-age=31536000; includeSubDomains\r\n"
      -> "\r\n"
      -> "142\r\n"
      reading 322 bytes...
      -> "{\"success\":true,\"response_code\":101,\"status_message\":\"Your transaction was successfully approved.\",\"transaction_id\":395970044,\"approval_code\":\"TAS679\",\"approval_message\":\"  NO  MATCH - Approved and completed\",\"avs_response\":\"No Match\",\"csc_response\":\"\",\"external_transaction_id\":\"\",\"masked_card_number\":\"xxxxxxxxxxxx5439\"}"
      read 322 bytes
      reading 2 bytes...
      -> "\r\n"
      read 2 bytes
      -> "0\r\n"
      -> "\r\n"
      Conn close
    PRE_SCRUBBED
  end

  def post_scrubbed
    <<-POST_SCRUBBED
      opening connection to api.paytrace.com:443...
      opened
      starting SSL for api.paytrace.com:443...
      SSL established
      <- "POST /v1/transactions/sale/keyed HTTP/1.1\r\nContent-Type: application/json\r\nAuthorization: Bearer [FILTERED]\r\nConnection: close\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept: */*\r\nUser-Agent: Ruby\r\nHost: api.paytrace.com\r\nContent-Length: 335\r\n\r\n"
      <- "{\"amount\":\"1.00\",\"credit_card\":{\"number\":\"[FILTERED]\",\"expiration_month\":9,\"expiration_year\":2022},\"billing_address\":{\"name\":\"Longbob Longsen\",\"street_address\":\"456 My Street\",\"city\":\"Ottawa\",\"state\":\"ON\",\"zip\":\"K1C2N6\"},\"password\":\"[FILTERED]\",\"username\":\"[FILTERED]\"}"
      -> "HTTP/1.1 200 OK\r\n"
      -> "Date: Thu, 03 Jun 2021 22:03:24 GMT\r\n"
      -> "Content-Type: application/json; charset=utf-8\r\n"
      -> "Transfer-Encoding: chunked\r\n"
      -> "Connection: close\r\n"
      -> "Status: 200 OK\r\n"
      -> "Cache-Control: max-age=0, private, must-revalidate\r\n"
      -> "Referrer-Policy: strict-origin-when-cross-origin\r\n"
      -> "X-Permitted-Cross-Domain-Policies: none\r\n"
      -> "X-XSS-Protection: 1; mode=block\r\n"
      -> "X-Request-Id: f008583e-3755-4eca-b8a0-83d8d82cefca\r\n"
      -> "X-Download-Options: noopen\r\n"
      -> "ETag: W/\"4edcbabd892d2f033a4cbc7932f26fae\"\r\n"
      -> "X-Frame-Options: SAMEORIGIN\r\n"
      -> "X-Runtime: 1.984489\r\n"
      -> "X-Content-Type-Options: nosniff\r\n"
      -> "X-Frame-Options: SAMEORIGIN\r\n"
      -> "X-XSS-Protection: 1; mode=block\r\n"
      -> "X-Content-Type-Options: nosniff\r\n"
      -> "Content-Security-Policy: frame-ancestors 'self';\r\n"
      -> "Strict-Transport-Security: max-age=31536000; includeSubDomains\r\n"
      -> "\r\n"
      -> "142\r\n"
      reading 322 bytes...
      -> "{\"success\":true,\"response_code\":101,\"status_message\":\"Your transaction was successfully approved.\",\"transaction_id\":395970044,\"approval_code\":\"TAS679\",\"approval_message\":\"  NO  MATCH - Approved and completed\",\"avs_response\":\"No Match\",\"csc_response\":\"\",\"external_transaction_id\":\"\",\"masked_card_number\":\"xxxxxxxxxxxx5439\"}"
      read 322 bytes
      reading 2 bytes...
      -> "\r\n"
      read 2 bytes
      -> "0\r\n"
      -> "\r\n"
      Conn close
    POST_SCRUBBED
  end

  def successful_purchase_response
    '{"success":true,"response_code":101,"status_message":"Your transaction was successfully approved.","transaction_id":392483066,"approval_code":"TAS610","approval_message":"  NO  MATCH - Approved and completed","avs_response":"No Match","csc_response":"","external_transaction_id":"","masked_card_number":"xxxxxxxxxxxx5439"}'
  end

  def successful_level_3_response
    '{"success":true,"response_code":170,"status_message":"Visa/MasterCard enhanced data was successfully added to Transaction ID 392483066. 1 line item records were created."}'
  end

  def successful_level_3_visa
    '{"success":true,"response_code":170,"status_message":"Visa/MasterCard enhanced data was successfully added to Transaction ID 123456789. 2 line item records were created."}'
  end

  def failed_purchase_response
    '{"success":false,"response_code":102,"status_message":"Your transaction was not approved.","transaction_id":392501201,"approval_code":"","approval_message":"    DECLINE - Do not honor","avs_response":"No Match","csc_response":"","external_transaction_id":"","masked_card_number":"xxxxxxxxxxxx5439"}'
  end

  def successful_authorize_response
    '{"success":true,"response_code":101,"status_message":"Your transaction was successfully approved.","transaction_id":392224547,"approval_code":"TAS161","approval_message":"  NO  MATCH - Approved and completed","avs_response":"No Match","csc_response":"","external_transaction_id":"","masked_card_number":"xxxxxxxxxxxx2224"}'
  end

  def failed_authorize_response
    '{"success":false,"response_code":102,"status_message":"Your transaction was not approved.","transaction_id":395971008,"approval_code":"","approval_message":"  EXPIRED CARD - Expired card","avs_response":"No Match","csc_response":"","external_transaction_id":"","masked_card_number":"xxxxxxxxxxxx5439"}'
  end

  def successful_capture_response
    '{"success":true,"response_code":112,"status_message":"Your transaction was successfully captured.","transaction_id":392442990,"external_transaction_id":""}'
  end

  def failed_capture_response
    '{"success":false,"response_code":1,"status_message":"One or more errors has occurred.","errors":{"58":["Please provide a valid Transaction ID."]},"external_transaction_id":""}'
  end

  def successful_refund_response
    '{"success":true,"response_code":106,"status_message":"Your transaction successfully refunded.","transaction_id":105968559,"external_transaction_id":""}'
  end

  def failed_refund_response
    '{"success":false,"response_code":1,"status_message":"One or more errors has occurred.","errors":{"981":["Log in failed for insufficient permissions."]},"external_transaction_id":""}'
  end

  def successful_void_response
    '{"success":true,"response_code":109,"status_message":"Your transaction was successfully voided.","transaction_id":395971574}'
  end

  def failed_void_response
    '{"success":false,"response_code":1,"status_message":"One or more errors has occurred.","errors":{"58":["Please provide a valid Transaction ID."]}}'
  end

  def successful_create_customer_response
    '{"success":true,"response_code":160,"status_message":"The customer profile for customerTest150/Steve Smith was successfully created","customer_id":"customerTest150","masked_card_number":"xxxxxxxxxxxx1111"}'
  end

  def failed_customer_creation_response
    '{"success":false,"response_code":1,"status_message":"One or more errors has occurred.","errors":{"171":["Please provide a unique customer ID."]},"masked_card_number":"xxxxxxxxxxxx5439"}'
  end
end
