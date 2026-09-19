"""Offline acceptance checks; never open EC devices or change system services."""

import importlib.machinery
import importlib.util
import mmap
import tempfile
from contextlib import nullcontext
from pathlib import Path
from unittest.mock import patch

loader = importlib.machinery.SourceFileLoader(
    "yoga_fan", str(Path(__file__).with_name("yoga-fan"))
)
spec = importlib.util.spec_from_loader(loader.name, loader)
assert spec is not None
fan = importlib.util.module_from_spec(spec)
loader.exec_module(fan)


def check():
    for c, first, second in fan.DEFAULT_STEPS:
        assert fan.Curve(fan.DEFAULT_STEPS).targets(c, 0) == (
            first // 100,
            second // 100,
        )
    assert fan.Curve(fan.DEFAULT_STEPS).targets(94.9, 0) == (54, 88)
    assert fan.Curve(fan.DEFAULT_STEPS).targets(101, 0) == fan.MAX_TARGET
    curve = fan.Curve(fan.DEFAULT_STEPS)
    assert curve.targets(69.9, 0) == (0, 0)
    assert curve.targets(80, 1) == (51, 82)
    assert curve.targets(95, 2) == fan.MAX_TARGET
    assert curve.targets(94, 40) == fan.MAX_TARGET
    assert curve.targets(92, 41) == fan.MAX_TARGET
    assert curve.targets(91, 42) == fan.MAX_TARGET
    assert curve.targets(93, 60) == fan.MAX_TARGET  # Rewarming cancels the delay.
    assert curve.targets(80, 61) == fan.MAX_TARGET
    assert curve.targets(80, 81) == (51, 82)
    assert curve.targets(90, 82) == (54, 88)  # Upshifts have no delay.
    assert curve.targets(56, 83) == (54, 88)
    assert curve.targets(56, 103) == (0, 0)
    for temperature in (float("nan"), float("inf"), -1, 0, 111):
        try:
            curve.targets(temperature, 104)
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid temperature accepted")
    for steps in (
        [[100, 6000, 10000]],
        [[70, 4000, 6000], [94, 5600, 9400]],
        [[70, 4000, 6000], [90, 6000, 10000], [100, 6000, 10000]],
        [[60, 0, 5000], [100, 6000, 10000]],
        [[60, 5500, 9000], [80, 5100, 8200], [100, 6000, 10000]],
        [[60, 4001, 6000], [100, 6000, 10000]],
    ):
        try:
            fan.Curve(steps)
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid staircase accepted")

    with tempfile.TemporaryDirectory() as directory, mmap.mmap(-1, 4096) as ec:
        owned = Path(directory) / "owned"
        registers = dict(fan.EXPECTED_PWM)
        registers.update({0x2000: 0x55, 0x2001: 7, 0x2002: 2})
        writes = []

        def read(_fd, address):
            return registers[address]

        def output(_fd, port, value):
            assert port == 0x4F
            assert not (registers[0x180C] ^ value) & ~0x30
            writes.append(value)
            registers[0x180C] = value

        ec[0x400] = 0x10
        ec[0x5A0:0x5A2] = bytes((39, 70))
        with (
            patch.object(fan, "OWNED", owned),
            patch.object(fan, "read_register", read),
            patch.object(fan, "output", output),
        ):
            assert fan.cooling_floor(ec, (40, 60)) == (40, 70)
            assert fan.cooling_floor(ec, (0, 0)) == (0, 0)
            before = ec[:]
            fan.apply_targets(ec, 123, (40, 70))
            assert owned.exists() and registers[0x180C] == 0xD0
            assert ec[0x5FA:0x5FC] == bytes((40, 70))
            assert all(
                ec[i] == before[i] for i in range(4096) if i not in (0x5FA, 0x5FB)
            )
            fan.restore(ec, 123)
            assert not owned.exists() and ec[0x5FA:0x5FC] == bytes((0, 0))
            assert registers[0x180C] == 0xC0
            ec[0x5FA] = 49  # Another controller owns this; never clear it.
            fan.restore(ec, 123)
            assert ec[0x5FA] == 49
            try:
                fan.apply_targets(ec, 123, (60, 100))
            except RuntimeError:
                pass
            else:
                raise AssertionError("Existing owner was overwritten")
            assert not owned.exists()
            ec[0x5FA] = 0
            registers[0x1841] = 255
            try:
                fan.apply_targets(ec, 123, (60, 100))
            except RuntimeError:
                pass
            else:
                raise AssertionError("Changed clock configuration accepted")
            assert not owned.exists() and writes == [0xD0, 0xC0]
            registers[0x1841] = 159
            fan.apply_targets(ec, 123, (60, 100))
            registers[0x180C] = 0xDF
            fan.restore(ec, 123)
            assert registers[0x180C] == 0xCF  # Restore only our channel bits.
            owned.write_text("pending rollback")
            ec[0x5FA:0x5FC] = bytes((60, 100))
            with patch.object(fan, "clock", side_effect=OSError("port unavailable")):
                try:
                    fan.restore(ec, 123)
                except OSError:
                    pass
                else:
                    raise AssertionError("Failed rollback was hidden")
            assert owned.exists() and not any(ec[0x5FA:0x5FC])
            fan.restore(ec, 123)
            assert not owned.exists()
            owned.write_text("pending rollback")
            ec[0x5FA:0x5FC] = bytes((60, 100))
            with (
                patch.dict(fan.os.environ, {"SERVICE_RESULT": "watchdog"}),
                patch.object(fan, "atomic", side_effect=OSError("No space left")),
                patch.object(fan, "hardware", return_value=nullcontext((ec, 123))),
            ):
                try:
                    fan.reset()
                except OSError:
                    pass
                else:
                    raise AssertionError("Failed fault recording was hidden")
            assert not owned.exists() and not any(ec[0x5FA:0x5FC])

    with (
        patch.object(fan.os, "pwrite", return_value=1) as write,
        patch.object(fan.os, "pread", return_value=bytes((159,))),
    ):
        assert fan.read_register(123, 0x180C) == 159
        assert [(c.args[2], c.args[1][0]) for c in write.call_args_list] == [
            (0x4E, 0x2E),
            (0x4F, 0x11),
            (0x4E, 0x2F),
            (0x4F, 0x18),
            (0x4E, 0x2E),
            (0x4F, 0x10),
            (0x4E, 0x2F),
            (0x4F, 0x0C),
            (0x4E, 0x2E),
            (0x4F, 0x12),
            (0x4E, 0x2F),
        ]
        write.reset_mock()
        try:
            fan.read_register(123, 0x1234)
        except ValueError:
            pass
        else:
            raise AssertionError("Unknown register accepted")
        assert not write.called
    print("Fan staircase, hysteresis, cooling floor, ownership and rollback: PASS")


if __name__ == "__main__":
    check()
