"""Log the board UART (115200) to build/uart_listen.log for a while."""
import sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from install_uart import SerialPort
seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 600
out = Path(__file__).resolve().parents[1] / 'build' / 'uart_listen.log'
port = SerialPort('COM15', 115200)
port.timeout(200)
end = time.monotonic() + seconds
with out.open('ab') as f:
    f.write(f'\n--- listen start {time.strftime("%H:%M:%S")}\n'.encode())
    while time.monotonic() < end:
        data = port.read(256)
        if data:
            f.write(f'[{time.strftime("%H:%M:%S")}] '.encode() + data)
            f.flush()
port.close()
