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

import Foundation
import ArgumentParser
import SwiftPortmap

@main
struct Portmap: AsyncParsableCommand {
    @Flag(help: "If specified, UDP will be used. Otherwise, TCP will be used.")
    var udp: Bool = false

    @Argument(help: "The port number on the local machine which is listening for packets. If you pass 0, a random unused port will be selected.")
    var internalPort: UInt16

    @Argument(help: "The requested external port in network byte order in the NAT gateway that you would like to map to the internal port.")
    var externalPort: UInt16?

    @Option(help: "The requested renewal period of the NAT port mapping, in seconds.")
    var ttl: UInt32?

    @Option(help: "The interface on which to create port mappings in a NAT gateway.")
    var interfaceIndex: UInt32?
}

extension Portmap {
    func run() async throws {
        let port = udp ? Port.UDP(internalPort: internalPort) : Port.TCP(internalPort: internalPort)
        port.mappingChangedHandler = { port in
            Task {
                print("NAT mapping updated...")
                print("Internal : \(port.internalPort)")
                print("External : \(try await port.externalPort)")
                print("IPv4     : \(try await port.externalIpv4Address)")
            }
        }
        try await port.createNATmapping(interfaceIndex: interfaceIndex ?? 0, requestedExternalPort: externalPort, ttl: ttl ?? 0)
        while true {
            try await Task.sleep(nanoseconds: 1000000000)
        }
    }
}
