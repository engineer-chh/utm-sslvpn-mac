import struct
import unittest
from protocol import *

class Fragmented:
    def __init__(self, data): self.data = data
    def recv(self, size):
        part, self.data = self.data[:min(size, 1)], self.data[min(size, 1):]
        return part

class Tests(unittest.TestCase):
    def test_auth_golden(self):
        self.assertEqual(auth_frame(b'a'*32), bytes.fromhex('01010020') + b'a'*32)
    def test_fragmented_stream(self):
        self.assertEqual(read_frame(Fragmented(b'\x02\x01\x00\x03abc')), (0x201,b'abc'))
    def test_truncated(self):
        with self.assertRaises(EOFError): read_frame(Fragmented(b'\0\0\0\x03x'))
    def test_oversized(self):
        with self.assertRaises(ValueError): read_frame(Fragmented(b'\0\0\xff\xff'))
    def test_link(self):
        self.assertEqual(parse_link('utmssl://example.test:1234/conn?abc&5'),('example.test',1234,b'abc'))
    def test_no_implicit_port(self):
        with self.assertRaises(ValueError): parse_link('utmssl://example.test/conn?abc')
    def test_config(self):
        self.assertEqual(config_summary(bytes(20)+struct.pack('!I',1)+bytes(8))['route_count'],1)
    def test_bad_config(self):
        with self.assertRaises(ValueError): config_summary(bytes(20)+struct.pack('!I',100000))

if __name__=='__main__': unittest.main()
