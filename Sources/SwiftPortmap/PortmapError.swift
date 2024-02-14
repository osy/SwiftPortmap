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
import dnssd

/// Errors for SwiftPortmap
public enum PortmapError: Error {
    case portInUse
    case noPortAvailable
    case cannotReservePort(Int32)
    case dnsServiceError(DNSServiceErrorType)
}

extension PortmapError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .portInUse:
            return NSLocalizedString("Port is already in use.", comment: "PortmapError")
        case .noPortAvailable:
            return NSLocalizedString("No avilable port is found.", comment: "PortmapError")
        case .cannotReservePort(_):
            return NSLocalizedString("Cannot reserve an unused port on this system.", comment: "PortmapError")
        case .dnsServiceError(_):
            return NSLocalizedString("Failed to create NAT mapping.", comment: "PortmapError")
        }
    }
}
