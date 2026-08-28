# frozen_string_literal: true

require "English"
require "yaml"

require "bareruby_prot/tools"

require_relative "binding"

module BareRubyProt
  # What an Arduino build reaches for, and where a build is told to find it afterwards.
  #
  # The lock beside this file is the whole of what is known about these; nothing is named
  # twice. The directories a build is given come out of the same entries that were used to
  # fetch them, so a version bump is one file and the build follows.
  #
  # **Only one of the two is an archive, and that is why this binding needed writing rather
  # than copying.** arduino-cli is a release: it is fetched and verified like an SDK. A core
  # is the compiler — avr-gcc and avrdude for one board, an Xtensa toolchain and esptool for
  # another — and it arrives as an index and a set of packages that arduino-cli resolves for
  # itself. There is no single file to hash, so the command that owns the format is the one
  # that fetches it, pinned by version on its own command line. What the ecosystem has never
  # heard of, it is not asked to do.
  #
  # **Which core is fetched follows from which machines the run is for.** One board's core
  # is 259 MB and another's is 5.6 GB, and a desk with only a Mega attached should pay for
  # neither of the other kind — so the packages are read off the FQBNs the machines this run
  # names, and a core nobody is building for is never asked about.
  module ArduinoTools
    LOCK = YAML.safe_load_file(File.join(__dir__, "data/sources.lock.yml")).freeze

    # **A desk that already has one of these says so, and then it is not fetched.** The
    # two answers are the ones the build already honours — an `arduino-cli` on PATH, and a
    # data directory named through the environment — read here so that honouring them does
    # not first cost a download. Which variable covers which thing is known here and
    # nowhere else, the same way it is for every other binding.
    def self.install(into:, targets: [])
      Tools.archive(directory: LOCK["cli"]["directory"], from: LOCK["cli"]["from"], **archive) unless own_cli?
      packages(targets).each { |package| core(package) }
    end

    def self.archive
      found = LOCK["cli"]["archives"][Tools.platform]
      raise "no arduino-cli is locked for #{Tools.platform}." unless found

      { file: found["file"], sha256: found["sha256"] }
    end

    # **A core is named by the board that needs it.** The first two words of an FQBN are the
    # packager and the architecture, which is exactly what `core install` takes — so which
    # core a machine wants is already written in what the build calls that board, and this
    # side keeps no second list of which board belongs to which core.
    def self.packages(targets)
      targets.map { |target| package(ArduinoBinding.machine(target.machine).fqbn) }.uniq
    end

    def self.package(fqbn) = fqbn.split(":").first(2).join(":")

    def self.locked(fqbn) = LOCK["cores"].fetch(package(fqbn))

    # Gigabytes of somebody else's compiler, so what says it is already here is asked before
    # anything reaches the network — the same question `Tools.already?` asks of an archive,
    # asked of a directory this side did not unpack. arduino-cli is quiet about a core it
    # already has, but it is quiet after resolving an index over the network, and a second
    # build should not pay for the first one's convenience.
    def self.core(package)
      held = LOCK["cores"].fetch(package)
      return if own_data? || Dir.exist?(File.join(data, held["holds"]))

      Tools.announce(named(package, held), "#{command} core install")
      fetched(package, held)
    end

    def self.named(package, held) = "#{package}@#{held['version']}"

    # **Quiet unless it fails**, which is what every other tool here is. arduino-cli
    # narrates each index and each package as it goes, and a fetch that said all of it
    # would be the loudest thing in a build that says two lines. What it said is kept for
    # the failure it explains, the same way a second stage's output is.
    #
    # A core the command has never heard of is one published by whoever wrote it rather than
    # by Arduino, and the lock carries the index that lists it.
    def self.fetched(package, held)
      wanted = named(package, held)
      command_line = [command, "core", "install", wanted]
      command_line += ["--additional-urls", held["index"]] if held["index"]
      output = IO.popen(environment, command_line, err: %i[child out], &:read)
      return if $CHILD_STATUS.success?

      warn output
      raise "installing #{wanted} failed."
    end

    # Where the command ends up, which a build has to be able to find it at. A desk that
    # brought its own has it on PATH already, and then this names a directory that was
    # never made — which is exactly right, because nothing will look in it.
    def self.command_directory = Tools.at(LOCK["cli"]["directory"])

    def self.command = own_cli? ? "arduino-cli" : File.join(command_directory, "arduino-cli")

    # **The program that writes a board, for a core whose boards `arduino-cli upload` is
    # not what puts an image on them.** It came down with the core, so where it is is the
    # data directory and the path the lock names; a core that has no such entry is one whose
    # boards the command writes itself, and this answers nothing for it.
    def self.writer(fqbn)
      held = locked(fqbn)["writer"]
      held && File.join(data, held)
    end

    # Env-name to the directory in the store it stands for. The build reads this too, so
    # the directories a core was installed into are the ones it is compiled from.
    def self.paths = LOCK["directories"]

    def self.data = ENV["ARDUINO_DIRECTORIES_DATA"] || Tools.at(paths["ARDUINO_DIRECTORIES_DATA"])

    def self.own_data? = !ENV["ARDUINO_DIRECTORIES_DATA"].nil?

    def self.own_cli? = ENV["PATH"].to_s.split(File::PATH_SEPARATOR)
                                   .any? { |place| File.executable?(File.join(place, "arduino-cli")) }

    def self.environment
      paths.to_h { |name, held| [name, ENV[name] || Tools.at(held)] }
    end
  end
end
