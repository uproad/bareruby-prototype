# frozen_string_literal: true

require "English"
require "yaml"

require "bareruby_prot/tools"

module BareRubyProt
  # What an Arduino build reaches for, and where a build is told to find it afterwards.
  #
  # The lock beside this file is the whole of what is known about these; nothing is named
  # twice. The directories a build is given come out of the same entries that were used to
  # fetch them, so a version bump is one file and the build follows.
  #
  # **Only one of the two is an archive, and that is why this binding needed writing rather
  # than copying.** arduino-cli is a release: it is fetched and verified like an SDK. The
  # core is the compiler — avr-gcc, avr-libc and avrdude — and it arrives as an index and a
  # set of packages that arduino-cli resolves for itself. There is no single file to hash,
  # so the command that owns the format is the one that fetches it, pinned by version on
  # its own command line. What the ecosystem has never heard of, it is not asked to do.
  module ArduinoTools
    LOCK = YAML.safe_load_file(File.join(__dir__, "data/sources.lock.yml")).freeze

    CORE = "#{LOCK['core']['package']}@#{LOCK['core']['version']}"

    # **A desk that already has one of these says so, and then it is not fetched.** The
    # two answers are the ones the build already honours — an `arduino-cli` on PATH, and a
    # data directory named through the environment — read here so that honouring them does
    # not first cost a download. Which variable covers which thing is known here and
    # nowhere else, the same way it is for every other binding.
    def self.install(into:)
      Tools.archive(directory: LOCK["cli"]["directory"], from: LOCK["cli"]["from"], **archive) unless own_cli?
      core
    end

    def self.archive
      found = LOCK["cli"]["archives"][Tools.platform]
      raise "no arduino-cli is locked for #{Tools.platform}." unless found

      { file: found["file"], sha256: found["sha256"] }
    end

    # 381 MB of somebody else's compiler, so what says it is already here is asked before
    # anything reaches the network — the same question `Tools.already?` asks of an archive,
    # asked of a directory this side did not unpack. arduino-cli is quiet about a core it
    # already has, but it is quiet after resolving an index over the network, and a second
    # build should not pay for the first one's convenience.
    def self.core
      return if own_data? || Dir.exist?(File.join(data, LOCK["core"]["holds"]))

      Tools.announce(CORE, "#{command} core install")
      fetched
    end

    # **Quiet unless it fails**, which is what every other tool here is. arduino-cli
    # narrates each index and each package as it goes, and a fetch that said all of it
    # would be the loudest thing in a build that says two lines. What it said is kept for
    # the failure it explains, the same way a second stage's output is.
    def self.fetched
      output = IO.popen(environment, [command, "core", "install", CORE], err: %i[child out], &:read)
      return if $CHILD_STATUS.success?

      warn output
      raise "installing #{CORE} failed."
    end

    # Where the command ends up, which a build has to be able to find it at. A desk that
    # brought its own has it on PATH already, and then this names a directory that was
    # never made — which is exactly right, because nothing will look in it.
    def self.command_directory = Tools.at(LOCK["cli"]["directory"])

    def self.command = own_cli? ? "arduino-cli" : File.join(command_directory, "arduino-cli")

    # Env-name to the directory in the store it stands for. The build reads this too, so
    # the three directories the core was installed into are the three it is compiled from.
    def self.paths = LOCK["core"]["directories"]

    def self.data = ENV["ARDUINO_DIRECTORIES_DATA"] || Tools.at(paths["ARDUINO_DIRECTORIES_DATA"])

    def self.own_data? = !ENV["ARDUINO_DIRECTORIES_DATA"].nil?

    def self.own_cli? = ENV["PATH"].to_s.split(File::PATH_SEPARATOR)
                                   .any? { |place| File.executable?(File.join(place, "arduino-cli")) }

    def self.environment
      paths.to_h { |name, held| [name, ENV[name] || Tools.at(held)] }
    end
  end
end
