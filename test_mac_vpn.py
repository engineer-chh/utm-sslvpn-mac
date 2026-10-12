import unittest, struct, socket
from mac_vpn import parse_config, check_ipv4
from protocol import config_summary

def config(routes, padded=True):
    b=b''.join(socket.inet_aton(a) for a in ['10.20.30.2','255.255.255.0','10.20.30.1','0.0.0.0','0.0.0.0'])
    b+=struct.pack('!I',len(routes))
    for net,mask in routes:b+=socket.inet_aton(net)+socket.inet_aton(mask)
    return b.ljust(536,b'\0') if padded else b

class Tests(unittest.TestCase):
    def test_fixed_size_config(self):
        b=config([('192.168.0.0','255.255.255.0')])
        self.assertEqual(config_summary(b)['route_count'],1)
        self.assertEqual(str(parse_config(b)[3][0]),'192.168.0.0/24')
    def test_reject_default_route(self):
        with self.assertRaises(ValueError):parse_config(config([('0.0.0.0','0.0.0.0')]))
    def test_reject_invalid_mask(self):
        with self.assertRaises(ValueError):parse_config(config([('10.0.0.0','255.0.255.0')]))
    def test_reject_truncated_config(self):
        with self.assertRaises(ValueError):config_summary(config([('10.0.0.0','255.0.0.0')],False)[:-1])
    def test_ipv4_length(self):
        packet=bytes.fromhex('4500001400000000400600000a0000010a000002')
        self.assertTrue(check_ipv4(packet))
        self.assertFalse(check_ipv4(packet+b'x'))
        self.assertFalse(check_ipv4(bytes.fromhex('44000014')+packet[4:]))

if __name__=='__main__':unittest.main()
