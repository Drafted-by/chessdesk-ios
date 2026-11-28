import Foundation

// A reader for the part of the ONNX file format the Maia network uses. ONNX
// is a protocol-buffers file: a graph of nodes (one operator each) and the
// weights they read. The app runs the same file the site downloads, so the
// bots play from the same network; nothing here depends on a third-party
// runtime.

nonisolated enum OnnxError: Error, Equatable {
    case malformed(String)
    case unsupported(String)
}

/// One operator of the graph, with its attributes already decoded.
nonisolated struct OnnxNode: Sendable {
    var op = ""
    var inputs: [String] = []
    var outputs: [String] = []
    var ints: [String: Int] = [:]
    var floats: [String: Float] = [:]
    var strings: [String: String] = [:]
    var intLists: [String: [Int]] = [:]
    var tensors: [String: OnnxTensor] = [:]
}

nonisolated struct OnnxGraph: Sendable {
    var nodes: [OnnxNode] = []
    var initializers: [String: OnnxTensor] = [:]
    var inputs: [String] = []
    var outputs: [String] = []

    init(data: Data) throws {
        var model = ProtoReader(data)
        var found = false
        while let field = try model.next() {
            // ModelProto.graph = 7
            if field.number == 7, case let .bytes(graph) = field.value {
                try read(graph: graph)
                found = true
            }
        }
        guard found, !nodes.isEmpty else { throw OnnxError.malformed("no graph") }
        // Weights are also listed as inputs by some exporters: they are not fed.
        inputs.removeAll { initializers[$0] != nil }
    }

    private mutating func read(graph: Data) throws {
        var reader = ProtoReader(graph)
        while let field = try reader.next() {
            guard case let .bytes(payload) = field.value else { continue }
            switch field.number {
            case 1: nodes.append(try Self.node(payload))
            case 5:
                let (name, tensor) = try Self.tensor(payload)
                initializers[name] = tensor
            case 11: inputs.append(try Self.valueName(payload))
            case 12: outputs.append(try Self.valueName(payload))
            default: break
            }
        }
    }

    private static func valueName(_ data: Data) throws -> String {
        var reader = ProtoReader(data)
        while let field = try reader.next() {
            if field.number == 1, case let .bytes(name) = field.value { return String(decoding: name, as: UTF8.self) }
        }
        throw OnnxError.malformed("value without a name")
    }

    private static func node(_ data: Data) throws -> OnnxNode {
        var node = OnnxNode()
        var reader = ProtoReader(data)
        while let field = try reader.next() {
            guard case let .bytes(payload) = field.value else { continue }
            switch field.number {
            case 1: node.inputs.append(String(decoding: payload, as: UTF8.self))
            case 2: node.outputs.append(String(decoding: payload, as: UTF8.self))
            case 4: node.op = String(decoding: payload, as: UTF8.self)
            case 5: try attribute(payload, into: &node)
            default: break
            }
        }
        return node
    }

    private static func attribute(_ data: Data, into node: inout OnnxNode) throws {
        var name = ""
        var int: Int?
        var float: Float?
        var string: String?
        var ints: [Int] = []
        var tensor: OnnxTensor?
        var reader = ProtoReader(data)
        while let field = try reader.next() {
            switch (field.number, field.value) {
            case let (1, .bytes(payload)): name = String(decoding: payload, as: UTF8.self)
            case let (2, .fixed32(bits)): float = Float(bitPattern: bits)
            case let (3, .varint(value)): int = Int(Int64(bitPattern: value))
            case let (4, .bytes(payload)): string = String(decoding: payload, as: UTF8.self)
            case let (5, .bytes(payload)): tensor = try Self.tensor(payload).tensor
            case let (8, .varint(value)): ints.append(Int(Int64(bitPattern: value)))
            case let (8, .bytes(packed)): ints.append(contentsOf: try ProtoReader.packedVarints(packed))
            default: break
            }
        }
        if let int { node.ints[name] = int }
        if let float { node.floats[name] = float }
        if let string { node.strings[name] = string }
        if let tensor { node.tensors[name] = tensor }
        if !ints.isEmpty { node.intLists[name] = ints }
    }

    /// A TensorProto: float32 and int64 (and bool) are all this network holds.
    private static func tensor(_ data: Data) throws -> (name: String, tensor: OnnxTensor) {
        var name = ""
        var dims: [Int] = []
        var type = 0
        var raw: Data?
        var floats: [Float] = []
        var ints: [Int] = []
        var reader = ProtoReader(data)
        while let field = try reader.next() {
            switch (field.number, field.value) {
            case let (1, .varint(value)): dims.append(Int(Int64(bitPattern: value)))
            case let (1, .bytes(packed)): dims.append(contentsOf: try ProtoReader.packedVarints(packed))
            case let (2, .varint(value)): type = Int(value)
            case let (4, .fixed32(bits)): floats.append(Float(bitPattern: bits))
            case let (4, .bytes(packed)): floats.append(contentsOf: ProtoReader.floats(packed))
            case let (7, .varint(value)): ints.append(Int(Int64(bitPattern: value)))
            case let (7, .bytes(packed)): ints.append(contentsOf: try ProtoReader.packedVarints(packed))
            case let (8, .bytes(payload)): name = String(decoding: payload, as: UTF8.self)
            case let (9, .bytes(payload)): raw = payload
            default: break
            }
        }
        let count = dims.reduce(1, *)
        switch type {
        case 1:
            if let raw { floats = ProtoReader.floats(raw) }
            guard floats.count == count else { throw OnnxError.malformed("tensor \(name): \(floats.count) values for \(dims)") }
            return (name, OnnxTensor(shape: dims, floats: floats))
        case 7:
            if let raw { ints = ProtoReader.int64s(raw) }
            guard ints.count == count else { throw OnnxError.malformed("tensor \(name): \(ints.count) values for \(dims)") }
            return (name, OnnxTensor(shape: dims, ints: ints))
        case 9:
            if let raw { ints = raw.map { Int($0) } }
            guard ints.count == count else { throw OnnxError.malformed("tensor \(name): \(ints.count) values for \(dims)") }
            return (name, OnnxTensor(shape: dims, ints: ints))
        default:
            throw OnnxError.unsupported("tensor type \(type)")
        }
    }
}

