import Foundation
import md4c_html

extension Templates {
    struct Markdown: Template {
        struct Context {
            var filePath: URL
            var errorHandler: (any Error) -> Void
        }

        enum MarkdownParsingError: Error {
            //            case cStringConversionError // Just going to fatalError instead
            case md_htmlError(Int32)
        }

        let context: Context

        func generate(into output: inout TemplateGenerationOutput) {
            do {
                var markdownString = try String(contentsOf: context.filePath, encoding: .utf8)

                guard !markdownString.isEmpty else { return }

                markdownString.makeContiguousUTF8()
                let utf8View = markdownString.utf8

                let cStringOffset =
                    if let match =
                        markdownString
                        .firstMatch(of: /^---\s*[\s\S]*?\s*---/)
                    {  // Based on https://www.bramadams.dev/202303061543/
                        utf8View.distance(
                            from: utf8View.startIndex,
                            to: match.endIndex.samePosition(in: utf8View)!
                        )
                    } else { 0 }  // No yaml frontmatter

                let statusCode = utf8View.withContiguousStorageIfAvailable { buffer in
                    let pointer = buffer.baseAddress! + cStringOffset
                    let length = buffer.count - cStringOffset

                    return md_html(
                        pointer,
                        UInt32(exactly: length)!,
                        {
                            stringPtr, size,
                            outputPointer /*user data for our use; we pass NULL (nil)*/ in
                            guard let stringPtr else { return }
                            guard let outputPointer else { fatalError("outputPointer was NULL") }

                            let typedOutputPointer = outputPointer.bindMemory(
                                to: TemplateGenerationOutput.self, capacity: 1)

                            // DO NOT DO ANYTHING LIKE THIS, because it will copy the struct and thus write to a different buffer.
                            // Take it from someone who found at the hard way...
                            // var output = typedOutputPointer.pointee

                            var rawUTF8 = [UInt8]()
                            rawUTF8.reserveCapacity(Int(size))

                            for i in 0..<Int(size) {
                                rawUTF8.append(UInt8(bitPattern: stringPtr[i]))
                            }

                            let string = String(decoding: rawUTF8, as: UTF8.self)

                            // print("md_html generated chunk \(string)")

                            typedOutputPointer.pointee.write(string)
                        },
                        &output,
                        UInt32(
                            MD_FLAG_STRIKETHROUGH | MD_FLAG_TABLES | MD_FLAG_UNDERLINE
                                | MD_FLAG_TASKLISTS),
                        0
                    )
                }

                guard let statusCode else {
                    fatalError(
                        "Markdown could not be converted to a contiguous buffer. This is an unexpected error. Please report it!"
                    )
                }

                if statusCode != 0 {
                    context.errorHandler(MarkdownParsingError.md_htmlError(statusCode))
                }
            } catch let e {
                context.errorHandler(e)
                return
            }
        }
    }
}
