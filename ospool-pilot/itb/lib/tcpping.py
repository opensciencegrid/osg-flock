"""
usage: tcpping.py [-h] [-n NUM_PINGS] [-t TIMEOUT_SECS] [-w WAIT_SECS] hostname port

Returns a CSV of attempts, IPs, ports, and ping times in milliseconds.
Currently only works with hosts running IPv4.
Compatible with Python 2.7+

positional arguments:
  hostname         Hostname to ping
  port             TCP port to ping

optional arguments:
  -h, --help       show this help message and exit
  -n NUM_PINGS     Number of pings to send (default: 4)
  -t TIMEOUT_SECS  Timeout in seconds (default: 1)
  -w WAIT_SECS     Wait time between pings in seconds (default: 1)
"""

import sys
import socket
from argparse import ArgumentParser
from time import sleep
from timeit import default_timer as timer  # more accurate timer


# Make sure a large number doesn't cause problems in Python 2.7
# (Python 3 linters hate this one weird trick!)
if sys.version_info.major < 3:
    range = xrange


def print_err(msg):
    sys.stderr.write("{0}\n".format(msg))
    sys.stderr.flush()


def parse_args():
    parser = ArgumentParser(description="""
Returns a CSV of attempts, IPs, ports, and ping times in milliseconds.
Currently only works with hosts running IPv4.
Compatible with Python 2.7+
""")
    parser.add_argument("hostname", help="Hostname to ping")
    parser.add_argument("port", type=int, help="TCP port to ping")
    parser.add_argument("-n", dest="num_pings", metavar="NUM_PINGS", type=int, default=4,
        help="Number of pings to send (default: %(default)s)")
    parser.add_argument("-t", dest="timeout", metavar="TIMEOUT_SECS", type=float, default=1,
        help="Timeout in seconds (default: %(default)s)")
    parser.add_argument("-w", dest="wait", metavar="WAIT_SECS", type=float, default=1,
        help="Wait time between pings in seconds (default: %(default)s)")
    return parser.parse_args()


def get_hostname_ip(hostname):
    try:
        host_ip = socket.gethostbyname(hostname)
    except socket.gaierror:
        print_err("Could not find address for hostname {0}".format(hostname))
        sys.exit(1)
    return host_ip


def tcp_ping(target, port, timeout=1):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    timed_out = False

    timer_start = timer()
    try:
        sock.connect((target, port,))
        sock.shutdown(socket.SHUT_RD)
    except socket.timeout:
        timed_out = True
    finally:
        timer_stop = timer()
        sock.close()

    return (timer_stop - timer_start, timed_out)


def main():
    args = parse_args()
    ip = get_hostname_ip(args.hostname)
    print("Attempt,IP,Port,Ping_ms")
    for i in range(args.num_pings):
        ping_time, ping_timeout = tcp_ping(ip, args.port, timeout=args.timeout)
        if not ping_timeout:
            print("{0},{1},{2},{3:.3f}".format(i+1, ip, args.port, ping_time*1000))
        else:
            print_err("{0},{1},{2},Timed out after {3:.3f} ms".format(i+1, ip, args.port, ping_time*1000))
        sleep(args.wait)


if __name__ == "__main__":
    main()
