# frozen_string_literal: true

module BareRubyProt
  module Stm32CubeBinding
    module Stm32F4
      # One board's clock profile, checked against its device's limits and rendered as
      # the C that configures it. Every figure is computed here first — a profile that
      # cannot be proved inside the device's constraints refuses to become code, which
      # is what keeps "set it to the maximum" from ever being implicit.
      #
      # The PLL structure is this family's and no other's: F0 has no such PLL and H7 has
      # three, so this file is what a second family replaces rather than parameterizes.
      class Clock
        DIVIDERS = { 1 => "DIV1", 2 => "DIV2", 4 => "DIV4", 8 => "DIV8", 16 => "DIV16" }.freeze
        AHB_DIVIDERS = [1, 2, 4, 8, 16, 64, 128, 256, 512].freeze
        SOURCES = %w[hsi hse-crystal hse-bypass].freeze

        def initialize(board)
          @board = board
          @device = board.device
          @profile = board.clock
          @limits = @device.clock
          prove
        end

        attr_reader :sysclk, :hclk, :apb1, :apb2, :latency

        def pll = @profile["pll"]

        def hse? = @profile["source"].start_with?("hse")

        def input = hse? ? Integer(@profile["hse_hz"]) : Integer(@limits["hsi_hz"])

        # The arithmetic, and the refusal. Raising names the file, because the file is
        # what has to change.
        def prove
          refuse "clock source must be one of #{SOURCES.join(', ')}" unless SOURCES.include?(@profile["source"])
          refuse "an HSE profile names hse_hz" if hse? && !@profile["hse_hz"]
          scale = Integer(@profile.fetch("regulator_scale", 1))
          refuse "regulator_scale is 1, 2 or 3" unless (1..3).cover?(scale)
          @sysclk = pll ? proved_pll : input
          buses
        end

        def proved_pll
          m, n, p = %w[m n p].map { |name| Integer(pll.fetch(name)) }
          refuse "PLLM is 2..63" unless (2..63).cover?(m)
          refuse "PLLN is 50..432" unless (50..432).cover?(n)
          refuse "PLLP is 2, 4, 6 or 8" unless [2, 4, 6, 8].include?(p)
          refuse "PLLQ is 2..15" unless (2..15).cover?(Integer(pll.fetch("q")))

          vco_in = input / m
          vco_out = vco_in * n
          low, high = @limits["vco_in_hz"]
          refuse "VCO input #{vco_in} Hz is outside #{low}..#{high}" unless (low..high).cover?(vco_in)
          low, high = @limits["vco_out_hz"]
          refuse "VCO output #{vco_out} Hz is outside #{low}..#{high}" unless (low..high).cover?(vco_out)
          vco_out / p
        end

        def buses
          ahb = Integer(@profile.fetch("ahb_divider", 1))
          apb1_divider = Integer(@profile.fetch("apb1_divider", 1))
          apb2_divider = Integer(@profile.fetch("apb2_divider", 1))
          refuse "ahb_divider is one of #{AHB_DIVIDERS.join(', ')}" unless AHB_DIVIDERS.include?(ahb)
          [apb1_divider, apb2_divider].each do |divider|
            refuse "APB dividers are one of #{DIVIDERS.keys.join(', ')}" unless DIVIDERS.key?(divider)
          end

          @hclk = @sysclk / ahb
          @apb1 = @hclk / apb1_divider
          @apb2 = @hclk / apb2_divider
          ceiling "SYSCLK", @sysclk, @limits["max_sysclk_hz"]
          ceiling "APB1", @apb1, @limits["max_apb1_hz"]
          ceiling "APB2", @apb2, @limits["max_apb2_hz"]
          @latency = (@hclk + @limits["flash_wait_hz"] - 1) / @limits["flash_wait_hz"] - 1
        end

        def ceiling(name, value, most)
          refuse "#{name} #{value} Hz is over this device's #{most} Hz" if value > most
        end

        def refuse(message)
          raise Manifests::Error.new(@board.path, "clock: #{message}")
        end

        # ------------------------------------------------------------------------------

        # The C is written from the proved figures, never the other way around. What it
        # configures is exactly what prove accepted, and the comment it carries says what
        # the profile lands at, so a map file and a manifest can be checked against it.
        def configure_text
          <<~C
            /* #{summary} */
            static void bareruby_board_clock(void) {
                RCC_OscInitTypeDef oscillators = {0};
                RCC_ClkInitTypeDef buses = {0};

                __HAL_RCC_PWR_CLK_ENABLE();
                __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE#{@profile.fetch('regulator_scale', 1)});

            #{oscillator_text.chomp}
                if (HAL_RCC_OscConfig(&oscillators) != HAL_OK) {
                    bareruby_board_fault();
                }

                buses.ClockType = RCC_CLOCKTYPE_SYSCLK | RCC_CLOCKTYPE_HCLK
                                | RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2;
                buses.SYSCLKSource = #{pll ? 'RCC_SYSCLKSOURCE_PLLCLK' : sysclk_source};
                buses.AHBCLKDivider = RCC_SYSCLK_#{ahb_name};
                buses.APB1CLKDivider = RCC_HCLK_#{DIVIDERS.fetch(Integer(@profile.fetch('apb1_divider', 1)))};
                buses.APB2CLKDivider = RCC_HCLK_#{DIVIDERS.fetch(Integer(@profile.fetch('apb2_divider', 1)))};
                if (HAL_RCC_ClockConfig(&buses, FLASH_LATENCY_#{@latency}) != HAL_OK) {
                    bareruby_board_fault();
                }
            }
          C
        end

        def summary
          "#{@profile['source']} #{input / 1_000_000} MHz -> SYSCLK #{@sysclk / 1_000_000} MHz, " \
            "AHB #{@hclk / 1_000_000}, APB1 #{@apb1 / 1_000_000}, APB2 #{@apb2 / 1_000_000}, " \
            "#{@latency} wait state#{@latency == 1 ? '' : 's'}"
        end

        def ahb_name
          divider = Integer(@profile.fetch("ahb_divider", 1))
          divider == 1 ? "DIV1" : "DIV#{divider}"
        end

        def sysclk_source = hse? ? "RCC_SYSCLKSOURCE_HSE" : "RCC_SYSCLKSOURCE_HSI"

        def oscillator_text
          lines = ["    oscillators.OscillatorType = #{hse? ? 'RCC_OSCILLATORTYPE_HSE' : 'RCC_OSCILLATORTYPE_HSI'};"]
          if hse?
            state = @profile["source"] == "hse-bypass" ? "RCC_HSE_BYPASS" : "RCC_HSE_ON"
            lines << "    oscillators.HSEState = #{state};"
          else
            lines << "    oscillators.HSIState = RCC_HSI_ON;"
            lines << "    oscillators.HSICalibrationValue = RCC_HSICALIBRATION_DEFAULT;"
          end
          lines.concat(pll_text)
          "#{lines.join("\n")}\n"
        end

        def pll_text
          return ["    oscillators.PLL.PLLState = RCC_PLL_NONE;"] unless pll

          lines = ["    oscillators.PLL.PLLState = RCC_PLL_ON;",
                   "    oscillators.PLL.PLLSource = #{hse? ? 'RCC_PLLSOURCE_HSE' : 'RCC_PLLSOURCE_HSI'};",
                   "    oscillators.PLL.PLLM = #{Integer(pll.fetch('m'))};",
                   "    oscillators.PLL.PLLN = #{Integer(pll.fetch('n'))};",
                   "    oscillators.PLL.PLLP = RCC_PLLP_DIV#{Integer(pll.fetch('p'))};",
                   "    oscillators.PLL.PLLQ = #{Integer(pll.fetch('q'))};"]
          # Only some F4 devices have the R divider, and on those the struct carries the
          # field — so whether the line exists is the manifest's answer, not an #ifdef's.
          lines << "    oscillators.PLL.PLLR = #{Integer(pll['r'])};" if pll["r"]
          lines
        end
      end
    end
  end
end
