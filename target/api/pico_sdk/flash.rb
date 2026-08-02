# frozen_string_literal: true

module BareRubyProt
  # A .uf2 carries the family id of the chip it was built for, so the image says which
  # boards are candidates and only two of the same chip need telling apart. That is what
  # flash.sh does, and it is left in the shell it was proved on real hardware in.
  #
  # Several identical boards take the same image, so a deployment names them all and each
  # is written in turn.
  module PicoSdkFlash
    SCRIPT = File.expand_path("flash.sh", __dir__)

    def self.run(directory, boards:, options: {})
      image = File.join(directory, "bareruby_program.uf2")
      return system(SCRIPT, image, exception: true) if boards.empty?

      boards.each { |board| system(SCRIPT, "--board", board.to_s, image, exception: true) }
    end
  end
end
