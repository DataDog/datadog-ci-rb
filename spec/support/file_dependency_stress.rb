# frozen_string_literal: true

require "fileutils"

# Shared by coverage integration tests and isolated native memory checks.
module FileDependencyStress
  CONTENTS = "file dependency fixture\x00\n"

  def self.build(directory)
    names = [
      " leading and trailing spaces ", "-leading-dash", "~literal-tilde",
      "quotes-'\"", "glob-[a]*?", "back\\slash", "line\nbreak", "tab\tname",
      "shell-|&;$`!", "parentheses-(){}", "dots...", "nfc-caf\u00e9",
      "nfd-cafe\u0301", "\u65e5\u672c\u8a9e", "emoji-\u{1f9ea}", "rtl-\u202ename",
      "x" * 251 + ".dat", "\u754c" * 70 + ".dat"
    ]
    random = Random.new(0xDDC1)
    alphabet = "abcXYZ0129 ._-~[](){}'\"\\|!;$`\t".chars
    32.times do |index|
      suffix = Array.new(random.rand(8..180)) { alphabet[random.rand(alphabet.length)] }.join
      names << "generated-#{index}-#{suffix}"
    end

    paths = names.map { |name| File.join(directory, name) }
    deep = directory
    64.times do |level|
      deep = File.join(deep, format("d%02d", level))
      Dir.mkdir(deep)
    end
    paths << File.join(deep, "deep.dat")
    paths << File.join(deep, "y" * 251 + ".dat")
    paths << File.join(deep, "unicode-\u{1f9ea}.dat")
    paths.each { |path| File.binwrite(path, CONTENTS) }

    target = paths.first
    8.times do |index|
      link = File.join(directory, "symlink-#{index}")
      File.symlink(File.basename(target), link)
      paths << link
      target = link
    end
    hardlink = File.join(directory, "hardlink.dat")
    File.link(paths.first, hardlink)
    paths << hardlink
    directory_link = File.join(directory, "directory-link")
    File.symlink(deep.delete_prefix(directory + "/"), directory_link)
    paths << File.join(directory_link, "deep.dat")
    paths << directory + "//./" + names.first
    paths << File.join(directory, "d00", "..", names.first)
    # Resolve the directory symlink before ..; the target is in its real parent.
    parent_file = File.join(File.dirname(deep), "parent.dat")
    File.binwrite(parent_file, CONTENTS)
    paths << File.join(directory_link, "..", "parent.dat")
    paths
  end

  def self.read(path, operation)
    case operation
    when :open, :new
      file = File.public_send(operation, path, "rb")
      begin
        file.read
      ensure
        file.close
      end
    else
      File.public_send(operation, path)
    end
  end
end
