# frozen_string_literal: true

require "digest"
require "fileutils"
require "open-uri"
require "tmpdir"

require_relative "toolchain"

module BareRubyProt
  # What a build reaches for that no gem carries: SDKs, cross compilers, the programs that
  # write a board. Gigabytes of other people's releases.
  #
  # **This side decides where they go and knows how to fetch the two shapes they come in.
  # It does not know what any of them are.** Which SDK a Pico needs, which version, and
  # what a build has to be told about it afterwards are the binding's answers, the same way
  # a peripheral names its own C functions. A binding that reaches for something in a shape
  # this file has never heard of does not use this file — `arduino-cli` installs its own
  # cores, and there is nothing here for it to fit into.
  #
  # **The store belongs to the desk rather than to a project.** One pico-sdk serves every
  # project on a machine, and a checkout that keeps its own copy is a checkout that was
  # written when there was only one of them. A desk that wants it elsewhere says so.
  module Tools
    STORE = File.expand_path(ENV["BARERUBY_TOOLS"] || "~/.bareruby/tools")

    # Asked of the bindings a run is about to use, before the run uses them. A binding with
    # nothing to install answers by not having any — the same shape as a binding with no
    # peripherals to implement.
    #
    # **The machines are handed over with the question**, because for some bindings what to
    # fetch is not settled by the binding alone: one Arduino core is 259 MB and another is
    # 5.6 GB, and which of them a desk needs is which boards it has. A binding whose answer
    # does not depend on that takes the list and ignores it.
    def self.install(targets)
      targets.group_by(&:binding).each do |binding, wanted|
        binding.tools.install(into: STORE, targets: wanted) if binding.respond_to?(:tools)
      end
    end

    def self.at(directory) = File.join(STORE, directory)

    # linux-x64 and its three siblings, spelled the way a lock file spells them.
    def self.platform
      system = RUBY_PLATFORM.include?("darwin") ? "darwin" : "linux"
      "#{system}-#{RUBY_PLATFORM.start_with?('aarch64', 'arm64') ? 'arm64' : 'x64'}"
    end

    # Idempotent, and silent when there is nothing to do. **The question "is it already
    # here" is answered locally**, because this runs underneath every build: a check that
    # reached the network would make the second build pay for the first one's convenience.
    def self.already?(directory)
      Dir.exist?(at(directory)) && !Dir.empty?(at(directory))
    end

    def self.announce(what, from)
      warn "bareruby: fetching #{what} into #{STORE}"
      warn "bareruby:   #{from}"
    end

    # An archive, verified before it is opened. The hash is not optional: what is being
    # unpacked is a compiler, and it came off the network.
    def self.archive(directory:, from:, file:, sha256:)
      return if already?(directory)

      announce(File.basename(directory), "#{from}/#{file}")
      # Unpacked inside the store rather than in the system's temporary directory, so that
      # putting it in place is a rename. A gigabyte that crosses a filesystem to get where
      # it is going is a gigabyte copied twice.
      FileUtils.mkdir_p(STORE)
      Dir.mktmpdir(nil, STORE) do |scratch|
        downloaded = File.join(scratch, file)
        download("#{from}/#{file}", downloaded)
        verify(downloaded, sha256)
        fetching(["tar", "-xf", downloaded, "-C", scratch])
        place(Dir.children(scratch).reject { |name| name == file }, scratch, directory)
      end
    end

    # A repository at one commit, with the submodules the lock names and no others. The tag
    # says which release it is; the commit says the release has not been moved underneath
    # it, which is the failure a tag alone cannot see.
    def self.repository(directory:, github:, tag:, commit:, submodules: {})
      return if already?(directory)

      announce(File.basename(directory), "https://github.com/#{github} @ #{tag}")
      into = at(directory)
      FileUtils.mkdir_p(File.dirname(into))
      clone(github, tag, into)
      confirm(into, commit, "#{github} #{tag}")
      submodules.each { |path, at| submodule(into, path, at) }
    end

    def self.clone(github, tag, into)
      fetching(["git", "clone", "--branch", tag, "--depth", "1",
                "https://github.com/#{github}.git", into])
    end

    def self.submodule(into, path, commit)
      fetching(["git", "-C", into, "submodule", "update", "--init", "--depth", "1", path])
      confirm(File.join(into, path), commit, path)
    end

    # git and tar say where a download has got to, which is worth hearing when it is a
    # gigabyte — but they say it to the terminal, and a run drawing a table there needs
    # them to say it through this side instead. What they said is passed on either way;
    # only a failure stops the run.
    def self.fetching(command)
      raise "#{command.first} failed while fetching." unless Toolchain.aloud(command)
    end

    def self.confirm(repository, commit, what)
      found = `git -C #{repository} rev-parse HEAD`.strip
      return if found == commit

      raise "#{what} is at #{found}, and the lock says #{commit}."
    end

    def self.download(url, to)
      URI.parse(url).open { |remote| IO.copy_stream(remote, to) }
    end

    def self.verify(file, sha256)
      found = Digest::SHA256.file(file).hexdigest
      return if found == sha256

      raise "#{File.basename(file)} hashes to #{found}, and the lock says #{sha256}."
    end

    # An archive holds one directory and it is named whatever the release names it. What
    # the lock calls it is what it is filed under, so the two are reconciled here rather
    # than by everything that later has to find it.
    #
    # **Some releases hold no directory at all** — arduino-cli is a command and a licence,
    # loose at the top of the tarball, and a release that unpacks into the directory it was
    # unpacked in is a shape as ordinary as the other. Which one arrived is a question the
    # archive answers by what came out of it, so it is asked here rather than written into
    # every lock that ever names one.
    def self.place(unpacked, scratch, directory)
      into = at(directory)
      FileUtils.mkdir_p(File.dirname(into))
      FileUtils.rm_rf(into)
      return FileUtils.mv(File.join(scratch, unpacked.first), into) if held?(unpacked, scratch)

      FileUtils.mkdir_p(into)
      unpacked.each { |name| FileUtils.mv(File.join(scratch, name), into) }
    end

    def self.held?(unpacked, scratch)
      unpacked.one? && File.directory?(File.join(scratch, unpacked.first))
    end
  end
end
