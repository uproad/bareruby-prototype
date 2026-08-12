# frozen_string_literal: true

require "fileutils"
require "io/console"
require "yaml"

require_relative "deployment"
require_relative "stop"

module BareRubyProt
  # Asking, rather than being told. A composition takes three answers and none of them is
  # a thing to be looked up, so what is asked for is the machine — first roughly, by the
  # family its maker sells it in, then exactly — and the three follow from the answer.
  #
  # It asks for a machine rather than a board because not every one of them is a board:
  # this desk itself is an entry, with every peripheral traced instead of driven. What to
  # ask is data, in each binding's own family.yml, so a machine that does not exist yet is
  # reached by adding a binding rather than by editing a list here.
  #
  # **What is on screen is the entry itself, in the words the file will use** — not a list
  # of questions that produces one afterwards, but the entry, being written. A composition
  # is three answers rather than one, and that is only visible if all three are in view
  # when a single choice fills them in. The questions ride above it on one line, so the
  # answer being given is never far from the thing it is being given to.
  class Catalog
    # A family arrives with the binding that can build it, beside the four files that
    # binding already owns. Nothing here lists them.
    #
    #   key       what the family is called where one has to be named
    #   label     what it is called on screen. The family's own name and nothing more —
    #             what it is reached through is one of the three the composition already
    #             spells out, and repeating it only makes the reader carry it twice.
    #   targets   the target names it offers, in the order they are offered
    #   asks      what it needs beyond the machine, the name and the debug build, which
    #             every entry has and which `target add` asks for itself. Each one takes:
    #
    #               key           where the answer goes. `options.` prefixes go under it.
    #               label         the question.
    #               kind          text | path | list | choice
    #               choices       for kind: choice.
    #               optional      true to let an empty answer skip the key entirely.
    #               hint          shown under the question.
    #               hint_command  run, and its output shown under the question.
    #
    # Which boards are attached is not among them. It is not knowable when an entry is made
    # — a serial is read off the machine in front of you, and an RP2040 answers with a
    # different one in BOOTSEL than while running — and it is not needed until two machines
    # of one chip are attached at once, which flashing detects and prints the candidates
    # for. `boards:` is written empty and filled in when that day comes.
    #
    # **Which bindings there are is not asked twice.** This side used to glob for them on
    # its own, which meant two searches that had to agree about what a binding is and where
    # it may live. The compiler already answers that, so the family a binding offers is
    # read from beside the declaration it answered with.
    OFFER = "family.yml"

    # The one that needs no hardware comes first, because it is the only family that is
    # always there — everything else is a machine somebody went out and bought, and in time
    # each will arrive on its own rather than from here. The rest are alphabetical, so a
    # name is found by looking where it would be, and so anything attaching later has one
    # obvious place to go: below.
    OWN = "host"

    DIM = "\e[2m"
    BOLD = "\e[1m"
    ACCENT = "\e[36m"
    WARN = "\e[31m"
    OFF = "\e[0m"

    # The three a machine settles at once. They are shown together for that reason.
    COMPOSITION = %w[machine binding triple].freeze

    # Written whether or not they say anything. Reading an entry tolerates a missing
    # `debug`, but that is a kindness to a file written by hand, not a reason for one
    # written by a command to leave it out — **an entry should read the same way to
    # everyone who opens it**, without a default anybody has to already know.
    ALWAYS = ["name", *COMPOSITION, "debug", "boards"].freeze

    # Written but never asked. Which boards are attached is true of a desk at a moment,
    # not of an entry, and the value is read off the machine rather than known — so the
    # field is laid out empty and filled in when flashing says which one it needs.
    UNASKED = { "boards" => [] }.freeze

    # What an offer is made of: the family's own short key, the heading a person reads, and
    # the compositions to put under it. **A binding that cannot answer all three offers
    # nothing**, and none of the three has a stand-in worth inventing — a heading made up
    # here would make a gem that forgot one look like a gem that has one.
    OFFERED = %w[key label targets].freeze

    # **Which gem an offer came out of is answered here and not asked for again.** It is
    # the one fact about a family that the family's own file cannot state — a gem does not
    # know its own name from the inside, and a file that claimed one could claim somebody
    # else's. The declaration's path knows, and this is the only place holding it.
    GEM = "gem"

    def self.families
      found = Target.declarations.filter_map { |declaration| offer_of(declaration) }
      own, rest = found.partition { |one| one["key"] == OWN }
      own + rest.sort_by { |one| one["label"] }
    end

    # **A gem that is not what it says it is stops at itself.** This is the one place
    # somebody else's file is taken at its word, so it is the one place their mistake could
    # take this command down with it — and it did: one binding without an offer, and
    # neither `target add` nor `target list` worked for any of them.
    #
    # A binding that registers machines and then offers no way to choose one is a broken
    # gem rather than a binding with an answer, which is why this is said rather than
    # passed over. But it is not this program's fault and not the fault of whoever typed
    # the command, so it is neither a backtrace nor a refusal: it is said once, the gem is
    # left out, and everything else answers as usual.
    #
    # **A file that never arrived and a file that does not answer are different mistakes.**
    # Nothing shipped is a packaging one — a gemspec listing `lib/**/*.rb` takes the binding
    # and leaves its offer behind, and the gem looks complete from the working tree it was
    # built in. Something shipped that does not answer is a content one, in a file that is
    # there to be looked at. Different errands, so different sentences.
    #
    # Further than that is not worth telling apart: unreadable, and short of one of the
    # three answers, send whoever wrote it to the same file — which is why asking for the
    # three by name is enough of a check, and enumerating the ways to be wrong would be
    # writing a checker.
    def self.offer_of(declaration)
      at = File.join(File.dirname(declaration), OFFER)
      unless File.exist?(at)
        warn "WARN: #{OFFER} not found in gem #{gem_of(declaration)}"
        warn "(#{File.dirname(declaration)})"
        return nil
      end

      # **Three ways a file that is there can fail to answer, and no fourth**: it is not
      # YAML, it is not a mapping, or it is short of one of the three. Each arrives as its
      # own kind, so asking for the three is the whole of the check. Anything else raised
      # in here is this program's own mistake, and that is a backtrace rather than a
      # sentence about somebody's gem.
      Hash(YAML.safe_load_file(at))
        .tap { |offer| offer.fetch_values(*OFFERED) }
        .merge(GEM => gem_of(declaration))
    rescue Psych::Exception, TypeError, KeyError
      warn "WARN: #{OFFER} is broken in gem #{gem_of(declaration)}"
      warn "(#{File.dirname(declaration)})"
      nil
    end

    # **A gem is under its directory, not under a name its name begins with.** Every gem
    # here is `bareruby_prot` followed by what it adds, so comparing text alone makes the
    # ecosystem gem the answer for all of them — `bareruby_prot-binding-pico_sdk/lib/…`
    # starts with `bareruby_prot` and always did. The separator is what makes the
    # comparison about directories rather than about spelling.
    #
    # The fallback is the binding's own directory name, which is what there is to say when
    # a declaration is not under any loaded gem — a working tree run straight off the load
    # path. It is not a gem name and does not pretend to be one.
    def self.gem_of(declaration)
      found = Gem.loaded_specs.values.find { |one| declaration.start_with?("#{one.full_gem_path}/") }
      found&.name || File.basename(File.dirname(declaration))
    end

    # **Every heading says which gem it came out of.** What this command can offer is
    # exactly what is installed, and a machine missing from it is almost never a machine
    # this ecosystem cannot reach — it is a line still commented out in the Gemfile. Naming
    # the gem beside each family is what makes that legible without a second catalogue to
    # disagree with the first: the reader sees which gems answered, and so which one did
    # not.
    def self.list
      families.each do |family|
        puts "#{family['label']}  (#{family[GEM]})"
        family["targets"].each do |name|
          spelling = Deployment.spelling(Target[name])
          puts "  #{name}"
          puts "    #{Deployment::FIELDS.map { |field| "#{field}: #{spelling[field]}" }.join('  ')}"
        end
        puts
      end
      0
    end

    # It draws a screen and reads single keys, so it wants a terminal and says so. Without
    # this the raw read fails with an ioctl error from inside the reader, which describes
    # the mechanism rather than the situation — and the situation, in a pipe or a CI job,
    # is that this is the wrong command to be reaching for.
    #
    # **What it sends the reader to is the record itself.** It used to name a `.sample`
    # beside it, which exists in the checkout these gems are built from and in no project
    # anybody has — `new` writes one file into `config/`, and it is this one. It opens with
    # a comment on every field, so the shape is where the entry goes rather than in a file
    # to go and find; what those fields may say depends on which gems are installed, which
    # is a question only a command can answer.
    def self.add
      raise Stop, "target add asks questions, so it needs a terminal. Write the entry " \
                  "into #{Deployment::FILE} instead — every field is explained in the " \
                  "comments it opens with, and `bareruby target list` prints what the " \
                  "first three can say." \
        unless $stdin.tty?

      Session.new.run
    end

    # One run of `target add`. It keeps the answers, knows which question is current, and
    # moves either way through them — a choice made early is not a choice made forever.
    class Session
      def initialize
        @answers = {}
        @cursor = {}
        @preview = nil
        @at = 0
        @drawn = 0
      end

      def run
        print "\e[?25l"
        advance while @at < steps.length
        Catalog.write(written) if @answers["confirm"]
        0
      ensure
        print "\e[?25h"
      end

      # Going back un-answers the question it lands on and everything after it. The screen
      # then says the same thing on the way back as it does on the way in — settled before
      # the question, pending from it on — and a question being asked is never shown as
      # already answered. It is also the only way a family can be changed safely: what the
      # one before it asked for is no longer part of this entry.
      #
      # Where the cursor was is kept even so. That is not an answer, only the place the
      # eye left off, and starting over from the top of a list nobody meant to leave is
      # a cost with nothing bought by it.
      def advance
        return @at += 1 unless ask(steps[@at]) == :back

        @at = [@at - 1, 0].max
        steps[@at..].each { |key| @answers.delete(key) }
      end

      # family and machine come first because they settle the most. name and debug are
      # true of every entry, so they are asked here rather than by any one family. What a
      # family needs beyond them comes after, and nothing is written before it is shown.
      # family is not among them. It names no field of the entry, so answering it would be
      # a transition that settles nothing — which is exactly what it felt like. It is a
      # way through the machines instead, and lives inside that one question.
      def steps = %w[machine name debug] + asks.map { |ask| ask["key"] } + ["confirm"]

      # Asking nothing beyond the machine is the ordinary case, so a family that says
      # nothing about it is one of those rather than one to complain about.
      def asks = family ? family["asks"] || [] : []

      # **What a debug build buys is the binding's answer, so the binding is what says
      # it.** Only one of them means anything by the field: a pico-sdk firmware keeps its
      # USB interface up and is reflashed without the button, while the others take the
      # flag and do nothing with it. A line written here would be true of one family and
      # a lie to the rest, and a family with nothing to say answers by having no hint —
      # the same shape as a family that asks nothing.
      def debug_hint = family&.fetch("debug_hint", nil)

      # Which family is in play: the one being moved through while the machines are open,
      # or — once a machine is chosen — the one that holds it. It is never stored, because
      # a machine already says which family it belongs to.
      def family
        return family_in(tentative["family"]) if tentative["family"]

        Catalog.families.find { |one| one["targets"].include?(tentative["machine"]) }
      end

      def family_in(label) = Catalog.families.find { |one| one["label"] == label }

      def ask(key)
        case key
        when "machine" then choose_machine
        when "name" then type(key, "Name it?", suggest: suggestion)
        when "debug" then choose(key, [true, false], note: debug_hint, &:to_s)
        when "confirm" then choose(key, [true, false]) { |yes| yes ? "write it" : "discard" }
        else family_ask(key)
        end
      end

      MOVING = "↑↓ move   enter choose   esc back   ^C cancel"
      FAMILIES = "↑↓ move   →  machines   ^C cancel"
      MACHINES = "↑↓ move   ←  families   enter choose   ^C cancel"
      TYPING = "tab fill   ←→ move   ⌫ delete   enter accept   esc back   ^C cancel"

      # Two columns rather than two questions. The families stand to the left of the
      # machines they hold, and moving right steps into them — so choosing a family is a
      # move rather than an answer, and nothing is settled until a machine is named.
      #
      # It is also what keeps a binding honest. A family whose machines are all reached
      # the same way shows that binding early, dimmed, because every candidate agrees on
      # it — not because a family decides one. The day a family is reached two ways, the
      # agreement fails and the field waits for the machine, with nothing here to change.
      def choose_machine
        pane = :family
        at = { family: @cursor["family"] || 0, machine: @cursor["machine"] || 0 }
        loop do
          targets = Catalog.families[at[:family]]["targets"]
          at[:machine] = 0 if at[:machine] >= targets.length
          @cursor["family"] = at[:family]
          @cursor["machine"] = at[:machine]
          @preview = { "family" => Catalog.families[at[:family]]["label"] }
          @preview["machine"] = targets[at[:machine]] if pane == :machine
          render(question_for("machine"), columns(targets, at, pane),
                 keys: pane == :family ? FAMILIES : MACHINES)
          case keypress
          when :up then at[pane] = (at[pane] - 1) % length_of(pane, targets)
          when :down then at[pane] = (at[pane] + 1) % length_of(pane, targets)
          when :right then (pane = :machine)
          when :left, :back then (pane = :family)
          when :enter
            next pane = :machine if pane == :family

            @preview = nil
            return keep("machine", targets[at[:machine]])
          end
          at[:machine] = 0 if pane == :family
        end
      end

      def length_of(pane, targets)
        pane == :family ? Catalog.families.length : targets.length
      end

      # The inactive column is still shown — a family is chosen by seeing what it holds —
      # but dimmed and unmarked, so only one cursor is ever on screen.
      def columns(targets, at, pane)
        labels = Catalog.families.map { |one| one["label"] }
        width = labels.map(&:length).max
        # The headings stand over the columns they name — past the marker each cell keeps
        # room for, or they would sit two characters left of what they head.
        [+"      #{'family'.ljust(width + 5)}machine", +""] +
          Array.new([labels.length, targets.length].max) do |row|
            left = cell(labels[row].to_s.ljust(width), row == at[:family], pane == :family, keep: true)
            right = cell(targets[row].to_s, row == at[:machine] && targets[row], pane == :machine)
            "    #{left}   #{right}".rstrip
          end
      end

      # Dim is for what is not in play. A family left behind is still in play — it is the
      # one whose machines are on the right — so it stays lit while the rest of its column
      # goes out. A machine is not: until the cursor arrives there, none of them has been
      # settled on, and lighting one would claim a choice nobody has made.
      def cell(text, current, active, keep: false)
        return "#{ACCENT}› #{text}#{OFF}" if current && active
        return "  #{text}" if active || (current && keep)

        "  #{DIM}#{text}#{OFF}"
      end

      # While a list is open, the choice under the cursor is shown as though it had been
      # made — dimmed, because it has not been. That is what makes the three a machine
      # settles visible **before** it is settled, which is the one place the lesson lands.
      def choose(key, choices, note: nil)
        index = @cursor[key] || choices.index { |one| chosen?(key, one) } || 0
        loop do
          @cursor[key] = index
          @preview = { key => stored(choices[index]) }
          render(question_for(key),
                 choices.each_with_index.map { |one, at| row(at == index, yield(one)) }, note:)
          case keypress
          when :up then index = (index - 1) % choices.length
          when :down then index = (index + 1) % choices.length
          when :back then return (@preview = nil) || :back
          when :enter then return (@preview = nil) || keep(key, choices[index])
          end
        end
      end

      # Typing is drawn rather than read, for the same reason choosing is: a line the
      # terminal echoes for itself cannot belong to a frame that redraws.
      def type(key, question, note: nil, kind: "text", suggest: nil)
        text = +@answers[key].to_s
        caret = text.length
        problem = nil
        loop do
          @preview = { key => answered(key, text, kind) }
          render(question, [typed(text, caret, suggest)], note: note, keys: TYPING,
                                                          problem: problem)
          press = keypress
          problem = nil unless press == :enter
          case press
          when :enter
            problem = refused(key, text)
            return (@preview = nil) || keep(key, answered(key, text, kind)) unless problem
          when :back then return (@preview = nil) || :back
          when :tab then caret = text.replace(suggest.to_s).length if text.empty? && suggest
          when :left then caret -= 1 if caret.positive?
          when :right then caret += 1 if caret < text.length
          when :backspace then (text.slice!(caret - 1) and caret -= 1) if caret.positive?
          when String then (text.insert(caret, press) and caret += 1)
          end
        end
      end

      def listed(text) = text.split(/[,\s]+/).reject(&:empty?)

      def answered(key, text, kind) = kind == "list" ? listed(text) : text.strip

      # A name is the directory the artifacts land in, so two entries cannot share one.
      # The check is on what would be written rather than on what was typed, because an
      # empty answer still writes something.
      def refused(key, text)
        return nil unless key == "name"

        wanted = blank?(text.strip) ? composed : text.strip
        return nil unless taken.include?(wanted)

        "#{wanted} is already taken by another entry."
      end

      # What is suggested is what nobody has yet. The machine on its own reads best, and
      # when it is spoken for, **the binding is added only if it tells the two apart** —
      # against an entry reached the very same way it distinguishes nothing, and
      # `pico-pico_sdk` beside a `pico` that is also pico-sdk is a longer word for the
      # same thing. There, and when even the binding is not enough, letters follow.
      #
      # **Letters rather than numbers, because these machines are numbered.** `pico_2`
      # sits one underscore away from `pico2`, which is a different board, and a name that
      # can be misread as another machine is worse than a long one. What the second entry
      # is actually for — a second board of the same kind, running something else — is
      # past what a suggestion can know, so it offers a name that is merely free.
      def suggestion
        machine = visible["machine"]
        return nil unless machine
        return machine unless taken.include?(machine)
        return lettered(machine) if bindings_of(machine).include?(visible["binding"])

        qualified = "#{machine}-#{visible['binding']}"
        taken.include?(qualified) ? lettered(qualified) : qualified
      end

      # The unsuffixed name is the first of them, so the letters start at the second.
      def lettered(base) = ("b".."z").lazy.map { |at| "#{base}-#{at}" }.find { |one| !taken.include?(one) }

      def bindings_of(name)
        claimed.select { |one| one["name"] == name }.map { |one| one["binding"] }
      end

      def taken = claimed.map { |one| one["name"] }

      # Every directory an entry already claims: the name it was given, or the composition
      # it falls back to, alongside what reached it.
      def claimed
        Deployment.recorded.map do |one|
          { "name" => one["name"] || COMPOSITION.map { |field| one[field] }.join("-"),
            "binding" => one["binding"] }
        end
      end

      # The caret is drawn rather than left to the terminal, so that it sits inside the
      # frame instead of wherever the last write happened to leave it.
      #
      # An empty field shows what tab would put in it, dimmed and with the caret still at
      # the left — it is an offer, not a value, and typing anything takes it away. Empty
      # the field again and the offer comes back. What is being suggested is not what an
      # empty answer writes: the entry above says that, and it is the long unmistakable
      # one, while this is the short name most people would have typed.
      def typed(text, caret, suggest = nil)
        return "    #{ACCENT}›#{OFF} #{ghost(suggest)}" if text.empty? && suggest

        "    #{ACCENT}›#{OFF} #{text[0, caret]}\e[7m#{text[caret] || ' '}#{OFF}#{text[(caret + 1)..]}"
      end

      def ghost(suggest) = "\e[7m#{suggest[0]}#{OFF}#{DIM}#{suggest[1..]}#{OFF}"

      def family_ask(key)
        ask = asks.find { |one| one["key"] == key }
        return choose(key, ask["choices"]) { |choice| choice } if ask["kind"] == "choice"

        type(key, "#{ask['label']}?", note: [ask["hint"], *ran(ask)], kind: ask["kind"])
      end

      # A hint command's output is caught rather than printed, so that it lands inside the
      # frame with everything else instead of scrolling it away.
      def ran(ask) = ask["hint_command"] ? `#{ask['hint_command']} 2>&1`.lines.map(&:chomp) : []

      QUESTIONS = {
        "machine" => "Which machine?",
        "debug" => "Debug build?",
        "confirm" => "Write it?"
      }.freeze

      def question_for(key) = QUESTIONS[key] || "#{key}?"

      # An answer is kept as the thing that was chosen, never as what it implies. A family
      # is kept as its label and a machine as its target name, so that coming back to a
      # question finds the answer that was given to it. What a machine settles is derived
      # instead — three fields that no question owns cannot be answers to any of them.
      def keep(key, value)
        @answers[key] = stored(value)
        :next
      end

      def stored(value) = value.is_a?(Hash) ? value["label"] : value

      # Three readings of the same entry: what has been answered, what the cursor would
      # add if the key were pressed, and the two together as the screen shows them.
      def settled = @answers.merge(spelling_of(@answers))

      def tentative = @preview ? @answers.merge(@preview) : @answers

      def visible = tentative.merge(spelling_of(tentative))

      # **A field is settled the moment every candidate still in play agrees on it.** One
      # machine leaves one candidate and settles all three, which is the usual way. But a
      # family whose targets are reached through the same binding settles that binding
      # before any machine is named, and a family holding one target settles everything.
      #
      # It is a count of what the answers still allow rather than a rule about families,
      # so a family reached through two bindings stops settling one — which is the case
      # this design exists for, and the case a rule would have had to be rewritten for.
      def spelling_of(source)
        names = candidates(source)
        return {} if names.empty?

        spellings = names.map { |name| Deployment.spelling(Target[name]) }
        Deployment::FIELDS.each_with_object({}) do |field, agreed|
          values = spellings.map { |one| one[field] }.uniq
          agreed[field] = values.first if values.one?
        end
      end

      def candidates(source)
        return [source["machine"]] if source["machine"]

        family_in(source["family"])&.fetch("targets", []) || []
      end

      def chosen?(key, choice)
        @answers[key] == (choice.is_a?(Hash) ? choice["label"] : choice)
      end

      # Only what the file takes: a name if one was given, the composition, and answers
      # that said something. `debug: false` and an empty list said nothing.
      def written
        source = settled
        keys = ALWAYS + (source.keys - ALWAYS - %w[family confirm])
        keys.each_with_object({}) do |key, entry|
          value = source.fetch(key) { UNASKED[key] }
          value = composed if key == "name" && blank?(value)
          entry[key] = value if writes?(key, value)
        end
      end

      def writes?(key, value) = ALWAYS.include?(key) || !blank?(value)

      # --- the screen ---------------------------------------------------------------

      def render(question, choices, note: nil, keys: MOVING, problem: nil)
        body = ["", *entry_lines, "", progress, "", "  #{BOLD}#{question}#{OFF}"]
        body += Array(note).compact.map { |line| "  #{DIM}#{line}#{OFF}" }
        body += ["", *choices] unless choices.empty?
        body += ["", "  #{WARN}#{problem}#{OFF}"] if problem
        body += ["", "  #{DIM}#{keys}#{OFF}", ""]
        print "\e[#{@drawn}A\e[0J" if @drawn.positive?
        puts body
        @drawn = body.length
      end

      def row(current, label) = current ? "    #{ACCENT}› #{label}#{OFF}" : "      #{label}"

      # The entry as the file will hold it. A field nobody has answered says so, and the
      # name shows what this build would be called if it is never given one.
      def entry_lines
        rows = laid_out
        width = rows.map { |label, _| label.length }.max + 1
        rows.each_with_index.map do |(label, field), at|
          "    #{at.zero? ? '-' : ' '} #{"#{label}:".ljust(width)} #{field ? value_of(field) : ''}".rstrip
        end
      end

      # A key with a dot in it is one key inside another, and the file writes it that way,
      # so this shows it that way too. A heading of its own, and its members indented under
      # it — otherwise the entry on screen and the entry in the file are different shapes.
      def laid_out
        ALWAYS.map { |key| [key, key] } +
          asks.flat_map { |one| one["key"] }.each_with_object([]) do |key, rows|
            next rows << [key, key] unless key.include?(".")

            outer, inner = key.split(".")
            rows << [outer, nil] unless rows.any? { |label, field| label == outer && field.nil? }
            rows << ["  #{inner}", key]
          end
      end

      # Dim says one of two things, and only ever those: not settled yet, or settled and
      # not going into the file. A `debug: false` is neither, so it is written plainly.
      def value_of(field)
        return dim(default_name) if field == "name" && blank?(visible["name"])
        return dim(shown(UNASKED[field])) if UNASKED.key?(field) && !@answers.key?(field)
        return dim("pending") unless visible.key?(field)
        return dim(shown(visible[field])) unless settled.key?(field)

        writes?(field, settled[field]) ? shown(settled[field]) : dim(shown(settled[field]))
      end

      # What the artifacts land under when no name is given. Before a machine is chosen it
      # is the three field names themselves, which is the shape of the answer to come.
      def composed = COMPOSITION.map { |field| visible[field] || field }.join("-")

      # What an empty answer writes. Until a machine is chosen the three are their own
      # field names rather than values, so it is bracketed — it is the shape the name will
      # take, not a name. Once chosen it is the name, and brackets would deny that.
      def default_name
        COMPOSITION.all? { |field| visible[field] } ? composed : "(#{composed})"
      end

      def dim(text) = "#{DIM}#{text}#{OFF}"

      def blank?(value) = [nil, false, "", []].include?(value)

      def shown(value)
        case value
        when true then "true"
        when false then "false"
        when Array then value.empty? ? "[]" : value.join(", ")
        else value.to_s
        end
      end

      # Every question on one line, in the order they are asked, so what is left is one
      # glance away rather than a screen of its own.
      def progress
        "  " + steps.each_with_index.map do |key, at|
          short = key.split(".").last
          next "#{ACCENT}[›] #{short}#{OFF}" if at == @at
          next dim("[ ] #{short}") if at > @at

          "[#{ACCENT}✓#{OFF}] #{short}"
        end.join("  ")
      end

      ARROWS = { "A" => :up, "B" => :down, "C" => :right, "D" => :left }.freeze

      # One reader for both kinds of question. A printable character comes back as itself,
      # which is what lets typing and choosing share a loop.
      #
      # **No key means two things.** Going back is escape everywhere, so the arrows are
      # free to mean only movement — which is what they mean in a list and what they have
      # to mean in a line of text. Escape arrives both alone and as the first byte of an
      # arrow, and nothing but time tells them apart: a sequence sends its rest at once,
      # a person cannot.
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

      def stop
        print "\e[?25h"
        puts
        exit 130
      end
    end

    # A key with a dot in it is a key inside a key, which is how the answers only one
    # binding needs stay under that binding's own heading rather than spreading across it.
    def self.place(record)
      record.each_with_object({}) do |(key, value), entry|
        outer, inner = key.split(".")
        next entry[key] = value unless inner

        entry[outer] = (entry[outer] || {}).merge(inner => value)
      end
    end

    # Appended as text rather than written back as YAML, so that whatever else is in the
    # file — the other entries, and whatever was said about them — survives being added to.
    def self.write(record)
      FileUtils.mkdir_p(File.dirname(Deployment::FILE))
      File.write(Deployment::FILE, "targets:\n") unless File.exist?(Deployment::FILE)
      File.open(Deployment::FILE, "a") { |file| file.write(rendered(place(record))) }
      puts "Added to #{Deployment::FILE}:"
      puts rendered(place(record))
    end

    def self.rendered(record)
      first, *rest = record.map { |key, value| lines(key, value) }.flatten
      ["  - #{first}", *rest.map { |line| "    #{line}" }].join("\n") + "\n"
    end

    def self.lines(key, value)
      case value
      when Array then value.empty? ? ["#{key}: []"] : ["#{key}:", *value.map { |item| "  - #{item}" }]
      when Hash then ["#{key}:", *value.map { |inner, item| "  #{inner}: #{item}" }]
      else ["#{key}: #{value}"]
      end
    end
  end
end
