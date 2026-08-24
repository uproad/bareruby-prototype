# frozen_string_literal: true

require "yaml"

module BareRubyProt
  module Stm32CubeBinding
    # The two layers a device or a board is described in, and the reading of both.
    #
    # The gem carries the official boards under data/, versioned with the gem. A project
    # carries its own under config/stm32cube/, found from the root the run is standing
    # at — a custom board is a YAML file placed there, never an edit to this gem.
    #
    # **On one key, the project wins.** That is the path for correcting official data
    # without waiting for a release, so the shadowing is never silent: every record
    # remembers which layer it came from, and the build writes that provenance into its
    # manifest. Files replace whole; the only reference that crosses a layer is a board
    # naming its device, which is the common case — a custom board is almost always known
    # silicon wired differently.
    module Manifests
      GEM_DATA = File.expand_path("data", __dir__)
      PROJECT_DATA = File.expand_path("config/stm32cube", Dir.pwd)

      # A manifest that cannot be read is a build that must not start, and the file to
      # fix is the whole of the useful answer.
      class Error < StandardError
        def initialize(path, message) = super("#{path}: #{message}")
      end

      # "PA5" — a port letter and a pin index, the only spelling a manifest uses.
      Pin = Struct.new(:port, :index) do
        def name = "P#{port}#{index}"
      end

      def self.pin(text, path)
        match = /\AP([A-K])(\d{1,2})\z/.match(text.to_s)
        raise Error.new(path, "not a pin name: #{text.inspect}") unless match && match[2].to_i < 16

        Pin.new(match[1], match[2].to_i)
      end

      # "512K" or "1M" — readable in the file, bytes in the program.
      def self.size(text, path)
        match = /\A(\d+)([KM])\z/.match(text.to_s)
        raise Error.new(path, "not a size: #{text.inspect} (say 512K or 1M)") unless match

        match[1].to_i * (match[2] == "K" ? 1024 : 1024 * 1024)
      end

      # One region of a device's memory. Kept apart even where regions are adjacent,
      # because bus reach and DMA visibility differ between them — the roles are how a
      # linker template places without knowing the family.
      Region = Struct.new(:name, :kind, :origin, :size, :role)

      REGION_KINDS = %w[flash ram].freeze
      REGION_ROLES = %w[code main ccm fast].freeze

      # What a chip is. Nothing here says how a board wires it.
      class Device
        FIELDS = %w[key family part define core fpu float_abi startup memory gpio_ports
                    uarts i2cs timers clock].freeze

        attr_reader :key, :family, :part, :define, :core, :fpu, :float_abi, :startup,
                    :memory, :gpio_ports, :uarts, :i2cs, :timers, :clock, :layer, :path

        def initialize(record, layer:, path:)
          @layer = layer
          @path = path
          missing = FIELDS - record.keys
          raise Error.new(path, "device is missing #{missing.join(', ')}") unless missing.empty?

          @key = record["key"]
          @family = record["family"]
          @part = record["part"]
          @define = record["define"]
          @core = record["core"]
          @fpu = record["fpu"]
          @float_abi = record["float_abi"]
          @startup = record["startup"]
          @memory = regions(record["memory"])
          @gpio_ports = record["gpio_ports"].map(&:to_s)
          @uarts = record["uarts"]
          @i2cs = record["i2cs"]
          @timers = record["timers"]
          @clock = record["clock"]
          settled
        end

        def flash = @memory.find { |region| region.role == "code" }

        def main_ram = @memory.find { |region| region.role == "main" }

        def region_of(role) = @memory.find { |region| region.role == role }

        private

        def regions(listed)
          listed.map do |one|
            unless REGION_KINDS.include?(one["kind"]) && REGION_ROLES.include?(one["role"])
              raise Error.new(@path, "region #{one['name']}: kind must be one of " \
                                     "#{REGION_KINDS.join('/')}, role one of #{REGION_ROLES.join('/')}")
            end
            Region.new(one["name"], one["kind"], Integer(one["origin"]),
                       Manifests.size(one["size"], @path), one["role"])
          end
        end

        def settled
          raise Error.new(@path, "no region has role: code") unless flash
          raise Error.new(@path, "no region has role: main") unless main_ram
        end
      end

      # One wired end of a peripheral: the pin and the alternate function that reaches it.
      Wire = Struct.new(:pin, :af)

      # A UART or an I2C bus as a board offers it: the logical id a program says, the
      # instance the silicon calls it, and the wires between them.
      Channel = Struct.new(:id, :instance, :wires, :stdout) do
        def stdout? = !!stdout
      end

      Led = Struct.new(:pin, :active_high) do
        def active_high? = !!active_high
      end

      # One pin a board offers for PWM: which timer answers it, on which capture/compare
      # channel, through which alternate function. Addressed by the pin, because that is
      # what a program says — the timer is this table's answer, never the program's word.
      PwmPin = Struct.new(:pin, :instance, :channel, :af)

      # What a board adds to a device. The device is named rather than repeated.
      class Board
        FIELDS = %w[key name family device clock uart].freeze

        attr_reader :key, :name, :family, :device_key, :clock, :led, :uarts,
                    :i2cs, :pwms, :probe, :layer, :path

        def initialize(record, layer:, path:)
          @layer = layer
          @path = path
          missing = FIELDS - record.keys
          raise Error.new(path, "board is missing #{missing.join(', ')}") unless missing.empty?

          @key = record["key"]
          @name = record["name"]
          @family = record["family"]
          @device_key = record["device"]
          @clock = record["clock"]
          @led = led_of(record["led"])
          @uarts = channels(record["uart"], %w[tx rx])
          @i2cs = channels(record["i2c"] || [], %w[scl sda])
          @pwms = pwm_pins(record["pwm"] || [])
          @probe = record["probe"] || {}
        end

        # The board's device, resolved across both layers. A board is not usable until
        # this answers, so the reference is checked where every other reference is.
        def device = Manifests.device(@device_key, @family, asked_by: @path)

        def uart(id) = @uarts.find { |channel| channel.id == id }

        def i2c(id) = @i2cs.find { |channel| channel.id == id }

        def stdout_uart = @uarts.find(&:stdout?)

        def openocd = @probe["openocd"] || {}

        private

        def led_of(record)
          return nil unless record

          Led.new(Manifests.pin(record["pin"], @path), record.fetch("active_high", true))
        end

        def channels(listed, ends)
          listed.map do |one|
            wires = ends.to_h do |wire_end|
              wire = one.fetch(wire_end) { raise Error.new(@path, "#{one['instance']}: missing #{wire_end}") }
              [wire_end, Wire.new(Manifests.pin(wire["pin"], @path), Integer(wire["af"]))]
            end
            Channel.new(Integer(one["id"]), one["instance"], wires, one["stdout"])
          end
        end

        def pwm_pins(listed)
          listed.map do |one|
            channel = Integer(one.fetch("channel") { raise Error.new(@path, "pwm #{one['pin']}: missing channel") })
            unless (1..4).cover?(channel)
              raise Error.new(@path, "pwm #{one['pin']}: channel is 1..4")
            end
            PwmPin.new(Manifests.pin(one["pin"], @path), one["instance"], channel,
                       Integer(one["af"]))
          end
        end
      end

      # --- the reading -------------------------------------------------------------

      # Both layers, read once. The gem's records are filed by family; a project's sit
      # flat under config/stm32cube/, each file saying which family it belongs to.
      def self.tables
        @tables ||= begin
          tables = { devices: {}, boards: {} }
          families.each do |family|
            read(tables, Dir[File.join(GEM_DATA, family, "devices", "*.yml")], :gem, Device)
            read(tables, Dir[File.join(GEM_DATA, family, "boards", "*.yml")], :gem, Board)
          end
          read(tables, Dir[File.join(PROJECT_DATA, "devices", "*.yml")], :project, Device)
          read(tables, Dir[File.join(PROJECT_DATA, "boards", "*.yml")], :project, Board)
          settled(tables)
        end
      end

      def self.families = Dir.children(GEM_DATA).select { |one| File.directory?(File.join(GEM_DATA, one)) }

      def self.read(tables, paths, layer, kind)
        table = tables[kind == Device ? :devices : :boards]
        paths.sort.each do |path|
          record = kind.new(YAML.safe_load_file(path), layer:, path:)
          unless families.include?(record.family)
            raise Error.new(path, "family #{record.family.inspect} is not one this gem carries " \
                                  "(#{families.join(', ')})")
          end
          table[record.key] = record
        end
      end

      # References are checked when the tables are complete rather than as files load,
      # so a board may name a device from either layer in either order.
      def self.settled(tables)
        tables[:boards].each_value do |board|
          device = tables[:devices][board.device_key]
          raise Error.new(board.path, "device #{board.device_key.inspect} is not defined in " \
                                      "either layer") unless device
          references(board, device)
        end
        tables
      end

      # A board may only wire what its silicon has. This is the check that caught the
      # difference between a manifest and a wish.
      def self.references(board, device)
        board.uarts.each { |channel| carried(board, channel, device.uarts) }
        board.i2cs.each { |channel| carried(board, channel, device.i2cs) }
        board.pwms.each { |one| carried(board, one, device.timers) }
        pins = board.uarts.flat_map { |one| one.wires.values.map(&:pin) } +
               board.i2cs.flat_map { |one| one.wires.values.map(&:pin) } +
               board.pwms.map(&:pin)
        pins << board.led.pin if board.led
        pins.each do |pin|
          unless device.gpio_ports.include?(pin.port)
            raise Error.new(board.path, "#{pin.name}: port #{pin.port} is not on #{device.key}")
          end
        end
      end

      def self.carried(board, channel, instances)
        return if instances.include?(channel.instance)

        raise Error.new(board.path, "#{channel.instance} is not on #{board.device_key}")
      end

      def self.boards = tables[:boards].values

      def self.board(key)
        tables[:boards].fetch(key.to_s) do
          raise Error.new(PROJECT_DATA, "no board is called #{key.inspect}")
        end
      end

      def self.device(key, family, asked_by:)
        found = tables[:devices][key]
        raise Error.new(asked_by, "device #{key.inspect} is not defined in either layer") unless found
        unless found.family == family
          raise Error.new(asked_by, "device #{key} is #{found.family}, not #{family}")
        end

        found
      end

      # What the build manifest records about where a record came from — the answer to
      # "which definition built this firmware".
      def self.provenance(record)
        record.layer == :gem ? "gem" : "project:#{record.path}"
      end
    end
  end
end
