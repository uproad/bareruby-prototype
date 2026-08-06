# frozen_string_literal: true

module BareRubyProt
  # A refusal a user is meant to read.
  #
  # **The difference between this and any other exception is who the reader is.** A record
  # naming a board nobody has installed is not a fault in this program: it has been asked
  # for something it cannot do, it knows exactly what, and the person who typed the command
  # is the one who can fix it. What that person needs is one sentence. A stack of frames
  # through the innards of a gem is not more information, it is the same information with
  # the answer buried in it.
  #
  # Everything else keeps its backtrace, and should: an exception nobody planned for is a
  # bug in this program, and the frames are the report.
  class Stop < RuntimeError; end
end
