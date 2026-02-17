import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum SerialPortError: Error, Equatable {
    case openFailed(path: String, code: Int32)
    case configureFailed(path: String, code: Int32)
    case notOpen
    case readFailed(code: Int32)
    case writeFailed(code: Int32)
    case unsupportedBaudRate(Int)
}

public struct SerialPortConfiguration: Sendable, Equatable {
    public let path: String
    public let baudRate: Int
    public let readTimeoutSeconds: TimeInterval
    public let writeTimeoutSeconds: TimeInterval

    public init(
        path: String,
        baudRate: Int,
        readTimeoutSeconds: TimeInterval = 0.5,
        writeTimeoutSeconds: TimeInterval = 0.5
    ) {
        self.path = path
        self.baudRate = baudRate
        self.readTimeoutSeconds = readTimeoutSeconds
        self.writeTimeoutSeconds = writeTimeoutSeconds
    }
}

public protocol SerialLineIO: Sendable {
    func open() async throws
    func close() async
    func writeLine(_ line: String) async throws
    func readLine() async throws -> String?
}

public actor POSIXSerialPort: SerialLineIO {
    private let configuration: SerialPortConfiguration
    private var fd: Int32 = -1
    private var readBuffer: [UInt8] = []

    public init(configuration: SerialPortConfiguration) {
        self.configuration = configuration
    }

    deinit {
        if fd >= 0 {
            _ = Darwin.close(fd)
        }
    }

    public func open() async throws {
        if fd >= 0 {
            return
        }

        let descriptor = Darwin.open(configuration.path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw SerialPortError.openFailed(path: configuration.path, code: errno)
        }

        do {
            try configure(descriptor: descriptor, baudRate: configuration.baudRate)
        } catch {
            _ = Darwin.close(descriptor)
            throw error
        }

        // Switch back to blocking mode after setup; readiness is handled with select().
        _ = fcntl(descriptor, F_SETFL, 0)
        fd = descriptor
        readBuffer.removeAll(keepingCapacity: true)
    }

    public func close() async {
        guard fd >= 0 else {
            return
        }
        _ = Darwin.close(fd)
        fd = -1
        readBuffer.removeAll(keepingCapacity: true)
    }

    public func writeLine(_ line: String) async throws {
        guard fd >= 0 else {
            throw SerialPortError.notOpen
        }

        let payload = Array((line + "\n").utf8)
        var written = 0

        while written < payload.count {
            guard waitWritable(fd: fd, timeoutSeconds: configuration.writeTimeoutSeconds) else {
                continue
            }

            let n = payload.withUnsafeBytes { rawBuffer -> Int in
                guard let base = rawBuffer.baseAddress else {
                    return -1
                }
                return Darwin.write(fd, base.advanced(by: written), payload.count - written)
            }

            if n < 0 {
                if errno == EINTR || errno == EAGAIN {
                    continue
                }
                throw SerialPortError.writeFailed(code: errno)
            }

            written += n
        }
    }

    public func readLine() async throws -> String? {
        guard fd >= 0 else {
            throw SerialPortError.notOpen
        }

        while true {
            if let line = popCompleteLine() {
                return line
            }

            let readable = waitReadable(fd: fd, timeoutSeconds: configuration.readTimeoutSeconds)
            if !readable {
                return nil
            }

            var chunk = [UInt8](repeating: 0, count: 128)
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n < 0 {
                if errno == EAGAIN || errno == EINTR {
                    continue
                }
                throw SerialPortError.readFailed(code: errno)
            }
            if n == 0 {
                return nil
            }

            readBuffer.append(contentsOf: chunk.prefix(n))
        }
    }

    private func popCompleteLine() -> String? {
        guard let newlineIndex = readBuffer.firstIndex(of: 0x0A) else {
            return nil
        }

        var lineBytes = Array(readBuffer[..<newlineIndex])
        readBuffer.removeFirst(newlineIndex + 1)

        // Strip CR for CRLF lines.
        if lineBytes.last == 0x0D {
            lineBytes.removeLast()
        }

        let line = String(decoding: lineBytes, as: UTF8.self)
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func configure(descriptor: Int32, baudRate: Int) throws {
    var options = termios()
    if tcgetattr(descriptor, &options) != 0 {
        throw SerialPortError.configureFailed(path: "", code: errno)
    }

    cfmakeraw(&options)

    options.c_cflag |= (tcflag_t(CLOCAL) | tcflag_t(CREAD))
    options.c_cflag &= ~tcflag_t(PARENB)
    options.c_cflag &= ~tcflag_t(CSTOPB)
    options.c_cflag &= ~tcflag_t(CSIZE)
    options.c_cflag |= tcflag_t(CS8)

    let speed = try mapBaudRate(baudRate)
    if cfsetspeed(&options, speed) != 0 {
        throw SerialPortError.configureFailed(path: "", code: errno)
    }

    options.c_cc.16 = 0 // VMIN
    options.c_cc.17 = 0 // VTIME

    if tcsetattr(descriptor, TCSANOW, &options) != 0 {
        throw SerialPortError.configureFailed(path: "", code: errno)
    }
}

private func mapBaudRate(_ baudRate: Int) throws -> speed_t {
    switch baudRate {
    case 1200: return speed_t(B1200)
    case 2400: return speed_t(B2400)
    case 4800: return speed_t(B4800)
    case 9600: return speed_t(B9600)
    case 19200: return speed_t(B19200)
    case 38400: return speed_t(B38400)
    case 57600: return speed_t(B57600)
    case 115200: return speed_t(B115200)
    case 230400:
        #if canImport(Darwin)
        return speed_t(B230400)
        #else
        return speed_t(B115200)
        #endif
    default:
        throw SerialPortError.unsupportedBaudRate(baudRate)
    }
}

private func waitReadable(fd: Int32, timeoutSeconds: TimeInterval) -> Bool {
    waitPoll(fd: fd, events: Int16(POLLIN), timeoutSeconds: timeoutSeconds)
}

private func waitWritable(fd: Int32, timeoutSeconds: TimeInterval) -> Bool {
    waitPoll(fd: fd, events: Int16(POLLOUT), timeoutSeconds: timeoutSeconds)
}

private func waitPoll(fd: Int32, events: Int16, timeoutSeconds: TimeInterval) -> Bool {
    var descriptor = pollfd(fd: fd, events: events, revents: 0)
    let timeoutMs = Int32(max(0, timeoutSeconds * 1000))

    while true {
        let result = poll(&descriptor, 1, timeoutMs)
        if result > 0 {
            return true
        }
        if result == 0 {
            return false
        }
        if errno == EINTR {
            continue
        }
        return false
    }
}

public enum SerialPortDiscovery {
    public static let defaultPrefixes = [
        "cu.usbserial",
        "tty.usbserial",
        "cu.wchusbserial",
        "tty.wchusbserial",
        "cu.usbmodem",
        "tty.usbmodem"
    ]

    public static func listPorts(in directory: String = "/dev") -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }
        let filtered = filterCandidateNames(entries)
        return filtered.map { "\(directory)/\($0)" }
    }

    public static func filterCandidateNames(_ names: [String]) -> [String] {
        names
            .filter { name in defaultPrefixes.contains(where: { name.hasPrefix($0) }) }
            .sorted()
    }
}
