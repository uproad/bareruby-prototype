# frozen_string_literal: true

require "yaml"

require "bareruby_prot/tools"

module BareRubyProt
  # What a Pico build reaches for, and where a build is told to find it afterwards.
  #
  # The lock beside this file is the whole of what is known about these; nothing is named
  # twice. The directories a build is given come out of the same entries that were used to
  # fetch them, so a version bump is one file and the build follows.
  module PicoSdkTools
    LOCK = YAML.safe_load_file(File.join(__dir__, "data/sources.lock.yml")).freeze

    # **A desk that already has one of these says so, and then it is not fetched.** Which
    # variable covers which thing is known here and nowhere else, which is why the skipping
    # is here rather than in the fetching: the ecosystem knows how to bring an archive
    # down, not that `PICO_TOOLCHAIN_PATH` is what makes bringing one down unnecessary.
    def self.install(into:)
      unless ENV["PICO_TOOLCHAIN_PATH"]
        Tools.archive(directory: LOCK["arm_gcc"]["directory"],
                      from: LOCK["arm_gcc"]["from"], **archive)
      end
      return if ENV["PICO_SDK_PATH"]

      Tools.repository(directory: LOCK["sdk"]["directory"], github: LOCK["sdk"]["github"],
                       tag: LOCK["sdk"]["tag"], commit: LOCK["sdk"]["commit"],
                       submodules: LOCK["sdk"]["submodules"])
    end

    def self.archive
      found = LOCK["arm_gcc"]["archives"][Tools.platform]
      raise "no Arm toolchain is locked for #{Tools.platform}." unless found

      { file: found["file"], sha256: found["sha256"] }
    end

    # The three the SDK will not run without. Two are fetched; the third is a directory the
    # SDK builds picotool into, which is kept out of the target's build tree because the
    # next first-stage run deletes that.
    def self.paths
      {
        "PICO_SDK_PATH" => LOCK["sdk"]["directory"],
        "PICO_TOOLCHAIN_PATH" => LOCK["arm_gcc"]["directory"],
        "PICOTOOL_FETCH_FROM_GIT_PATH" => "pico_sdk/picotool-#{LOCK['sdk']['tag']}"
      }
    end
  end
end
