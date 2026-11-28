import Foundation

/// A loaded network, ready to run. Loading reads the file, refuses an
/// operator it does not know, and computes once everything that does not
/// depend on the inputs (shapes, constants); a run then executes the rest in
/// the order of the file.
nonisolated struct OnnxSession: Sendable {
    let inputs: [String]
    let outputs: [String]

    private let constants: [String: OnnxTensor]
    private let plan: [OnnxNode]
    /// For each value computed during a run, the last step that reads it.
    private let lastUse: [String: Int]

    static let supported: Set<String> = [
        "Add", "Sub", "Mul", "Div", "Pow", "Mod", "Equal", "Sqrt", "Erf", "Relu", "Clip", "Where",
        "MatMul", "Gemm", "Einsum", "Softmax", "LayerNormalization", "ReduceMean",
        "Transpose", "Reshape", "Unsqueeze", "Squeeze", "Gather", "Slice", "Concat", "Expand",
        "Shape", "Cast", "Constant", "ConstantOfShape", "Identity",
    ]

    init(data: Data) throws {
        try self.init(graph: OnnxGraph(data: data))
    }

    init(graph: OnnxGraph) throws {
        if let unknown = graph.nodes.first(where: { !Self.supported.contains($0.op) }) {
            throw OnnxError.unsupported(unknown.op)
        }
        var constants = graph.initializers
        var plan: [OnnxNode] = []
        for node in graph.nodes {
            let known = node.inputs.allSatisfy { $0.isEmpty || constants[$0] != nil }
            if known {
                let results = try Self.evaluate(node) { constants[$0] }
                for (name, value) in zip(node.outputs, results) { constants[name] = value }
            } else {
                plan.append(node)
            }
        }
        var lastUse: [String: Int] = [:]
        for (step, node) in plan.enumerated() {
            for name in node.inputs where constants[name] == nil { lastUse[name] = step }
        }
        // Only what a run reads is kept.
        let read = Set(plan.flatMap(\.inputs)).union(graph.outputs)
        self.constants = constants.filter { read.contains($0.key) }
        self.plan = plan
        self.lastUse = lastUse
        inputs = graph.inputs
        outputs = graph.outputs
    }

    /// Runs the network on `feeds` (one tensor per input) and returns its outputs by name.
    func run(_ feeds: [String: OnnxTensor]) throws -> [String: OnnxTensor] {
        for name in inputs where feeds[name] == nil { throw OnnxError.malformed("missing input \(name)") }
        var values = feeds
        let wanted = Set(outputs)
        for (step, node) in plan.enumerated() {
            let results = try Self.evaluate(node) { values[$0] ?? constants[$0] }
            for (name, value) in zip(node.outputs, results) { values[name] = value }
            for name in node.inputs where lastUse[name] == step && !wanted.contains(name) { values[name] = nil }
        }
        var answer: [String: OnnxTensor] = [:]
        for name in outputs {
            guard let value = values[name] ?? constants[name] else { throw OnnxError.malformed("output \(name) was not computed") }
            answer[name] = value
        }
        return answer
    }

    // MARK: One operator

    private static func evaluate(_ node: OnnxNode, value: (String) -> OnnxTensor?) throws -> [OnnxTensor] {
        func input(_ index: Int) throws -> OnnxTensor {
            guard index < node.inputs.count, let tensor = value(node.inputs[index]) else {
                throw OnnxError.malformed("\(node.op): input \(index) is missing")
            }
            return tensor
        }
        func optional(_ index: Int) -> OnnxTensor? {
            index < node.inputs.count && !node.inputs[index].isEmpty ? value(node.inputs[index]) : nil
        }

        switch node.op {
        case "Add": return [try OnnxOps.binary(.add, input(0), input(1))]
        case "Sub": return [try OnnxOps.binary(.subtract, input(0), input(1))]
        case "Mul": return [try OnnxOps.binary(.multiply, input(0), input(1))]
        case "Div": return [try OnnxOps.binary(.divide, input(0), input(1))]
        case "Pow": return [try OnnxOps.binary(.power, input(0), input(1))]
        case "Mod":
            guard node.ints["fmod"] ?? 0 == 0 else { throw OnnxError.unsupported("Mod with fmod") }
            return [try OnnxOps.binary(.modulo, input(0), input(1))]
        case "Equal": return [try OnnxOps.binary(.equal, input(0), input(1))]
        case "Sqrt": return [OnnxOps.sqrt(try input(0))]
        case "Erf": return [OnnxOps.erf(try input(0))]
        case "Relu": return [OnnxOps.relu(try input(0))]
        case "Clip":
            return [OnnxOps.clip(try input(0), low: optional(1)?.asFloats().first, high: optional(2)?.asFloats().first)]
        case "Where": return [try OnnxOps.whereOp(input(0), input(1), input(2))]
        case "MatMul": return [try OnnxOps.matmul(input(0), input(1))]
        case "Gemm":
            return [try OnnxOps.gemm(
                input(0), input(1), optional(2),
                alpha: node.floats["alpha"] ?? 1, beta: node.floats["beta"] ?? 1,
                transA: node.ints["transA"] ?? 0 != 0, transB: node.ints["transB"] ?? 0 != 0
            )]
        case "Einsum":
            guard let equation = node.strings["equation"] else { throw OnnxError.malformed("Einsum without an equation") }
            return [try OnnxOps.einsum(equation, input(0), input(1))]
        case "Softmax": return [try OnnxOps.softmax(input(0), axis: node.ints["axis"] ?? -1)]
        case "LayerNormalization":
            return [try OnnxOps.layerNormalization(
                input(0), scale: input(1), bias: optional(2),
                axis: node.ints["axis"] ?? -1, epsilon: node.floats["epsilon"] ?? 1e-5
            )]
        case "ReduceMean":
            // Opset 17 keeps the axes in an attribute; later ones in an input.
            guard let axes = node.intLists["axes"] ?? optional(1)?.asInts() else { throw OnnxError.unsupported("ReduceMean over every axis") }
            return [try OnnxOps.reduceMean(input(0), axes: axes, keepDimensions: node.ints["keepdims"] ?? 1 != 0)]
        case "Transpose": return [try OnnxOps.transpose(input(0), permutation: node.intLists["perm"])]
        case "Reshape":
            return [try OnnxOps.reshape(input(0), to: input(1).asInts(), allowZero: node.ints["allowzero"] ?? 0 != 0)]
        case "Unsqueeze": return [try OnnxOps.unsqueeze(input(0), axes: input(1).asInts())]
        case "Squeeze": return [try OnnxOps.squeeze(input(0), axes: optional(1)?.asInts())]
        case "Gather": return [try OnnxOps.gather(input(0), indices: input(1), axis: node.ints["axis"] ?? 0)]
        case "Slice":
            return [try OnnxOps.slice(
                input(0), starts: input(1).asInts(), ends: input(2).asInts(),
                axes: optional(3)?.asInts(), steps: optional(4)?.asInts()
            )]
        case "Concat":
            guard let axis = node.ints["axis"] else { throw OnnxError.malformed("Concat without an axis") }
            return [try OnnxOps.concat(try node.inputs.indices.map(input), axis: axis)]
        case "Expand": return [try OnnxOps.expand(input(0), to: input(1).asInts())]
        case "Shape":
            let shape = try input(0).shape
            return [OnnxTensor(shape: [shape.count], ints: shape)]
        case "Cast":
            guard let type = node.ints["to"] else { throw OnnxError.malformed("Cast without a type") }
            return [try OnnxOps.cast(input(0), to: type)]
        case "Constant":
            guard let tensor = node.tensors["value"] else { throw OnnxError.unsupported("Constant without a tensor") }
            return [tensor]
        case "ConstantOfShape":
            let shape = try input(0).asInts()
            let count = shape.reduce(1, *)
            guard let fill = node.tensors["value"] else {
                return [OnnxTensor(shape: shape, floats: [Float](repeating: 0, count: count))]
            }
            return [fill.isInt
                ? OnnxTensor(shape: shape, ints: [Int](repeating: fill.ints.first ?? 0, count: count))
                : OnnxTensor(shape: shape, floats: [Float](repeating: fill.floats.first ?? 0, count: count))]
        case "Identity": return [try input(0)]
        default: throw OnnxError.unsupported(node.op)
        }
    }
}
