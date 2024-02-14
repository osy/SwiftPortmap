//
// Copyright © 2024 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Darwin
import dnssd
import os

/// Abstract class representing a TCP or UDP port which can be NAT mapped.
public class Port {
    public typealias MappingChangedHandler = (Port) -> Void

    /// TCP port
    public class TCP: Port {
        /// Request a random unused port from the system
        /// - Parameter at: Optional port number to start allocating from. 
        public init(unusedPortStartingAt port: UInt16 = 0) throws {
            super.init(port: try Port.reserveAvailablePort(startingAt: port), isTcp: true)
        }
        
        /// Create a TCP port from a port number
        /// - Parameter internalPort: Port number internal to this host
        public init(internalPort: UInt16) {
            super.init(port: internalPort, isTcp: true)
        }
    }
    
    /// UDP port
    public class UDP: Port {
        /// Request a random unused port from the system
        /// - Parameter at: Optional port number to start allocating from.
        public init(unusedPortStartingAt port: UInt16 = 0) throws {
            super.init(port: try Port.reserveAvailablePort(startingAt: port), isTcp: false)
        }

        /// Create a UDP port from a port number
        /// - Parameter internalPort: Port number internal to this host
        public init(internalPort: UInt16) {
            super.init(port: internalPort, isTcp: false)
        }
    }

    static private let portmapQueue = DispatchQueue(label: "SwiftPortmap Queue")

    private let isTcp: Bool
    fileprivate var _externalPort: UInt16?
    fileprivate var _externalAddress: UInt32?
    
    /// Port number internal to the host
    fileprivate(set) public var internalPort: UInt16
    
    /// NAT mapped port visible external to the host
    ///
    /// If `createNATmapping(interfaceIndex:requestedExternalPort:ttl:)` has not been called,
    /// it will be called with default arguments to obtain the NAT mapping.
    public var externalPort: UInt16 {
        get async throws {
            if let _externalPort = _externalPort {
                return _externalPort
            } else {
                try await createNATmapping()
                return _externalPort!
            }
        }
    }

    /// External IPv4 address (raw)
    ///
    /// If `createNATmapping(interfaceIndex:requestedExternalPort:ttl:)` has not been called,
    /// it will be called with default arguments to obtain the NAT mapping.
    public var externalAddress: UInt32 {
        get async throws {
            if let _externalAddress = _externalAddress {
                return _externalAddress
            } else {
                try await createNATmapping()
                return _externalAddress!
            }
        }
    }

    /// External IPv4 address (as a dot separated string)
    ///
    /// If `createNATmapping(interfaceIndex:requestedExternalPort:ttl:)` has not been called,
    /// it will be called with default arguments to obtain the NAT mapping.
    public var externalIpv4Address: String {
        get async throws {
            let address = in_addr(s_addr: try await externalAddress)
            let cString = inet_ntoa(address)
            let ipAddressString = String(cString: cString!)
            return ipAddressString
        }
    }

    /// Handler to be notified if the NAT mapping changes.
    public var mappingChangedHandler: MappingChangedHandler?

    private var sdRef: DNSServiceRef?
    fileprivate var createNATmappingContinuation: CheckedContinuation<Void, any Error>?

    private init(port: UInt16, isTcp: Bool) {
        self.internalPort = port
        self.isTcp = isTcp
    }

    deinit {
        // we must ensure that the callback (executed in the queue) is not running
        Self.portmapQueue.sync {
            if let sdRef = self.sdRef {
                DNSServiceRefDeallocate(sdRef)
            }
        }
    }

    /// Reserve an ephemeral port from the system
    /// 
    /// First we `bind` to port 0 in order to allocate an ephemeral port.
    /// Next, we `connect` to that port to establish a connection.
    /// Finally, we close the port and put it into the `TIME_WAIT` state.
    /// 
    /// This allows another process to `bind` the port with `SO_REUSEADDR` specified.
    /// However, for the next ~120 seconds, the system will not re-use this port.
    /// - Parameter port: Port number to attempt to reserve, or 0 to get any port.
    /// - Returns: A port number that is valid for ~120 seconds.
    /// - Throws: Any system error when trying to check the port
    static public func reservePort(_ port: UInt16 = 0) throws -> UInt16 {
        let serverSock = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSock >= 0 else {
            throw PortmapError.cannotReservePort(errno)
        }
        defer {
            close(serverSock)
        }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_ANY
        addr.sin_port = port.bigEndian

        var len = socklen_t(MemoryLayout<sockaddr_in>.stride)
        try withUnsafeMutablePointer(to: &addr) {
            try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                guard bind(serverSock, $0, len) == 0 else {
                    if errno == EADDRINUSE {
                        throw PortmapError.portInUse
                    } else {
                        throw PortmapError.cannotReservePort(errno)
                    }
                }
                guard getsockname(serverSock, $0, &len) == 0 else {
                    throw PortmapError.cannotReservePort(errno)
                }
            }
        }

        guard listen(serverSock, 1) == 0 else {
            throw PortmapError.cannotReservePort(errno)
        }

