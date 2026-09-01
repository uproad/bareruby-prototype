# frozen_string_literal: true

require "English"
require "yaml"

require "bareruby_prot/tools"

module BareRubyProt
  # What an ESP-IDF build reaches for, and where a build is told to find it afterwards.
  #
  # The lock beside this file is the whole of what is known about these; nothing is named
  # twice. The directories a build is given come out of the same entries that were used to
  # fetch them, so a version bump is one file and the build follows.
  #
  # **Only one of the two is a repository, and that is why this binding needed writing
  # rather than copying.** The SDK is a checkout: it is cloned and verified like any
  # other. The compilers are not — ESP-IDF brings its own down with `idf_tools.py`, from a
  # table inside that checkout, into a store it is told about through the environment.
  # There is no archive to hash, so the command that owns the format is the one that
  # fetches it, and the commit the checkout is pinned at is what pins what it fetches. What
  # the ecosystem has never heard of, it is not asked to do.
  module EspIdfTools
    LOCK = YAML.safe_load_file(File.join(__dir__, "data/sources.lock.yml")).freeze

    # **A desk that already has one of these says so, and then it is not fetched.** The
    # two variables are ESP-IDF's own, honoured by every command it ships, and which of
    # them covers which thing is known here and nowhere else — the same way it is for
    # every other binding.
    # One checkout and one set of tools serve every board this binding reaches, so which
    # machines a run is for settles nothing here.
    def self.install(into:, targets: [])
      checkout unless own_sdk?
      compilers
    end

    def self.checkout
      Tools.repository(directory: LOCK["sdk"]["directory"], github: LOCK["sdk"]["github"],
                       tag: LOCK["sdk"]["tag"], commit: LOCK["sdk"]["commit"],
                       submodules: LOCK["sdk"]["submodules"])
    end

    # Two gigabytes of somebody else's compiler and a Python environment beside it, so
    # what says it is already here is asked before anything reaches the network — the same
    # question `Tools.already?` asks of an archive, asked of directories this side did not
    # unpack. `idf_tools.py` is quiet about a tool it already has, but it is quiet after
    # reading its table and reaching for a version file, and a second build should not pay
    # for the first one's convenience.
    def self.compilers
      return if own_tools? || (wanted.all? { |name| held?(name) } && Dir.exist?(python_environment))

      Tools.announce("the ESP-IDF #{LOCK['sdk']['tag']} toolchain", "#{idf_tools} install")
      fetched(["install", *wanted])
      fetched(["install-python-env"])
    end

    # **Quiet unless it fails**, which is what every other tool here is. `idf_tools.py`
    # narrates a percentage per downloaded kilobyte, and a fetch that said all of it would
    # be the loudest thing in a build that says two lines. What it said is kept for the
    # failure it explains, the same way a second stage's output is.
    def self.fetched(arguments)
      output = IO.popen(environment_for_install, ["python3", idf_tools, *arguments],
                        err: %i[child out], &:read)
      return if $CHILD_STATUS.success?

      warn output
      raise "idf_tools.py #{arguments.first} failed."
    end

    def self.wanted = LOCK["tools"]["commands"].keys + LOCK["tools"]["named"].keys

    def self.idf_tools = File.join(sdk, "tools", "idf_tools.py")

    def self.sdk = ENV["IDF_PATH"] || Tools.at(LOCK["sdk"]["directory"])

    def self.own_sdk? = !ENV["IDF_PATH"].nil?

    def self.store = ENV["IDF_TOOLS_PATH"] || Tools.at(LOCK["tools"]["directory"])

    def self.own_tools? = !ENV["IDF_TOOLS_PATH"].nil?

    # **Which version of a tool is installed is not written down here.** ESP-IDF's own
    # table settled it, at the commit the lock pins, so the one directory under a tool's
    # name is the pinned one and asking the store is asking that table. A second answer
    # here would be a second thing to keep in step.
    def self.held?(name) = !versions(name).empty?

    def self.versions(name) = Dir.glob(File.join(store, "tools", name, "*")).sort

    def self.python_environment = Dir.glob(File.join(store, "python_env", "*")).min.to_s

    # **A command this side runs itself is named by its path rather than by its word.** A
    # second stage is a line handed to a shell, and a shell looks a bare word up on the
    # PATH it was given — which is why the manifest can record `cmake …` and stay readable
    # on any desk. Nothing runs a shell for the two commands run from Ruby here: an argv is
    # executed directly, and the resolving is ruby's, against the PATH of this process
    # rather than the one being passed in. A store this side downloaded into is on neither.
    def self.command(name) = File.join(python_environment, "bin", name)

    # Where each command ended up, in the order a build should meet them: the Python
    # environment first, because ESP-IDF's own scripts are what a build runs most, then
    # the compiler and the two build tools, then the scripts that live in the checkout.
    def self.command_directories
      [File.join(python_environment, "bin")] +
        LOCK["tools"]["commands"].map { |name, held| File.join(versions(name).last.to_s, held) } +
        [File.join(sdk, "tools")]
    end

    # The three ESP-IDF will not run without, and the PATH that carries the rest. A desk
    # that named its own store or its own checkout is answered with what it named, because
    # both were read that way when nothing was fetched.
    def self.environment
      {
        "IDF_PATH" => sdk,
        "IDF_TOOLS_PATH" => store,
        "IDF_PYTHON_ENV_PATH" => python_environment,
        # **The SDK's own submodule check is turned off, because it is not a check.** Told
        # one is missing it fetches it — a whole history, one submodule at a time — and
        # leaves 8.2 GB where the same twenty-three commits weigh 1.9 GB. Every one of them
        # is named in the lock and fetched with the checkout, at one commit each, so what
        # this switches off is a second answer to a question already settled.
        "IDF_SKIP_CHECK_SUBMODULES" => "1",
        "PATH" => (command_directories + [ENV.fetch("PATH", "")]).join(File::PATH_SEPARATOR)
      }.merge(named)
    end

    # The directories a build reads rather than runs, each under the variable the SDK looks
    # for it by. Which variable that is, is ESP-IDF's answer, so it is written in the lock
    # beside the tool it names.
    def self.named
      LOCK["tools"]["named"].to_h { |tool, variable| [variable, versions(tool).last.to_s] }
    end

    # Fetching is the one time the Python environment is what is being made rather than
    # what is being used, so it is left out and the desk's own python3 runs the fetch.
    def self.environment_for_install = { "IDF_PATH" => sdk, "IDF_TOOLS_PATH" => store }
  end
end
