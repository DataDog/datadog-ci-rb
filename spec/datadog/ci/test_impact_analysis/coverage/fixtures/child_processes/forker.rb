pid = fork { load ARGV.fetch(0) }
Process.wait(pid)
