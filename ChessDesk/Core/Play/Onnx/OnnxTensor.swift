import Accelerate
import Foundation

/// A tensor of float32 values, or of integers (ONNX int64 and bool: shapes,
/// indices and masks). Row-major, like ONNX and NumPy.
nonisolated struct OnnxTensor: Sendable, Equatable {
    var shape: [Int]
    var floats: [Float] = []
    var ints: [Int] = []
    var isInt = false

    init(shape: [Int], floats: [Float]) {
        self.shape = shape
        self.floats = floats
    }

    init(shape: [Int], ints: [Int]) {
        self.shape = shape
        self.ints = ints
        isInt = true
    }

    var count: Int { isInt ? ints.count : floats.count }
    var rank: Int { shape.count }

    /// The same values under another shape.
    func reshaped(_ shape: [Int]) -> OnnxTensor {
        var copy = self
        copy.shape = shape
        return copy
    }

    func asFloats() -> [Float] { isInt ? ints.map(Float.init) : floats }
    func asInts() -> [Int] { isInt ? ints : floats.map { Int($0) } }
}

/// The operators, as plain functions on tensors. Each follows the ONNX
/// specification for the cases the Maia network exercises; an unsupported
/// case throws rather than computing something else.
nonisolated enum OnnxOps {
    // MARK: Shapes

    static func axis(_ axis: Int, rank: Int) throws -> Int {
        let resolved = axis < 0 ? axis + rank : axis
        guard (0..<max(rank, 1)).contains(resolved) else { throw OnnxError.malformed("axis \(axis) of rank \(rank)") }
        return resolved
    }

    static func broadcastShape(_ lhs: [Int], _ rhs: [Int]) throws -> [Int] {
        let rank = max(lhs.count, rhs.count)
        let left = [Int](repeating: 1, count: rank - lhs.count) + lhs
        let right = [Int](repeating: 1, count: rank - rhs.count) + rhs
        return try zip(left, right).map { one, two in
            if one == two || two == 1 { return one }
            if one == 1 { return two }
            throw OnnxError.malformed("shapes \(lhs) and \(rhs) do not broadcast")
        }
    }

    /// The values of `tensor` repeated to fill `shape` (NumPy broadcasting).
    static func expand<Element>(_ values: [Element], from shape: [Int], to target: [Int]) -> [Element] {
        var current = [Int](repeating: 1, count: target.count - shape.count) + shape
        if current == target { return values }
        var data = values
        for axis in stride(from: target.count - 1, through: 0, by: -1) where current[axis] == 1 && target[axis] > 1 {
            let inner = current[(axis + 1)...].reduce(1, *)
            let outer = current[..<axis].reduce(1, *)
            var widened: [Element] = []
            widened.reserveCapacity(outer * target[axis] * inner)
            for block in 0..<outer {
                if inner == 1 {
                    widened.append(contentsOf: repeatElement(data[block], count: target[axis]))
                } else {
                    let slice = data[(block * inner)..<((block + 1) * inner)]
                    for _ in 0..<target[axis] { widened.append(contentsOf: slice) }
                }
            }
            data = widened
            current[axis] = target[axis]
        }
        return data
    }

    static func expand(_ tensor: OnnxTensor, to shape: [Int]) throws -> OnnxTensor {
        let target = try broadcastShape(tensor.shape, shape)
        return tensor.isInt
            ? OnnxTensor(shape: target, ints: expand(tensor.ints, from: tensor.shape, to: target))
            : OnnxTensor(shape: target, floats: expand(tensor.floats, from: tensor.shape, to: target))
    }

    // MARK: Arithmetic

    enum Binary { case add, subtract, multiply, divide, power, modulo, equal }

    static func binary(_ kind: Binary, _ lhs: OnnxTensor, _ rhs: OnnxTensor) throws -> OnnxTensor {
        let shape = try broadcastShape(lhs.shape, rhs.shape)
        if lhs.isInt, rhs.isInt {
            let left = expand(lhs.ints, from: lhs.shape, to: shape)
            let right = expand(rhs.ints, from: rhs.shape, to: shape)
            let values: [Int] = try zip(left, right).map { one, two in
                switch kind {
                case .add: return one &+ two
                case .subtract: return one &- two
                case .multiply: return one &* two
                case .divide:
                    guard two != 0 else { throw OnnxError.malformed("integer division by zero") }
                    return one / two
                case .modulo:
                    guard two != 0 else { throw OnnxError.malformed("integer modulo by zero") }
                    // The sign of the divisor, as ONNX Mod with fmod = 0.
                    let remainder = one % two
                    return remainder != 0 && (remainder < 0) != (two < 0) ? remainder + two : remainder
                case .equal: return one == two ? 1 : 0
                case .power: throw OnnxError.unsupported("Pow on integers")
                }
            }
            return OnnxTensor(shape: shape, ints: values)
        }
        let left = lhs.asFloats()
        let right = rhs.asFloats()
        if kind == .equal {
            let one = expand(left, from: lhs.shape, to: shape)
            let two = expand(right, from: rhs.shape, to: shape)
            return OnnxTensor(shape: shape, ints: zip(one, two).map { $0 == $1 ? 1 : 0 })
        }
        // A single value against a tensor: the common case, without copying it out.
        if right.count == 1, left.count == shape.reduce(1, *) {
            let scalar = right[0]
            let values: [Float]
            switch kind {
            case .add: values = vDSP.add(scalar, left)
            case .subtract: values = vDSP.add(-scalar, left)
            case .multiply: values = vDSP.multiply(scalar, left)
            case .divide: values = vDSP.divide(left, scalar)
            case .power: values = power(left, scalar)
            case .modulo: values = left.map { fmodf($0, scalar) }
            case .equal: values = []
            }
            return OnnxTensor(shape: shape, floats: values)
        }
        let one = expand(left, from: lhs.shape, to: shape)
        let two = expand(right, from: rhs.shape, to: shape)
        let values: [Float]
        switch kind {
        case .add: values = vDSP.add(one, two)
        case .subtract: values = vDSP.subtract(one, two)
        case .multiply: values = vDSP.multiply(one, two)
        case .divide: values = vDSP.divide(one, two)
        case .power: values = zip(one, two).map { powf($0, $1) }
        case .modulo: values = zip(one, two).map { fmodf($0, $1) }
        case .equal: values = []
        }
        return OnnxTensor(shape: shape, floats: values)
    }

    private static func power(_ values: [Float], _ exponent: Float) -> [Float] {
        if exponent == 2 { return vDSP.multiply(values, values) }
        if exponent == 0.5 { return vForce.sqrt(values) }
        return values.map { powf($0, exponent) }
    }

    static func sqrt(_ tensor: OnnxTensor) -> OnnxTensor {
        OnnxTensor(shape: tensor.shape, floats: vForce.sqrt(tensor.asFloats()))
    }

    static func erf(_ tensor: OnnxTensor) -> OnnxTensor {
        var values = tensor.asFloats()
        values.withUnsafeMutableBufferPointer { buffer in
            for index in 0..<buffer.count { buffer[index] = erff(buffer[index]) }
        }
        return OnnxTensor(shape: tensor.shape, floats: values)
    }

    static func relu(_ tensor: OnnxTensor) -> OnnxTensor {
        OnnxTensor(shape: tensor.shape, floats: vDSP.threshold(tensor.asFloats(), to: 0, with: .zeroFill))
    }

    static func clip(_ tensor: OnnxTensor, low: Float?, high: Float?) -> OnnxTensor {
        let lower = low ?? -Float.greatestFiniteMagnitude
        let upper = high ?? Float.greatestFiniteMagnitude
        return OnnxTensor(shape: tensor.shape, floats: vDSP.clip(tensor.asFloats(), to: lower...upper))
    }

    static func whereOp(_ condition: OnnxTensor, _ lhs: OnnxTensor, _ rhs: OnnxTensor) throws -> OnnxTensor {
        let shape = try broadcastShape(try broadcastShape(condition.shape, lhs.shape), rhs.shape)
        let mask = expand(condition.asInts(), from: condition.shape, to: shape)
        if lhs.isInt, rhs.isInt {
            let one = expand(lhs.ints, from: lhs.shape, to: shape)
            let two = expand(rhs.ints, from: rhs.shape, to: shape)
            return OnnxTensor(shape: shape, ints: mask.indices.map { mask[$0] != 0 ? one[$0] : two[$0] })
        }
        let one = expand(lhs.asFloats(), from: lhs.shape, to: shape)
        let two = expand(rhs.asFloats(), from: rhs.shape, to: shape)
        return OnnxTensor(shape: shape, floats: mask.indices.map { mask[$0] != 0 ? one[$0] : two[$0] })
    }

    // MARK: Linear algebra

    /// rows × inner times inner × columns, row-major.
    private static func multiply(_ lhs: UnsafePointer<Float>, _ rhs: UnsafePointer<Float>,
                                 into result: UnsafeMutablePointer<Float>, rows: Int, inner: Int, columns: Int) {
        vDSP_mmul(lhs, 1, rhs, 1, result, 1, vDSP_Length(rows), vDSP_Length(columns), vDSP_Length(inner))
    }

    private static func transposed(_ matrix: [Float], rows: Int, columns: Int) -> [Float] {
        var result = [Float](repeating: 0, count: matrix.count)
        vDSP_mtrans(matrix, 1, &result, 1, vDSP_Length(columns), vDSP_Length(rows))
        return result
    }

    /// NumPy matmul for a stack of matrices times one matrix, or two stacks
    /// of the same height.
    static func matmul(_ lhs: OnnxTensor, _ rhs: OnnxTensor) throws -> OnnxTensor {
        guard lhs.rank >= 2, rhs.rank >= 2, !lhs.isInt, !rhs.isInt,
              let inner = lhs.shape.last, inner == rhs.shape[rhs.rank - 2]
        else { throw OnnxError.unsupported("MatMul of \(lhs.shape) and \(rhs.shape)") }
        let columns = rhs.shape[rhs.rank - 1]
        let rows = lhs.shape[lhs.rank - 2]
        let leftBatch = lhs.shape.dropLast(2).reduce(1, *)
        let rightBatch = rhs.shape.dropLast(2).reduce(1, *)

        if rightBatch == 1 {
            // Every row of every matrix on the left meets the same matrix.
            let total = leftBatch * rows
            var result = [Float](repeating: 0, count: total * columns)
            multiply(lhs.floats, rhs.floats, into: &result, rows: total, inner: inner, columns: columns)
            return OnnxTensor(shape: lhs.shape.dropLast() + [columns], floats: result)
        }
        guard leftBatch == rightBatch else { throw OnnxError.unsupported("MatMul of \(lhs.shape) and \(rhs.shape)") }
        var result = [Float](repeating: 0, count: leftBatch * rows * columns)
        lhs.floats.withUnsafeBufferPointer { left in
            rhs.floats.withUnsafeBufferPointer { right in
                result.withUnsafeMutableBufferPointer { out in
                    guard let left = left.baseAddress, let right = right.baseAddress, let out = out.baseAddress else { return }
                    for batch in 0..<leftBatch {
                        multiply(left + batch * rows * inner, right + batch * inner * columns,
                                 into: out + batch * rows * columns, rows: rows, inner: inner, columns: columns)
                    }
                }
            }
        }
        return OnnxTensor(shape: lhs.shape.dropLast() + [columns], floats: result)
    }

    /// Y = alpha · A · B(ᵀ) + beta · C, on matrices.
    static func gemm(_ lhs: OnnxTensor, _ rhs: OnnxTensor, _ bias: OnnxTensor?,
                     alpha: Float, beta: Float, transA: Bool, transB: Bool) throws -> OnnxTensor {
        guard lhs.rank == 2, rhs.rank == 2, !transA else { throw OnnxError.unsupported("Gemm of \(lhs.shape) and \(rhs.shape)") }
        let weights = transB
            ? OnnxTensor(shape: [rhs.shape[1], rhs.shape[0]], floats: transposed(rhs.floats, rows: rhs.shape[0], columns: rhs.shape[1]))
            : rhs
        var product = try matmul(lhs, weights)
        if alpha != 1 { product.floats = vDSP.multiply(alpha, product.floats) }
        guard let bias else { return product }
        let scaled = beta == 1 ? bias : OnnxTensor(shape: bias.shape, floats: vDSP.multiply(beta, bias.asFloats()))
        return try binary(.add, product, scaled)
    }

    /// The two contractions the network uses.
    static func einsum(_ equation: String, _ lhs: OnnxTensor, _ rhs: OnnxTensor) throws -> OnnxTensor {
        switch equation.replacingOccurrences(of: " ", with: "") {
        case "bid,bjd->bij":
            // Each matrix times the transpose of its partner.
            guard lhs.rank == 3, rhs.rank == 3, lhs.shape[0] == rhs.shape[0], lhs.shape[2] == rhs.shape[2]
            else { throw OnnxError.malformed("einsum \(equation) on \(lhs.shape), \(rhs.shape)") }
            let (batch, rows, depth) = (rhs.shape[0], rhs.shape[1], rhs.shape[2])
            var flipped: [Float] = []
            flipped.reserveCapacity(rhs.floats.count)
            for index in 0..<batch {
                let block = Array(rhs.floats[(index * rows * depth)..<((index + 1) * rows * depth)])
                flipped.append(contentsOf: transposed(block, rows: rows, columns: depth))
            }
            return try matmul(lhs, OnnxTensor(shape: [batch, depth, rows], floats: flipped))
        case "bhi,oi->bho":
            guard lhs.rank == 3, rhs.rank == 2, lhs.shape[2] == rhs.shape[1]
            else { throw OnnxError.malformed("einsum \(equation) on \(lhs.shape), \(rhs.shape)") }
            let flipped = transposed(rhs.floats, rows: rhs.shape[0], columns: rhs.shape[1])
            return try matmul(lhs, OnnxTensor(shape: [rhs.shape[1], rhs.shape[0]], floats: flipped))
        default:
            throw OnnxError.unsupported("Einsum \(equation)")
        }
    }

    // MARK: Normalisation

    /// Over the last axis.
    static func softmax(_ tensor: OnnxTensor, axis: Int) throws -> OnnxTensor {
        guard try self.axis(axis, rank: tensor.rank) == tensor.rank - 1, let width = tensor.shape.last, width > 0
        else { throw OnnxError.unsupported("Softmax on axis \(axis) of \(tensor.shape)") }
        var values = tensor.floats
        var count = Int32(width)
        values.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for start in stride(from: 0, to: buffer.count, by: width) {
                let row = base + start
                var top: Float = 0
                vDSP_maxv(row, 1, &top, vDSP_Length(width))
                var shift = -top
                vDSP_vsadd(row, 1, &shift, row, 1, vDSP_Length(width))
                vvexpf(row, row, &count)
                var total: Float = 0
                vDSP_sve(row, 1, &total, vDSP_Length(width))
                vDSP_vsdiv(row, 1, &total, row, 1, vDSP_Length(width))
            }
        }
        return OnnxTensor(shape: tensor.shape, floats: values)
    }

    /// Over the last axis: zero mean, unit variance, then scale and bias.
    static func layerNormalization(_ tensor: OnnxTensor, scale: OnnxTensor, bias: OnnxTensor?,
                                   axis: Int, epsilon: Float) throws -> OnnxTensor {
        guard try self.axis(axis, rank: tensor.rank) == tensor.rank - 1, let width = tensor.shape.last, width > 0,
              scale.count == width, bias.map({ $0.count == width }) ?? true
        else { throw OnnxError.unsupported("LayerNormalization on axis \(axis) of \(tensor.shape)") }
        var values = tensor.floats
        let offsets = bias?.floats
        values.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for start in stride(from: 0, to: buffer.count, by: width) {
                let row = base + start
                var mean: Float = 0
                vDSP_meanv(row, 1, &mean, vDSP_Length(width))
                var shift = -mean
                vDSP_vsadd(row, 1, &shift, row, 1, vDSP_Length(width))
                var variance: Float = 0
                vDSP_measqv(row, 1, &variance, vDSP_Length(width))
                var deviation = (variance + epsilon).squareRoot()
                vDSP_vsdiv(row, 1, &deviation, row, 1, vDSP_Length(width))
                vDSP_vmul(row, 1, scale.floats, 1, row, 1, vDSP_Length(width))
                if let offsets { vDSP_vadd(row, 1, offsets, 1, row, 1, vDSP_Length(width)) }
            }
        }
        return OnnxTensor(shape: tensor.shape, floats: values)
    }

    static func reduceMean(_ tensor: OnnxTensor, axes: [Int], keepDimensions: Bool) throws -> OnnxTensor {
        guard axes.count == 1 else { throw OnnxError.unsupported("ReduceMean over \(axes)") }
        let axis = try self.axis(axes[0], rank: tensor.rank)
        let length = tensor.shape[axis]
        let outer = tensor.shape[..<axis].reduce(1, *)
        let inner = tensor.shape[(axis + 1)...].reduce(1, *)
        var result = [Float](repeating: 0, count: outer * inner)
        tensor.floats.withUnsafeBufferPointer { values in
            result.withUnsafeMutableBufferPointer { sums in
                guard let source = values.baseAddress, let target = sums.baseAddress, length > 0, inner > 0 else { return }
                for block in 0..<outer {
                    let row = target + block * inner
                    if inner == 1 {
                        vDSP_sve(source + block * length, 1, row, vDSP_Length(length))
                        continue
                    }
                    for step in 0..<length {
                        vDSP_vadd(row, 1, source + (block * length + step) * inner, 1, row, 1, vDSP_Length(inner))
                    }
                }
            }
        }
        result = vDSP.divide(result, Float(max(length, 1)))
        var shape = tensor.shape
        if keepDimensions { shape[axis] = 1 } else { shape.remove(at: axis) }
        return OnnxTensor(shape: shape, floats: result)
    }

    // MARK: Moving values around

    static func transpose(_ tensor: OnnxTensor, permutation: [Int]?) throws -> OnnxTensor {
        let order = permutation ?? Array((0..<tensor.rank).reversed())
        guard order.count == tensor.rank, Set(order) == Set(0..<tensor.rank)
        else { throw OnnxError.malformed("Transpose \(order) of \(tensor.shape)") }
        let shape = order.map { tensor.shape[$0] }
        var strides = [Int](repeating: 1, count: tensor.rank)
        for axis in stride(from: tensor.rank - 2, through: 0, by: -1) { strides[axis] = strides[axis + 1] * tensor.shape[axis + 1] }
        let sourceStrides = order.map { strides[$0] }
        // The last axis of the result is a run of evenly spaced source values;
        // the axes before it only move where the run starts.
        let rank = tensor.rank
        let run = rank > 0 ? shape[rank - 1] : 1
        let step = rank > 0 ? sourceStrides[rank - 1] : 1
        var starts: [Int] = [0]
        for axis in 0..<max(rank - 1, 0) {
            var next: [Int] = []
            next.reserveCapacity(starts.count * shape[axis])
            for start in starts {
                for index in 0..<shape[axis] { next.append(start + index * sourceStrides[axis]) }
            }
            starts = next
        }
        let total = tensor.count
        if tensor.isInt {
            var values: [Int] = []
            values.reserveCapacity(total)
            for start in starts {
                for index in 0..<run { values.append(tensor.ints[start + index * step]) }
            }
            return OnnxTensor(shape: shape, ints: values)
        }
        var values = [Float](repeating: 0, count: total)
        tensor.floats.withUnsafeBufferPointer { source in
            values.withUnsafeMutableBufferPointer { target in
                guard let source = source.baseAddress, let target = target.baseAddress, run > 0 else { return }
                for (row, start) in starts.enumerated() {
                    // A strided copy: vDSP adds zero to every `step`-th value.
                    var zero: Float = 0
                    vDSP_vsadd(source + start, vDSP_Stride(step), &zero, target + row * run, 1, vDSP_Length(run))
                }
            }
        }
        return OnnxTensor(shape: shape, floats: values)
    }

    static func reshape(_ tensor: OnnxTensor, to wanted: [Int], allowZero: Bool = false) throws -> OnnxTensor {
        var shape = wanted
        for (index, size) in wanted.enumerated() where size == 0 && !allowZero {
            guard index < tensor.rank else { throw OnnxError.malformed("Reshape \(tensor.shape) to \(wanted)") }
            shape[index] = tensor.shape[index]
        }
        if let unknown = shape.firstIndex(of: -1) {
            let known = shape.enumerated().filter { $0.offset != unknown }.map(\.element).reduce(1, *)
            guard known > 0, tensor.count % known == 0 else { throw OnnxError.malformed("Reshape \(tensor.shape) to \(wanted)") }
            shape[unknown] = tensor.count / known
        }
        guard shape.reduce(1, *) == tensor.count else { throw OnnxError.malformed("Reshape \(tensor.shape) to \(wanted)") }
        return tensor.reshaped(shape)
    }

    static func unsqueeze(_ tensor: OnnxTensor, axes: [Int]) throws -> OnnxTensor {
        let rank = tensor.rank + axes.count
        let resolved = try axes.map { try axis($0, rank: rank) }.sorted()
        var shape = tensor.shape
        for position in resolved { shape.insert(1, at: min(position, shape.count)) }
        return tensor.reshaped(shape)
    }

    static func squeeze(_ tensor: OnnxTensor, axes: [Int]?) throws -> OnnxTensor {
        let dropped: Set<Int>
        if let axes {
            dropped = Set(try axes.map { try axis($0, rank: tensor.rank) })
            guard dropped.allSatisfy({ tensor.shape[$0] == 1 }) else { throw OnnxError.malformed("Squeeze \(axes) of \(tensor.shape)") }
        } else {
            dropped = Set(tensor.shape.indices.filter { tensor.shape[$0] == 1 })
        }
        return tensor.reshaped(tensor.shape.enumerated().filter { !dropped.contains($0.offset) }.map(\.element))
    }

    /// Picks whole slices along `axis`: the result has the shape of the
    /// indices in place of that axis.
    static func gather(_ tensor: OnnxTensor, indices: OnnxTensor, axis: Int) throws -> OnnxTensor {
        let axis = try self.axis(axis, rank: tensor.rank)
        let length = tensor.shape[axis]
        let outer = tensor.shape[..<axis].reduce(1, *)
        let inner = tensor.shape[(axis + 1)...].reduce(1, *)
        let picks = try indices.asInts().map { index -> Int in
            let resolved = index < 0 ? index + length : index
            guard (0..<length).contains(resolved) else { throw OnnxError.malformed("Gather index \(index) of \(length)") }
            return resolved
        }
        let shape = Array(tensor.shape[..<axis]) + indices.shape + Array(tensor.shape[(axis + 1)...])
        var floats: [Float] = []
        var ints: [Int] = []
        if tensor.isInt { ints.reserveCapacity(outer * picks.count * inner) } else { floats.reserveCapacity(outer * picks.count * inner) }
        for block in 0..<outer {
            for pick in picks {
                let base = (block * length + pick) * inner
                if tensor.isInt {
                    ints.append(contentsOf: tensor.ints[base..<(base + inner)])
                } else {
                    floats.append(contentsOf: tensor.floats[base..<(base + inner)])
                }
            }
        }
        return tensor.isInt ? OnnxTensor(shape: shape, ints: ints) : OnnxTensor(shape: shape, floats: floats)
    }

    static func slice(_ tensor: OnnxTensor, starts: [Int], ends: [Int], axes: [Int]?, steps: [Int]?) throws -> OnnxTensor {
        var result = tensor
        for (position, start) in starts.enumerated() {
            let axis = try self.axis(axes?[position] ?? position, rank: result.rank)
            let step = steps?[position] ?? 1
            guard step > 0 else { throw OnnxError.unsupported("Slice with step \(step)") }
            let length = result.shape[axis]
            func clamp(_ value: Int) -> Int { max(0, min(length, value < 0 ? value + length : value)) }
            let from = clamp(start)
            let to = clamp(ends[position])
            let picks = Array(Swift.stride(from: from, to: max(from, to), by: step))
            result = try gather(result, indices: OnnxTensor(shape: [picks.count], ints: picks), axis: axis)
        }
        return result
    }

    static func concat(_ tensors: [OnnxTensor], axis: Int) throws -> OnnxTensor {
        guard let first = tensors.first else { throw OnnxError.malformed("Concat of nothing") }
        let axis = try self.axis(axis, rank: first.rank)
        let outer = first.shape[..<axis].reduce(1, *)
        let integer = tensors.allSatisfy(\.isInt)
        var shape = first.shape
        shape[axis] = 0
        var floats: [Float] = []
        var ints: [Int] = []
        for tensor in tensors {
            guard tensor.rank == first.rank, tensor.shape[..<axis] == first.shape[..<axis],
                  tensor.shape[(axis + 1)...] == first.shape[(axis + 1)...]
            else { throw OnnxError.malformed("Concat of \(tensors.map(\.shape)) on axis \(axis)") }
            shape[axis] += tensor.shape[axis]
        }
        for block in 0..<outer {
            for tensor in tensors {
                let width = tensor.count / max(outer, 1)
                let range = (block * width)..<((block + 1) * width)
                if integer { ints.append(contentsOf: tensor.ints[range]) } else { floats.append(contentsOf: tensor.asFloats()[range]) }
            }
        }
        return integer ? OnnxTensor(shape: shape, ints: ints) : OnnxTensor(shape: shape, floats: floats)
    }

    /// ONNX element types: 1 float32, 6 int32, 7 int64, 9 bool.
    static func cast(_ tensor: OnnxTensor, to type: Int) throws -> OnnxTensor {
        switch type {
        case 1: return OnnxTensor(shape: tensor.shape, floats: tensor.asFloats())
        case 6, 7: return OnnxTensor(shape: tensor.shape, ints: tensor.asInts())
        case 9:
            let flags = tensor.isInt ? tensor.ints.map { $0 != 0 ? 1 : 0 } : tensor.floats.map { $0 != 0 ? 1 : 0 }
            return OnnxTensor(shape: tensor.shape, ints: flags)
        default: throw OnnxError.unsupported("Cast to type \(type)")
        }
    }
}
