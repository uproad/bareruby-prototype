# frozen_string_literal: true

require_relative "deployment"
require_relative "screen"
require_relative "stop"

module BareRubyProt
  # Which board goes under which entry, asked instead of typed. It is what
  # `target attach` does when nothing was named on the command line.
  #
  # **Two columns rather than two questions**, laid out as `target add` lays its families
  # and machines out. The boards stand to the right of the entries they could go under, and
  # settling an entry steps right into them — so what is on the right is always the boards
  # *that* entry could take, and nothing happens until both halves and the confirmation
  # have been given.
  #
  # **`--target=` is a name typed back**, out of the very file this command is about to
  # write into, and it says nothing at all about the other half. Which board is being named
  # was answered by holding a button, which is an answer that cannot be seen, cannot be
  # taken back, and gives up entirely the moment two boards are held at once — the case the
  # bus refuses today. Both halves belong on the screen: a board is a thing on the desk, and
  # an entry is a line in a file, and this is where the two are put together.
  class Roster
    include Screen

    # It draws a screen and reads single keys, so it wants a terminal and says so. Without
    # one there is still a way to say which entry is meant, and it is the option this
    # question stands in for, so that is what the sentence hands back.
    def self.chosen(entries)
      raise Stop, "target attach asks which board goes under which entry, so it needs a " \
                  "terminal. Name an entry with --target=NAME instead, and hold BOOTSEL " \
                  "on the one board being named: #{Deployment::FILE} records " \
                  "#{entries.map(&:name).join(', ')}." \
        unless $stdin.tty?

      new(entries).run
    end

    # **The bus is asked once, before the question goes up.** Nothing is written until the
    # whole of it is answered, so what is attached cannot change while it is being asked —
    # and a list read again between keypresses would be rows moving under the cursor.
    def initialize(entries)
      @entries = entries
      @free = entries.to_h { |entry| [entry.name, free_for(entry)] }
      @at = { entry: 0, board: 0 }
      @pane = :entry
      @drawn = 0
    end

    # Which boards could take a name under this entry is the binding's answer: it owns the
    # bus, and it is the one that knows what a board of this chip answers to while it is
    # sitting in its bootloader. A binding whose boards carry no name of their own has none,
    # which is an answer rather than something missing.
    def free_for(entry)
      offered = entry.target.binding
      offered.respond_to?(:board) ? offered.board.free(entry.target, taken) : []
    end

    # Every board name the record already holds. A board answering to one of them has been
    # attached, whichever entry it was attached under.
    def taken = @taken ||= @entries.flat_map(&:boards).map(&:to_s)

    def boards_of(entry) = @free.fetch(entry.name)

    # Both halves, or nothing. Backing out of the boards returns to the entries rather than
    # ending, because an entry chosen and then thought better of is the ordinary way through
    # this — and discarding at the end writes nothing at all, which is what it is for.
    def run
      hidden do
        loop do
          entry = choose_entry
          board = choose_board(entry) or next
          settled = confirm
          next if settled == :back

          return settled ? [entry, board] : nil
        end
      end
    end

    ENTRY_QUESTION = "Which entry is this board named under?"
    BOARD_QUESTION = "Which board is it?"
    CONFIRM_QUESTION = "Write it?"

    ENTRY_KEYS = "↑↓ move   →  boards   enter choose   ^C cancel"
    BOARD_KEYS = "↑↓ move   ←  entries   enter choose   esc back   ^C cancel"
    MOVING = "↑↓ move   enter choose   esc back   ^C cancel"

    def choose_entry
      @pane = :entry
      loop do
        settle
        render(ENTRY_QUESTION, columns, keys: ENTRY_KEYS)
        case keypress
        when :up then move(:entry, -1)
        when :down then move(:entry, 1)
        when :enter, :right then return @entries[@at[:entry]]
        end
      end
    end

    # The cursor on the right is put back to the top whenever the entries move, because the
    # list under it is a different list: the second board of one entry is not the second
    # board of the next, and a cursor left where it was would be pointing at whatever
    # happened to be there.
    def settle = @at[:board] = 0

    def choose_board(entry)
      @pane = :board
      loop do
        render(BOARD_QUESTION, columns, note: note_for(entry), keys: BOARD_KEYS)
        case keypress
        when :up then move(:board, -1)
        when :down then move(:board, 1)
        when :left, :back then return nil
        when :enter then return boards_of(entry)[@at[:board]]
        end
      end
    end

    ANSWERS = [true, false].freeze
    SAID = { true => "write it", false => "discard" }.freeze

    def confirm
      @pane = :confirm
      at = 0
      loop do
        render(CONFIRM_QUESTION, ANSWERS.each_with_index.map { |yes, which| row(which == at, SAID[yes]) })
        case keypress
        when :up then at = (at - 1) % ANSWERS.length
        when :down then at = (at + 1) % ANSWERS.length
        when :back then return :back
        when :enter then return ANSWERS[at]
        end
      end
    end

    def move(pane, by)
      length = pane == :entry ? @entries.length : boards_of(@entries[@at[:entry]]).length
      @at[pane] = (@at[pane] + by) % length unless length.zero?
    end

    # A board sitting in its bootloader has no name yet, and on an RP2040 not even an id of
    # its own — three boards on this desk all called themselves the same thing. So the
    # device and the port are said beside it: they are what tells one from the next until
    # this command has given them something better.
    def note_for(entry)
      offered = entry.target.binding
      return ["#{offered.key} boards carry no name of their own.",
              "There is nothing here to name."] unless offered.respond_to?(:board)
      return ["No #{entry.target.machine.chip} board is in BOOTSEL.",
              "Hold the button down, plug the board in, and start this again."] if
        boards_of(entry).empty?

      ["In BOOTSEL a board answers with its chip's own id, which several of them share.",
       "What tells them apart is the device and the port."]
    end

    # --- the screen ---------------------------------------------------------------

    def render(question, choices, note: nil, keys: MOVING)
      body = ["", *decided, "", progress, "", "  #{BOLD}#{question}#{OFF}"]
      body += Array(note).compact.map { |line| "  #{DIM}#{line}#{OFF}" }
      body += ["", *choices, "", "  #{DIM}#{keys}#{OFF}", ""]
      redraw(body)
    end

    def row(current, label) = current ? "    #{ACCENT}› #{label}#{OFF}" : "      #{label}"

    # What this run is about to do, in the three parts it is made of: the entry, the board
    # on the desk, and the name that goes into the board's flash and into the entry's
    # boards:. The name is the entry's answer rather than a question of its own, which is
    # why it settles the moment the entry does.
    def decided
      rows = { "entry" => @entries[@at[:entry]].name, "board" => chosen_board&.label,
               "name" => Deployment.next_board_name(@entries[@at[:entry]].name) }
      width = rows.keys.map(&:length).max + 1
      rows.map { |field, value| "    #{"#{field}:".ljust(width)} #{shown(field, value)}" }
    end

    def chosen_board = boards_of(@entries[@at[:entry]])[@at[:board]]

    # Dim says one thing only: nobody has settled this yet. A field is settled once the
    # question that answers it has been passed — and the name is the entry's answer rather
    # than a question of its own, so it settles when the entry does.
    ANSWERED_BY = { "entry" => :entry, "board" => :board, "name" => :entry }.freeze

    def shown(field, value)
      return dim("pending") unless value

      settled?(field) ? value : dim(value)
    end

    def settled?(field) = STEPS.index(@pane) > STEPS.index(ANSWERED_BY.fetch(field))

    STEPS = %i[entry board confirm].freeze

    def progress
      at = STEPS.index(@pane)
      "  " + STEPS.each_with_index.map do |step, which|
        next "#{ACCENT}[›] #{step}#{OFF}" if which == at
        next dim("[ ] #{step}") if which > at

        "[#{ACCENT}✓#{OFF}] #{step}"
      end.join("  ")
    end

    # The headings stand over the columns they name, past the marker every cell keeps room
    # for, or they would sit two characters left of what they head.
    def columns
      names = @entries.map(&:name)
      boards = boards_of(@entries[@at[:entry]]).map(&:label)
      width = names.map(&:length).max
      ["      #{'entry'.ljust(width + 5)}board", ""] +
        Array.new([names.length, boards.length].max) do |at|
          left = cell(names[at].to_s.ljust(width), at == @at[:entry], @pane == :entry, keep: true)
          right = cell(boards[at].to_s, at == @at[:board] && boards[at], @pane == :board)
          "    #{left}   #{right}".rstrip
        end
    end

    # Dim is for what is not in play. An entry left behind is still in play — it is the one
    # whose boards are on the right — so it stays lit while the rest of its column goes out.
    # A board is not: until the cursor arrives there, none of them has been settled on, and
    # lighting one would claim a choice nobody has made.
    def cell(text, current, active, keep: false)
      return "#{ACCENT}› #{text}#{OFF}" if current && active
      return "  #{text}" if active || (current && keep)

      "  #{DIM}#{text}#{OFF}"
    end

    def dim(text) = "#{DIM}#{text}#{OFF}"
  end
end
