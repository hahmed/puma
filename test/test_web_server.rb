# frozen_string_literal: true
# Copyright (c) 2011 Evan Phoenix
# Copyright (c) 2005 Zed A. Shaw

require_relative "helper"

require "puma/server"

class TestHandler
  attr_reader :ran_test

  def call(env)
    @ran_test = true

    [200, {"Content-Type" => "text/plain"}, ["hello!"]]
  end
end

class WebServerTest < Minitest::Test
  parallelize_me!

  VALID_REQUEST = "GET / HTTP/1.1\r\nHost: www.zedshaw.com\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"

  # def setup
  #   @tester = TestHandler.new
  #   @server = Puma::Server.new @tester, Puma::Events.strings
  #   @server.add_tcp_listener "127.0.0.1", 0
  #
  #   @server.run
  # end
  #
  # def teardown
  #   @server.stop(true)
  # end

  def start_server
    tester = TestHandler.new
    server = Puma::Server.new tester, Puma::Events.strings
    server.add_tcp_listener "127.0.0.1", 0

    server.run
    [server, tester]
  end

  def test_simple_server
    server, tester = start_server
    hit(["http://127.0.0.1:#{server.connected_port}/test"])
    assert tester.ran_test, "Handler didn't really run"

    server.stop(true)
  end

  def test_trickle_attack
    server, tester = start_server

    socket = do_test(server, VALID_REQUEST, 3)
    assert_match "hello", socket.read

    socket.close
    server.stop(true)
  end

  def test_close_client
    server, tester = start_server

    assert_raises IOError do
      do_test_raise(server, VALID_REQUEST, 10, 20)
    end

    server.stop(true)
  end

  def test_bad_client
    server, tester = start_server

    socket = do_test(server, "GET /test HTTP/BAD", 3)
    assert_match "Bad Request", socket.read

    socket.close
    server.stop(true)
  end

  def test_header_is_too_long
    server, tester = start_server

    long = "GET /test HTTP/1.1\r\n" + ("X-Big: stuff\r\n" * 15000) + "\r\n"
    assert_raises Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNABORTED, Errno::EINVAL, IOError do
      do_test_raise(server, long, long.length/2, 10)
    end

    server.stop(true)
  end

  # TODO: Why does this test take exactly 20 seconds?
  def test_file_streamed_request
    server, tester = start_server

    body = "a" * (Puma::Const::MAX_BODY * 2)
    long = "GET /test HTTP/1.1\r\nContent-length: #{body.length}\r\nConnection: close\r\n\r\n" + body
    socket = do_test(server, long, (Puma::Const::CHUNK_SIZE * 2) - 400)

    assert_match "hello", socket.read

    socket.close
    server.stop(true)
  end

  private

  def do_test(server, string, chunk)
    # Do not use instance variables here, because it needs to be thread safe
    socket = TCPSocket.new("127.0.0.1", server.connected_port);
    request = StringIO.new(string)
    while data = request.read(chunk)
      socket.write(data)
      socket.flush
    end
    socket
  end

  def do_test_raise(server, string, chunk, close_after = nil)
    # Do not use instance variables here, because it needs to be thread safe
    socket = TCPSocket.new("127.0.0.1", server.connected_port);
    request = StringIO.new(string)
    chunks_out = 0

    while data = request.read(chunk)
      chunks_out += socket.write(data)
      socket.flush
      socket.close if close_after && chunks_out > close_after
    end

    socket.write(" ") # Some platforms only raise the exception on attempted write
    socket.flush
    socket
  ensure
    socket.close unless socket.closed?
  end
end
