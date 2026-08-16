#!/usr/bin/env python3
"""Expose a MeshCore USB-companion node's serial port over TCP.

Lets the iPad *simulator* (which has no USB) talk to a real radio plugged into
the Mac, via the app's TCP transport. Bytes are passed through untouched — the
companion frames ('<' len payload / '>' len payload) ride the socket as-is,
exactly like a MeshCore TCP companion (WiFi) node.

    python3 tools/serial-bridge.py /dev/cu.usbmodem8401 --port 5000

Requires pyserial (`pip install pyserial`). One client at a time; a new client
replaces the old one.
"""
import argparse
import selectors
import socket
import sys

try:
    import serial  # pyserial
except ImportError:
    sys.exit("pyserial is required: pip install pyserial")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("device", help="serial device, e.g. /dev/cu.usbmodem8401")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=5000)
    ap.add_argument("-v", "--verbose", action="store_true", help="hex-dump traffic")
    args = ap.parse_args()

    ser = serial.Serial(args.device, args.baud, timeout=0)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((args.host, args.port))
    srv.listen(1)
    srv.setblocking(False)
    print(f"bridge: {args.device} @ {args.baud} <-> tcp://{args.host}:{args.port}", flush=True)

    sel = selectors.DefaultSelector()
    sel.register(srv, selectors.EVENT_READ, "accept")
    sel.register(ser, selectors.EVENT_READ, "serial")
    client = None

    def drop_client():
        nonlocal client
        if client is not None:
            try:
                sel.unregister(client)
            except Exception:
                pass
            client.close()
            client = None
            print("bridge: client disconnected", flush=True)

    while True:
        for key, _ in sel.select():
            if key.data == "accept":
                conn, addr = srv.accept()
                drop_client()
                conn.setblocking(False)
                client = conn
                sel.register(client, selectors.EVENT_READ, "client")
                ser.reset_input_buffer()
                print(f"bridge: client connected from {addr[0]}:{addr[1]}", flush=True)
            elif key.data == "serial":
                data = ser.read(4096)
                if data and client is not None:
                    if args.verbose:
                        print(f"  <- {data.hex()}", flush=True)
                    try:
                        client.sendall(data)
                    except OSError:
                        drop_client()
            elif key.data == "client":
                try:
                    data = client.recv(4096)
                except OSError:
                    data = b""
                if not data:
                    drop_client()
                    continue
                if args.verbose:
                    print(f"  -> {data.hex()}", flush=True)
                ser.write(data)


if __name__ == "__main__":
    main()
