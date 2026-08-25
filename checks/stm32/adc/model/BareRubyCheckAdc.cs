using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals;
using Antmicro.Renode.Peripherals.Bus;

namespace Antmicro.Renode.Peripherals.Analog
{
    // The converter the STM32 ADC checks read from. Renode 1.16.1 models no F4 ADC —
    // its STM32 ADC models are all the F0/L0/G0 register layout — so this file is the
    // F4's, compiled at run time (include @...cs in the check's .resc) exactly as the
    // I2C check sensor is. It spans ADC1 at 0x40012000 through the common registers at
    // 0x40012300, and implements the minimum HAL's blocking conversion touches: ADON
    // and SWSTART in CR2, the first rank of SQR3, the sample times, EOC in SR, and DR.
    //
    // The contract, as testcase.md records it:
    //   - a check gives each channel its voltage in millivolts against the 3.3 V full
    //     scale: SetChannelVoltage from the monitor, before the run or between two
    //     slices of it.
    //   - a conversion answers value * 4095 / 3300 in integer arithmetic, clamped to
    //     the full scale — so 0 mV is 0x000, 3300 mV is 0xFFF, and 1650 mV lands on
    //     0x7FF, the expected files' side of the halfway question.
    //   - SR is write-zero-to-clear as the reference manual says, and reading DR
    //     clears EOC, which is what lets HAL poll and read without a hidden order.
    public class BareRubyCheckAdc : IDoubleWordPeripheral, IKnownSize
    {
        public BareRubyCheckAdc()
        {
            millivolts = new uint[ChannelCount];
            Reset();
        }

        public void Reset()
        {
            sr = 0;
            cr1 = 0;
            cr2 = 0;
            smpr1 = 0;
            smpr2 = 0;
            sqr1 = 0;
            sqr2 = 0;
            sqr3 = 0;
            dr = 0;
            ccr = 0;
        }

        // What a check gives a channel, in millivolts against the 3.3 V full scale.
        public void SetChannelVoltage(int channel, uint value)
        {
            millivolts[channel] = value;
            this.Log(LogLevel.Info, "check adc holds IN{0} at {1} mV", channel, value);
        }

        public uint ReadDoubleWord(long offset)
        {
            switch(offset)
            {
            case 0x00: return sr;
            case 0x04: return cr1;
            case 0x08: return cr2;
            case 0x0C: return smpr1;
            case 0x10: return smpr2;
            case 0x2C: return sqr1;
            case 0x30: return sqr2;
            case 0x34: return sqr3;
            case 0x4C:
                sr &= ~EocBit;
                return dr;
            case 0x304: return ccr;
            default: return 0;
            }
        }

        public void WriteDoubleWord(long offset, uint value)
        {
            switch(offset)
            {
            case 0x00: sr &= value; break;
            case 0x04: cr1 = value; break;
            case 0x08:
                cr2 = value & ~SwStartBit;
                if((value & SwStartBit) != 0 && (value & AdonBit) != 0)
                {
                    Convert();
                }
                break;
            case 0x0C: smpr1 = value; break;
            case 0x10: smpr2 = value; break;
            case 0x2C: sqr1 = value; break;
            case 0x30: sqr2 = value; break;
            case 0x34: sqr3 = value; break;
            case 0x304: ccr = value; break;
            }
        }

        public long Size { get { return 0x400; } }

        private void Convert()
        {
            var channel = (int)(sqr3 & 0x1F);
            var value = channel < ChannelCount ? millivolts[channel] : 0u;
            if(value > FullScale)
            {
                value = FullScale;
            }
            dr = value * 4095u / FullScale;
            sr |= EocBit | StrtBit;
            this.Log(LogLevel.Info, "check adc converts IN{0} at {1} mV to 0x{2:X3}",
                     channel, value, dr);
        }

        private uint sr;
        private uint cr1;
        private uint cr2;
        private uint smpr1;
        private uint smpr2;
        private uint sqr1;
        private uint sqr2;
        private uint sqr3;
        private uint dr;
        private uint ccr;
        private readonly uint[] millivolts;

        private const int ChannelCount = 16;
        private const uint FullScale = 3300;
        private const uint EocBit = 1u << 1;
        private const uint StrtBit = 1u << 4;
        private const uint AdonBit = 1u << 0;
        private const uint SwStartBit = 1u << 30;
    }
}
