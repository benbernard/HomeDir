import Darwin
import Foundation
import FzfPaletteCore
import os

final class SocketServer {
    typealias Handler = (PaletteClientRequest) -> PaletteResponse

    private let logger = Logger(subsystem: "dev.benbernard.fzf-palette", category: "socket")
    private let queue = DispatchQueue(label: "dev.benbernard.fzf-palette.socket")
    private let connectionQueue = DispatchQueue(
        label: "dev.benbernard.fzf-palette.socket.connection",
        attributes: .concurrent
    )
    private var serverFD: Int32 = -1
    private var isRunning = false
    private var handler: Handler?

    func start(handler: @escaping Handler) throws {
        try FzfPalettePaths.ensureRuntimeDirectories()
        self.handler = handler

        let path = FzfPalettePaths.socketURL.path
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw SocketServerError.socketCreateFailed
        }

        var address = try unixAddress(path: path)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw SocketServerError.bindFailed(path)
        }

        guard listen(fd, 16) == 0 else {
            close(fd)
            throw SocketServerError.listenFailed
        }

        serverFD = fd
        isRunning = true

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        isRunning = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(FzfPalettePaths.socketURL.path)
    }

    private func acceptLoop() {
        while isRunning {
            let clientFD = accept(serverFD, nil, nil)
            if clientFD < 0 {
                if isRunning {
                    logger.error("accept failed")
                }
                continue
            }
            connectionQueue.async { [weak self] in
                self?.handleConnection(clientFD)
            }
        }
    }

    private func handleConnection(_ clientFD: Int32) {
        defer { close(clientFD) }

        do {
            let data = try readAll(from: clientFD)
            let request = try WireCoding.decodeRequest(data)
            let response = handler?(request) ?? PaletteResponse(
                type: .error,
                id: request.id,
                code: "server_unavailable",
                message: "Socket handler is not installed"
            )
            try write(response, to: clientFD)
        } catch {
            logger.error("connection failed: \(String(describing: error))")
            let response = PaletteResponse(
                type: .error,
                code: "bad_request",
                message: String(describing: error)
            )
            try? write(response, to: clientFD)
        }
    }

    private func readAll(from fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 {
                break
            }
            guard count > 0 else {
                throw SocketServerError.readFailed
            }
            data.append(buffer, count: count)
            if buffer.prefix(count).contains(0x0A) {
                break
            }
        }
        return data
    }

    private func write(_ response: PaletteResponse, to fd: Int32) throws {
        let data = try WireCoding.encodeLine(response)
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw SocketServerError.writeFailed
            }
            var written = 0
            while written < data.count {
                let count = Darwin.write(fd, base.advanced(by: written), data.count - written)
                guard count > 0 else {
                    throw SocketServerError.writeFailed
                }
                written += count
            }
        }
    }

    private func unixAddress(path: String) throws -> sockaddr_un {
        let bytes = Array(path.utf8)
        var address = sockaddr_un()
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else {
            throw SocketServerError.pathTooLong(path)
        }

        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        return address
    }
}

enum SocketServerError: Error, CustomStringConvertible {
    case socketCreateFailed
    case pathTooLong(String)
    case bindFailed(String)
    case listenFailed
    case readFailed
    case writeFailed

    var description: String {
        switch self {
        case .socketCreateFailed:
            return "Could not create Unix socket"
        case let .pathTooLong(path):
            return "Socket path is too long: \(path)"
        case let .bindFailed(path):
            return "Could not bind socket at \(path)"
        case .listenFailed:
            return "Could not listen on socket"
        case .readFailed:
            return "Could not read from socket"
        case .writeFailed:
            return "Could not write to socket"
        }
    }
}
