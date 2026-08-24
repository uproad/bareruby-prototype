using System;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals;
using Antmicro.Renode.Peripherals.I2C;

namespace Antmicro.Renode.Peripherals.I2C
{
    // The device the STM32 I2C checks talk to. Renode compiles this file at run time
    // (include @...cs in the check's .resc), so changing the contract here needs no
    // build step — but the expected answers in expected/ are written against it.
    //
    // The contract, as testcase.md records it:
    //   - byte one of every write selects a register; further bytes store from there,
    //     advancing one register per byte through the sixteen-byte file.
    //   - the file starts as the known pattern 0xF0..0xFF, so reads have reviewed
    //     answers before any write.
    //   - a read request answers everything from the selected register to the end of
    //     the file, ignoring the requested count. That is not a nicety: the pinned
    //     Renode 1.16.1 STM32F4_I2C controller asks the slave with count=1 and lacks
    //     the POS bit, so a slave answering only what was asked starves HAL's
    //     multi-byte receive (renode#114). Handing back the whole tail is what makes
    //     1..N byte reads arrive as real data.
    //   - two special registers sit outside the file. Writes selecting SEQUENCE are
    //     checked byte-for-byte against a rolling 0x00..0xFF counter, so a program can
    //     push all 256 byte values through the write path and the sensor keeps score.
    //     A read selecting RESULT answers that score as "MMM/CCC" — mismatches and
    //     bytes received, three ASCII digits each, fixed width so the reader can ask
    //     for exactly seven bytes. The count is what catches a missing chunk: a sweep
    //     whose tail never arrived scores zero mismatches but not 256 received.
    public class BareRubyCheckSensor : II2CPeripheral
    {
        public BareRubyCheckSensor()
        {
            Reset();
        }

        public void Reset()
        {
            registers = new byte[FileSize];
            for(var i = 0; i < FileSize; i++)
            {
                registers[i] = (byte)(0xF0 + i);
            }
            pointer = 0;
            expected = 0;
            mismatches = 0;
            received = 0;
        }

        public void Write(byte[] data)
        {
            this.Log(LogLevel.Info, "check sensor received {0}", BitConverter.ToString(data));
            if(data.Length == 0)
            {
                return;
            }
            pointer = data[0];
            for(var i = 1; i < data.Length; i++)
            {
                if(pointer == SequenceRegister)
                {
                    if(data[i] != expected)
                    {
                        mismatches++;
                    }
                    expected = (byte)(expected + 1);
                    received++;
                }
                else
                {
                    registers[pointer % FileSize] = data[i];
                    pointer = (byte)((pointer + 1) % FileSize);
                }
            }
        }

        public byte[] Read(int count = 1)
        {
            if(pointer == ResultRegister)
            {
                var score = Math.Min(mismatches, 999).ToString("D3")
                    + "/" + Math.Min(received, 999).ToString("D3");
                this.Log(LogLevel.Info, "check sensor answers score {0}", score);
                return System.Text.Encoding.ASCII.GetBytes(score);
            }
            var from = pointer % FileSize;
            var reply = new byte[FileSize - from];
            Array.Copy(registers, from, reply, 0, reply.Length);
            this.Log(LogLevel.Info, "check sensor answers {0}", BitConverter.ToString(reply));
            return reply;
        }

        public void FinishTransmission()
        {
        }

        private byte[] registers;
        private byte pointer;
        private byte expected;
        private int mismatches;
        private int received;

        private const int FileSize = 16;
        private const byte SequenceRegister = 0x40;
        private const byte ResultRegister = 0x41;
    }
}
