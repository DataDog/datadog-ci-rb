# Required from the command line, which Ruby loads before the libraries that RUBYOPT names,
# so this exit handler runs after theirs.
at_exit { load File.expand_path("leaf.rb", __dir__) }
