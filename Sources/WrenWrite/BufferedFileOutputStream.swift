import Foundation

struct BufferedFileOutput: TextOutputStream {
    private let fileHandle: FileHandle
    let capacity: Int
    private let errorHandler: (any Error) -> Void

    private var buffer: [UInt8] = []

    init(
        writingTo fileHandle: FileHandle,
        maxCapacity: Int,
        handlingErrorsUsing errorHandler: @escaping (any Error) -> Void
    ) {
        self.fileHandle = fileHandle
        self.capacity = maxCapacity
        self.errorHandler = errorHandler
    }

    mutating func write(_ string: String) {
        self.buffer.append(contentsOf: string.utf8)

        // print("BufferedFileOutput was given chunk \(string)")

        if self.buffer.count >= capacity {
            flush()
        }
    }

    mutating func flush() {
        // print("Flushing buffer of size \(self.buffer.count)")
        if self.buffer.isEmpty { return }

        do {
            try self.fileHandle.write(contentsOf: self.buffer)

            let keepCapacity = self.buffer.capacity <= (self.capacity * 2)
            self.buffer.removeAll(keepingCapacity: keepCapacity)
        } catch let e {
            errorHandler(e)
        }
    }
}
