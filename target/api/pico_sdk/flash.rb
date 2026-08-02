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

    # The script says what went wrong when it goes wrong, so its answer is passed on as it
    # is rather than raised over. Writing stops at the first board that refuses.
    def self.run(directory, boards:, options: {})
      image = File.join(directory, "bareruby_program.uf2")
      return system(SCRIPT, image) if boards.empty?

      boards.all? { |board| system(SCRIPT, "--board", board.to_s, image) }
    end
  end
end
