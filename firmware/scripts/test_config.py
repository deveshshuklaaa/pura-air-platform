"""Host-only compile probes: disabled defaults, reported map and ownership conflicts.

Never creates local_config.h and never invokes Arduino/serial/network APIs.
"""
import argparse
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--compiler', default='g++')
args = parser.parse_args()
compiler = shutil.which(args.compiler)
if not compiler:
    raise SystemExit('Host C++ compiler required')
if (root / 'include/local_config.h').exists():
    raise SystemExit('Refuse config probes with a private local_config.h present')
out = root / '.pio/host-config'
out.mkdir(parents=True, exist_ok=True)
ownership = '''
static_assert(board::pmsUart == 2 && board::esp2ReservedUart == 1 && board::consoleUart == 0);
static_assert(board::pmsBaud == 9600 && board::esp2ReservedBaud == 115200);
static_assert(!board::esp2Implemented);
'''
defaults = '''
static_assert(!board::sensorIo && !board::mqEnabled);
static_assert(board::reportedWroomDa);
static_assert(board::pmsRx == -1 && board::pmsTx == -1 && board::esp2Rx == -1 && board::esp2Tx == -1);
static_assert(board::sda == -1 && board::scl == -1 && board::mqAdc == -1);
static_assert(sizeof(PURA_WIFI_SSID) == 1 && sizeof(PURA_WIFI_PASSWORD) == 1);
static_assert(sizeof(PURA_DEVICE_ID) == 1 && sizeof(PURA_INGEST_KEY) == 1 && sizeof(PURA_API_HOST) == 1);
static_assert(PURA_API_TLS && !PURA_ALLOW_PRIVATE_HTTP && sizeof(PURA_TLS_ROOT_CA) == 1);
'''
example = '''
static_assert(!board::sensorIo && !board::mqEnabled && board::reportedWroomDa);
static_assert(board::pmsRx == 25 && board::pmsTx == 26);
static_assert(board::sda == 21 && board::scl == 22 && board::mqAdc == 34);
static_assert(board::esp2Rx == 16 && board::esp2Tx == 17);
'''
# Negative probes explicitly suppress the DA guard to isolate collision errors.
# None is an approved enabled configuration or a replacement wiring proposal.
base = dict(PURA_SENSOR_IO_ENABLED=1, PURA_REPORTED_WROOM_DA=0,
            PURA_PMS_RX=25, PURA_PMS_TX=26, PURA_I2C_SDA=21, PURA_I2C_SCL=22,
            PURA_ESP2_RX=16, PURA_ESP2_TX=17)
cases = [
    ('disabled_defaults', {}, '', defaults, None),
    ('reported_example_disabled', {}, '#include "local_config.example.h"\n', example, None),
    ('gpio25_without_model_flag_blocked', {key: value for key, value in base.items() if key != 'PURA_REPORTED_WROOM_DA'}, '', '', 'WROOM-DA GPIO2/25'),
    ('reported_example_enable_blocked', {}, '#include "local_config.example.h"\n#undef PURA_SENSOR_IO_ENABLED\n#define PURA_SENSOR_IO_ENABLED 1\n', '', 'WROOM-DA GPIO2/25'),
    ('legacy_rx16_collides_with_esp2', {**base, 'PURA_PMS_RX': 16}, '', '', 'must not overlap'),
    ('pms_tx_collides_with_esp2', {**base, 'PURA_PMS_TX': 17}, '', '', 'must not overlap'),
    ('scd_collides_with_reserved_link', {**base, 'PURA_I2C_SDA': 16}, '', '', 'must not overlap'),
    ('mq_collides_with_uart_tx', {**base, 'PURA_MQ135_ENABLED': 1, 'PURA_MQ135_ADC': 34, 'PURA_PMS_TX': 34}, '', '', 'must not overlap'),
    ('da_rf_gpio2_blocked', {**base, 'PURA_REPORTED_WROOM_DA': 1, 'PURA_PMS_RX': 2}, '', '', 'WROOM-DA GPIO2/25'),
    ('missing_sensor_pins_blocked', {'PURA_SENSOR_IO_ENABLED': 1}, '', '', 'Review/configure sensor pins'),
    ('mq_adc2_blocked', {**base, 'PURA_MQ135_ENABLED': 1, 'PURA_MQ135_ADC': 25}, '', '', 'MQ requires reviewed ADC1'),
]
for name, defines, prefix, assertions, expected_error in cases:
    source = out / (name + '.cpp')
    source.write_text(prefix + '#include "board_config.h"\n' + ownership + assertions,
                      encoding='utf-8')
    result = subprocess.run([compiler, '-std=c++17', '-Wall', '-Wextra', '-Werror',
                             '-fsyntax-only', '-I' + str(root / 'include'),
                             *['-D' + key + '=' + str(value) for key, value in defines.items()],
                             str(source)], capture_output=True, text=True)
    if expected_error:
        if result.returncode == 0 or expected_error not in result.stderr:
            raise SystemExit('FAIL expected guard: ' + name + '\n' + result.stderr)
    elif result.returncode:
        raise SystemExit('FAIL compile: ' + name + '\n' + result.stderr)
    print('PASS config ' + name)
print('CONFIG_TESTS_PASS count=' + str(len(cases)))
