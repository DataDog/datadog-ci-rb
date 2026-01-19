RSpec.describe "gem release process" do
  context "datadog-ci.gemspec" do
    context "maximum Ruby version" do
      it "is the same as for gem datadog" do
        datadog_version = ::Datadog::VERSION::MAXIMUM_RUBY_VERSION
        datadog_ci_version = ::Datadog::CI::VERSION::MAXIMUM_RUBY_VERSION

        expect(datadog_ci_version).to eq(datadog_version)
      end
    end

    context "files" do
      subject(:files) { Gem::Specification.load("datadog-ci.gemspec").files }

      # It's easy to forget to ship new files, especially when a new paradigm is
      # introduced (e.g. introducing native files requires the inclusion `ext/`)
      it "includes all important files" do
        single_files_excluded = /
          ^
          (
           |\.customcops.yml
           |\.env
           |\.gitignore
           |\.rspec
           |\.rspec-local.example
           |\.rubocop.yml
           |\.standard.yml
           |\.standard_todo.yml
           |\.simplecov
           |\.yardopts
           |Appraisals
           |AGENTS.md
           |CLAUDE.md
           |CODE_OF_CONDUCT.md
           |CONTRIBUTING.md
           |CODEOWNERS
           |Gemfile
           |Gemfile-.*
           |Rakefile
           |Steepfile
           |supported-configurations.json
           |datadog-ci\.gemspec
           |docker-compose\.yml
          )
          $
        /x

        directories_excluded = %r{
          ^(
            spec
            |sig
            |docs
            |\.circleci
            |\.github
            |\.vscode
            | bin
            |gemfiles
            |integration
            |rubocop
            |tasks
            |yard
            |vendor/rbs
            |suppressions
            |.cursor
            |.claude
          )/
        }x

        expect(files)
          .to match_array(
            `git ls-files -z`
              .force_encoding(Encoding::UTF_8)
              .split("\x0")
              .reject { |f| f.match(directories_excluded) }
              .reject { |f| f.match(single_files_excluded) }
          )
      end
    end
  end
end