        let clientSock = socket(AF_INET, SOCK_STREAM, 0)
        guard clientSock >= 0 else {
            throw PortmapError.cannotReservePort(errno)
        }
        defer {
            close(clientSock)
        }
        let res3 = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(clientSock, $0, len)
            }
        }
        guard res3 == 0 else {
            throw PortmapError.cannotReservePort(errno)
        }

        let acceptSock = accept(serverSock, nil, nil)
        guard acceptSock >= 0 else {
            throw PortmapError.cannotReservePort(errno)
        }
        defer {
            close(acceptSock)
        }
        return addr.sin_port.bigEndian
    }
    
    /// Check if a port is available and reserve it
    /// - Parameter port: Port number to check
    /// - Returns: `port` if it is available otherwise nil
    /// - Throws: Any system error when trying to check the port
    static public func reservePortIfAvailable(port: UInt16) throws -> UInt16? {
        do {
            return try reservePort(port)
        } catch {
            if case .portInUse = error as? PortmapError {
                return nil
            } else {
                throw error
            }
        }
    }
    
    /// Reserve an available port starting from a specified number.
    /// - Parameter port: Starting port number, all ports will be checked until an available one is found.
    /// - Returns: First available port.
    /// - Throws: Any system error when trying to check the port
    static public func reserveAvailablePort(startingAt port: UInt16?) throws -> UInt16 {
        var requested = port ?? 0
        var allocated: UInt16? = nil
        while allocated == nil {
            var overflow = false
            allocated = try Port.reservePortIfAvailable(port: requested)
            (requested, overflow) = requested.addingReportingOverflow(1)
            if overflow {
                throw PortmapError.noPortAvailable
            }
        }
        return allocated!
    }
    
    /// Map this port externally using UPnP/NAT-PMP
    ///
    /// The mapping will be valid for the life cycle of this `Port` object.
    /// - Parameters:
    ///   - interfaceIndex: The interface on which to create port mappings in a NAT gateway. Passing 0 causes the port mapping request to be sent on the primary interface.
    ///   - requestedExternalPort: The requested external port in network byte order in the NAT gateway that you would like to map to the internal port. Pass 0 if you don't care which external port is chosen for you. Pass nil to request the same port as the internal port.
    ///   - ttl: The requested renewal period of the NAT port mapping, in seconds. If the client machine crashes, suffers a power failure, is disconnected from the network, or suffers some other unfortunate demise which causes it to vanish unexpectedly without explicitly removing its NAT port mappings, then the NAT gateway will garbage-collect old stale NAT port mappings when their lifetime expires. Requesting a short TTL causes such orphaned mappings to be garbage-collected more promptly, but consumes system resources and network bandwidth with frequent renewal packets to keep the mapping from expiring. Requesting a long TTL is more efficient on the network, but in the event of the client vanishing, stale NAT port mappings will not be garbage-collected as quickly. Most clients should pass 0 to use a system-wide default value.
    /// - Throws: Any DNS-SD error
    public func createNATmapping(interfaceIndex: UInt32 = 0, requestedExternalPort: UInt16? = nil, ttl: UInt32 = 0) async throws {
        try await withCheckedThrowingContinuation { continuation in
            Self.portmapQueue.async { [self] in
                createNATmappingContinuation = continuation
                let context = Unmanaged.passUnretained(self).toOpaque()
                let err = DNSServiceNATPortMappingCreate(&sdRef,
                                                         0,
                                                         interfaceIndex,
                                                         DNSServiceProtocol(isTcp ? kDNSServiceProtocol_TCP : kDNSServiceProtocol_UDP),
                                                         internalPort,
                                                         requestedExternalPort ?? internalPort,
                                                         ttl,
                                                         natPortCallback,
                                                         context)
                if err != kDNSServiceErr_NoError {
                    createNATmappingContinuation = nil
                    continuation.resume(throwing: PortmapError.dnsServiceError(err))
                } else {
                    DNSServiceSetDispatchQueue(sdRef!, Self.portmapQueue)
                }
            }
        }
    }
}

/// This function is overly complicated because the API allows this C callback to be made multiple times in the lifecycle of `sdRef`. We only care about the first time it is called,
private func natPortCallback(sdRef: DNSServiceRef?, flags: DNSServiceFlags, interfaceIndex: UInt32, errorCode: DNSServiceErrorType, externalAddress: UInt32, `protocol`: DNSServiceProtocol, internalPort: UInt16, externalPort: UInt16, ttl: UInt32, context: UnsafeMutableRawPointer?) -> Void {
    let _self = Unmanaged<Port>.fromOpaque(context!).takeUnretainedValue()
    _self._externalAddress = externalAddress
    _self._externalPort = externalPort
    _self.internalPort = internalPort
    defer {
        _self.mappingChangedHandler?(_self)
    }
    guard let continuation = _self.createNATmappingContinuation else {
        return
    }
    _self.createNATmappingContinuation = nil
    if errorCode != kDNSServiceErr_NoError {
        continuation.resume(throwing: PortmapError.dnsServiceError(errorCode))
    } else {
        continuation.resume()
    }
}
