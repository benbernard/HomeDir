import Darwin
import Foundation

public enum SocketClientError: Error, Equatable, CustomStringConvertible {
    case pathTooLong(String)
    case connectFailed(String)
    case writeFailed
    case readFailed
    case emptyResponse

    public var description: String {
        switch self {
        case let .pathTooLong(path):
            return "Socket path is too long: \(path)"
        case let .connectFailed(path):
            return "Could not connect to \(path)"
        case .writeFailed:
            return "Could not write request to socket"
        case .readFailed:
            return "Could not read response from socket"
        case .emptyResponse:
            return "Socket returned an empty response"
        }
    }
}

public final class PaletteSocketClient {
    public let socketPath: String

    public init(socketPath: String = FzfPalettePaths.socketURL.path) {
        self.socketPath = socketPath
    }

    public func send(_ request: PaletteClientRequest) throws -> PaletteResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw SocketClientError.connectFailed(socketPath)
        }
        defer { close(fd) }

        var address = try unixAddress(path: socketPath)
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw SocketClientError.connectFailed(socketPath)
        }

        let data = try WireCoding.encodeLine(request)
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw SocketClientError.writeFailed
            }
            var written = 0
            while written < data.count {
                let result = Darwin.write(fd, base.advanced(by: written), data.count - written)
                guard result > 0 else {
                    throw SocketClientError.writeFailed
                }
                written += result
            }
        }
        shutdown(fd, SHUT_WR)

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 {
                break
            }
            guard count > 0 else {
                throw SocketClientError.readFailed
            }
            response.append(buffer, count: count)
        }

        guard !response.isEmpty else {
            throw SocketClientError.emptyResponse
        }
        return try WireCoding.decodeResponse(response)
    }

    private func unixAddress(path: String) throws -> sockaddr_un {
        let bytes = Array(path.utf8)
        var address = sockaddr_un()
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else {
            throw SocketClientError.pathTooLong(path)
        }

        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        return address
    }
}
