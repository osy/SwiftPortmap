import XCTest
import Darwin
@testable import SwiftPortmap

final class SwiftPortmapTests: XCTestCase {
    static func checkConnect(port: UInt16) -> Int32? {
        let serverSock = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSock >= 0 else {
            return nil
        }
        var enable = 1
        let enableLen = socklen_t(MemoryLayout<Int>.stride)
        let success = withUnsafeMutablePointer(to: &enable) {
            $0.withMemoryRebound(to: Int.self, capacity: 1) {
                if setsockopt(serverSock, SOL_SOCKET, SO_REUSEADDR, $0, enableLen) == 0 {
                    return true
                } else {
                    return false
                }
            }
        }
        guard success else {
            return nil
        }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_ANY
        addr.sin_port = port.bigEndian

        let len = socklen_t(MemoryLayout<sockaddr_in>.stride)
        return withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                guard Darwin.bind(serverSock, $0, len) == 0 else {
                    return nil
                }
                return serverSock
            }
        }
    }

    func testReserveAnyPort() throws {
        let port = try Port.reservePort()
        XCTAssert(port > 0)
        let sock = Self.checkConnect(port: port)
        XCTAssertNotNil(sock)
        close(sock!)
    }

    func testReserveFirstUnused() throws {
        let port = try Port.reservePort(2345)
        let sock = Self.checkConnect(port: port)
        XCTAssertNotNil(sock)
        let port2 = try Port.reserveAvailablePort(startingAt: 2345)
        XCTAssert(port2 > 2345)
        close(sock!)
    }

    func testNatMapping() async throws {
        let port = try Port.TCP()
        let internalPort = port.internalPort
        let externalPort = try await port.externalPort
        let externalIpv4Address = try await port.externalIpv4Address
        print("internalPort = \(internalPort), externalPort = \(externalPort), externalIpv4Address = \(externalIpv4Address)")
    }
}
