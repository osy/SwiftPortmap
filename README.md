SwiftPortmap
============
A Swift library for reserving ports and creating NAT mappings. A system port can be reserved by calling `bind` on port 0 which returns a binding on a random free port. When the TCP socket is closed, the socket is placed in a `TIME_WAIT` state meaning that no other process can use the port unless they set `SO_REUSEADDR` (which is typically the case for server applications).

Once a port is reserved internal to the host, this library also allows you to make a NAT mapping to export the port externally. This uses UPnP/NAT-PMP through the DNS-SD system framework. The mapping is retained throughout the lifecycle of the `Port` object and an optional callback can be set to be notified of any NAT mapping changes.

A simple CLI tool is provided both as an example and also as a simple utility to perform NAT mappings.

## Usage
Reserve any port:
```swift
let port = Port.TCP()
print(port.internalPort)
```

Map to an external port:
```swift
let port = Port.TCP(internalPort: 2345)
let externalPort = try await port.externalPort
let ip = try await port.externalIpv4Address
print("mapped \(port) -> \(externalPort) for \(ip)")
```
