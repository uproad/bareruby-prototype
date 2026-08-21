# frozen_string_literal: true

require "io/console"

module BareRubyProt
  # The screen a question is asked on: one frame, redrawn where it stands, and one key at
  # a time read out of the terminal.
  #
  # **Two commands ask questions, and there is one place that knows how.** `target add`
  # composes an entry and `target attach` points at one, which are different questions
  # about different things — but what a key means, and what it takes to redraw without
  # scrolling the answer away, is the same in both. A second reader with an idea of its
  # own about which byte is an arrow is a reader that can disagree with the first, and a
  # disagreement about that is invisible until somebody presses the key.
  #
  # What is *asked* stays with whoever asks. Nothing here holds a question, a cursor or an
  # answer — only the terminal.
  module Screen
    DIM = "\e[2m"
    BOLD = "\e[1m"
    ACCENT = "\e[36m"
    WARN = "\e[31m"
    OFF = "\e[0m"

    # The caret belongs to a line being typed, and a frame that redraws has no such line —
    # so it is put away for as long as one is up, and put back however the frame ends.
    def hidden
      print "\e[?25l"
      yield
    ensure
      print "\e[?25h"
    end

    # Drawn over itself rather than under itself. The frame is the answer taking shape, and
    # a question that scrolled its own earlier drafts up the screen would leave the reader
    # deciding which of four of them is the one still being answered.
    def redraw(body)
      print "\e[#{@drawn}A\e[0J" if @drawn.positive?
      puts body
      @drawn = body.length
    end

    ARROWS = { "A" => :up, "B" => :down, "C" => :right, "D" => :left }.freeze

    # One reader for every kind of question. A printable character comes back as itself,
    # which is what lets typing and choosing share a loop.
    #
    # **No key means two things.** Going back is escape everywhere, so the arrows are free
    # to mean only movement — which is what they mean in a list and what they have to mean
    # in a line of text. Escape arrives both alone and as the first byte of an arrow, and
    # nothing but time tells them apart: a sequence sends its rest at once, a person
    # cannot.
    def keypress
      $stdin.raw do |io|
        case (char = io.getc)
        when "\r", "\n" then :enter
        when "\u0003", nil then stop
        when "\u007f", "\b" then :backspace
        when "\t" then :tab
        when "\e" then escape(io)
        else char
        end
      end
    end

    def escape(io)
      return :back unless IO.select([io], nil, nil, 0.05)

      io.getc == "[" ? ARROWS[io.getc] : :none
    end

    # The caret is not put back here. Whatever ends a frame ends inside the block
    # `hidden` is holding open, and its ensure is what restores the terminal — including
    # this, because leaving is a SystemExit like any other.
    def stop
      puts
      exit 130
    end
  end
end
