#!/usr/bin/env python3
"""
Basic RCON (Remote Console) client script.
Usage: python rcon.py <host:port> <password> <command>
"""

import socket
import struct
import sys


class RCONClient:
    """Simple RCON client for Source/Valve game servers."""

    SERVERDATA_AUTH = 3
    SERVERDATA_AUTH_RESPONSE = 2
    SERVERDATA_EXECCOMMAND = 2
    SERVERDATA_RESPONSE_VALUE = 0

    def __init__(self, host: str, port: int, password: str):
        self.host = host
        self.port = port
        self.password = password
        self.socket: socket.socket | None = None
        self.request_id = 0

    def _get_socket(self) -> socket.socket:
        """Get the socket, raising an error if not connected."""
        if self.socket is None:
            raise ConnectionError("Not connected to server")
        return self.socket

    def _create_packet(self, packet_type: int, body: str) -> bytes:
        """Create an RCON packet."""
        self.request_id += 1
        body_encoded = body.encode('utf-8') + b'\x00\x00'
        size = 4 + 4 + len(body_encoded)  # id + type + body
        packet = struct.pack('<iii', size, self.request_id, packet_type) + body_encoded
        return packet

    def _read_packet(self) -> tuple[int, int, str]:
        """Read and parse an RCON response packet."""
        sock = self._get_socket()

        size_data = sock.recv(4)
        if len(size_data) < 4:
            raise ConnectionError("Failed to receive packet size")

        size = struct.unpack('<i', size_data)[0]
        data = b''
        while len(data) < size:
            chunk = sock.recv(size - len(data))
            if not chunk:
                raise ConnectionError("Connection closed while reading packet")
            data += chunk

        request_id, packet_type = struct.unpack('<ii', data[:8])
        body = data[8:-2].decode('utf-8')  # Strip null terminators
        return request_id, packet_type, body

    def connect(self) -> bool:
        """Connect and authenticate with the RCON server."""
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.settimeout(10)

        try:
            self.socket.connect((self.host, self.port))
        except socket.error as e:
            print(f"Connection failed: {e}")
            return False

        auth_packet = self._create_packet(self.SERVERDATA_AUTH, self.password)
        self.socket.send(auth_packet)

        request_id, packet_type, _ = self._read_packet()

        if request_id == -1:
            print("Authentication failed: Invalid password")
            return False

        return True

    def execute(self, command: str) -> str:
        """Execute an RCON command and return the response."""
        sock = self._get_socket()

        packet = self._create_packet(self.SERVERDATA_EXECCOMMAND, command)
        sock.send(packet)

        _, _, response = self._read_packet()
        return response

    def disconnect(self) -> None:
        """Close the connection."""
        if self.socket is not None:
            self.socket.close()
            self.socket = None


def main() -> None:
    if len(sys.argv) < 4:
        print("Usage: python rcon.py <host:port> <password> <command>")
        print("Example: python rcon.py 127.0.0.1:27015 mypassword status")
        sys.exit(1)

    host_port = sys.argv[1]
    if ':' in host_port:
        host, port_str = host_port.rsplit(':', 1)
        port = int(port_str)
    else:
        host = host_port
        port = 27015

    password = sys.argv[2]
    command = ' '.join(sys.argv[3:])

    client = RCONClient(host, port, password)

    try:
        if not client.connect():
            sys.exit(1)

        response = client.execute(command)
        print(response)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
    finally:
        client.disconnect()


if __name__ == "__main__":
    main()