/// The protocol-buffers wire format: a sequence of (field number, value).
nonisolated struct ProtoReader {
    enum Value {
        case varint(UInt64)
        case fixed64(UInt64)
        case fixed32(UInt32)
        case bytes(Data)
    }

    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        offset = data.startIndex
    }

    mutating func next() throws -> (number: Int, value: Value)? {
        guard offset < data.endIndex else { return nil }
        let key = try varint()
        let number = Int(key >> 3)
        switch key & 7 {
        case 0: return (number, .varint(try varint()))
        case 1: return (number, .fixed64(try fixed(8)))
        case 2:
            let length = Int(try varint())
            guard length >= 0, offset + length <= data.endIndex else { throw OnnxError.malformed("field past the end") }
            defer { offset += length }
            return (number, .bytes(data[offset..<(offset + length)]))
        case 5: return (number, .fixed32(UInt32(try fixed(4))))
        default: throw OnnxError.malformed("wire type \(key & 7)")
        }
    }

    private mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while offset < data.endIndex {
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { break }
        }
        throw OnnxError.malformed("unfinished varint")
    }

    private mutating func fixed(_ width: Int) throws -> UInt64 {
        guard offset + width <= data.endIndex else { throw OnnxError.malformed("field past the end") }
        var result: UInt64 = 0
        for index in 0..<width { result |= UInt64(data[offset + index]) << UInt64(8 * index) }
        offset += width
        return result
    }

    static func packedVarints(_ data: Data) throws -> [Int] {
        var reader = ProtoReader(data)
        var values: [Int] = []
        while reader.offset < data.endIndex { values.append(Int(Int64(bitPattern: try reader.varint()))) }
        return values
    }

    /// Little-endian float32, as every Apple device stores them.
    static func floats(_ data: Data) -> [Float] {
        let count = data.count / 4
        return [Float](unsafeUninitializedCapacity: count) { buffer, initialized in
            _ = data.copyBytes(to: buffer)
            initialized = count
        }
    }

    static func int64s(_ data: Data) -> [Int] {
        let count = data.count / 8
        let wide = [Int64](unsafeUninitializedCapacity: count) { buffer, initialized in
            _ = data.copyBytes(to: buffer)
            initialized = count
        }
        return wide.map { Int($0) }
    }
}
