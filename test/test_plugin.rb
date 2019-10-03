require_relative "helper"
require_relative "helpers/integration"

class TestPlugin < TestIntegration
  include WaitForServerLogs

  def test_plugin
    skip "Skipped on Windows Ruby < 2.5.0, Ruby bug" if windows? && RUBY_VERSION < '2.5.0'
    @tcp_bind = UniquePort.call

    Dir.mkdir("tmp") unless Dir.exist?("tmp")

    cli_server "-C test/config/plugin1.rb test/rackup/hello.ru"
    File.open('tmp/restart.txt', mode: 'wb') { |f| f.puts "Restart #{Time.now}" }

    wait_until_server_logs("Restarting...")
    wait_until_server_logs("Ctrl-C")
  end
end
