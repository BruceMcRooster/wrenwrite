import Foundation
import Yams
import md4c_html

enum MarkdownContent {
    case renderedHTML(byteRange: Range<UInt64>)
    case codeBlock(CodeBlock)
    case mathChunk(MathChunk)
    case url(String)
    case embed(Embed)

    struct CodeBlock {
        var lang: String
        var code: Data
    }

    struct MathChunk {
        var code: Data
        var display: DisplayStyle

        enum DisplayStyle {
            case inline, block
        }
    }

    enum Embed {
        case blogTitle, blogDescription, blogLink, blogLastModifiedDate, blogLastPostedDate
        case postTitle, postDescription, postLink, postPublishedDate, postLastModifiedDate
        case tags
        case previousPost, nextPost
        case posts(filter: PostListFilter)

        struct PostListFilter: Hashable, Equatable {
            var postTags: [String]?
            var limit: UInt?
            var orderAscendingByDate: Bool = false
            var includeDescription: Bool = false
            var includeContent: Bool = false
            var includeImages: Bool = false

            /// Parse string should include all filters applied to "posts"
            init!(parsing filterString: String) {
                // Adding the surrounding pipes makes regex parsing a little easier and faster
                let filterString = "|" + (consume filterString) + "|"

                let tagsRegex = /\|\s*tag\s*:\s*(?<tags>[^:|]+?)\|/
                if let tagsString = filterString.firstMatch(of: consume tagsRegex)?.output.tags {
                    self.postTags = tagsString.split(separator: ",").map({
                        $0.trimmingCharacters(in: .whitespaces)
                    })
                }

                let limitRegex = /\|\s*limit\s*:\s*(?<limit>\d+)\s*\|/
                if let limitString = filterString.firstMatch(of: consume limitRegex)?.output.limit {
                    self.limit = UInt(limitString)
                }

                let orderRegex = /\|\s*order\s*:\s*(?<order>(asc|desc))\s*\|/
                if let orderString = filterString.firstMatch(of: consume orderRegex)?.output.order,
                    orderString == "asc"
                {
                    self.orderAscendingByDate = true
                }

                let descriptionTrueRegex = /\|\s*description\s*:\s*((?i)true)\s*\|/
                if filterString.contains(consume descriptionTrueRegex) {
                    self.includeDescription = true
                }

                let contentTrueRegex = /\|\s*content\s*:\s*((?i)true)\s*\|/
                if filterString.contains(consume contentTrueRegex) {
                    self.includeContent = true
                }

                let imageTrueRegex = /\|\s*image\s*:\s*((?i)true)\s*\|/
                if filterString.contains(consume imageTrueRegex) {
                    self.includeImages = true
                }
            }

            #if DEBUG
                /// Used for testing purposes to represent the default values
                /// Should not be used in real code, instead use ``init(parsing:)``
                init() {}
            #endif
        }

        static func parse(from data: String) -> Self? {
            let trimmed = data.trimmingCharacters(in: .whitespaces)
            switch trimmed {
            case "blog_title": return .blogTitle
            case "blog_description": return .blogDescription
            case "blog_link": return .blogLink
            case "blog_last_modified": return .blogLastModifiedDate
            case "blog_last_posted": return .blogLastPostedDate
            case "post_title": return .postTitle
            case "post_description": return .postDescription
            case "post_link": return .postLink
            case "post_published_date": return .postPublishedDate
            case "post_last_modified": return .postLastModifiedDate
            case "previous_post": return .previousPost
            case "next_post": return .nextPost
            case "tags": return .tags
            default:
                if trimmed.starts(with: "posts") {
                    if let filters = PostListFilter.init(parsing: String(trimmed.dropFirst(5))) {
                        return .posts(filter: filters)
                    }
                }
                return nil
            }
        }
    }
}

enum MarkdownRenderingError: Error {
    case bufferAccessError
    case md4cError
}

protocol DataWriter {
    func write(_ data: Data) throws
    func offset() throws -> UInt64
}

private struct ParsingObject {
    let writerWrite: (Data) throws -> Void
    let writerOffset: () throws -> UInt64
    var content: [MarkdownContent] = []
    var state: State?
    let textType: UnsafeMutablePointer<MD_HTML_RAW_TEXT_TYPE>

    enum State {
        /// Represents a partial language code block.
        /// A nil language indicates that the language has not been determined yet,
        /// and that the block may not actually be a language code block.
        case inLanguageCodeBlock(language: String?, code: Data?)
        case inMathChunk(displayStyle: MarkdownContent.MathChunk.DisplayStyle, data: Data)
    }

    mutating func appendHTMLContent(byteRange: Range<UInt64>, line: Int = #line) {
        if let prev = self.content.last, case MarkdownContent.renderedHTML(let prevByteRange) = prev
        {
            assert(
                byteRange.startIndex == prevByteRange.endIndex,
                "Expected append to only happen to consecutive ranges (got prev=\(prevByteRange), current=\(byteRange), called on line \(line)"
            )
            if byteRange.startIndex == prevByteRange.endIndex {
                self.content[self.content.endIndex - 1] = .renderedHTML(
                    byteRange: prevByteRange.startIndex..<byteRange.endIndex)
            }
        } else {
            self.content.append(.renderedHTML(byteRange: byteRange))
        }
    }
}

func renderMarkdown<Writer: DataWriter, FrontmatterDecodeType: Decodable>(
    from inputData: Data,
    writer: Writer
) throws -> (frontmatter: FrontmatterDecodeType?, content: [MarkdownContent]) {
    let markdownStartIndex: Int

    let frontmatter: FrontmatterDecodeType?

    // MARK: Finding and decoding frontmatter
    if inputData.count >= 8  // Minimum size for any frontmatter fences, since there should be ---\n---\n
    {
        let frontmatterStartIndex: Int?

        let unixStyle: [UInt8] = Array("---\n".utf8)
        let windowsStyle: [UInt8] = Array("---\r\n".utf8)
        let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

        if inputData.starts(with: unixStyle) {
            frontmatterStartIndex = unixStyle.count
        } else if inputData.starts(with: windowsStyle) {
            frontmatterStartIndex = windowsStyle.count
            // Checking for
        } else if inputData.starts(with: utf8BOM + unixStyle) {
            frontmatterStartIndex = utf8BOM.count + unixStyle.count
        } else if inputData.starts(with: utf8BOM + windowsStyle) {
            frontmatterStartIndex = utf8BOM.count + windowsStyle.count
        } else {
            frontmatterStartIndex = nil
        }

        if let frontmatterStartIndex, frontmatterStartIndex < inputData.count {
            /// First past end
            let frontmatterEndIndex: Int?

            if let lastFenceRange = inputData.firstRange(
                of: "---\n".data(using: .utf8)!, in: frontmatterStartIndex...)
            {
                frontmatterEndIndex = lastFenceRange.lowerBound
                markdownStartIndex = lastFenceRange.upperBound
            } else if let lastFenceRange = inputData.firstRange(
                of: "---\r\n".data(using: .utf8)!, in: frontmatterStartIndex...)
            {
                frontmatterEndIndex = lastFenceRange.lowerBound
                markdownStartIndex = lastFenceRange.upperBound
            } else {
                frontmatterEndIndex = nil
                markdownStartIndex = 0  // Don't skip the line, because it can be rendered as an <hr>
            }

            if let frontmatterEndIndex {
                let decoder = YAMLDecoder(encoding: .utf8)
                frontmatter = try? decoder.decode(
                    FrontmatterDecodeType.self,
                    // TODO: Check that .subdata(in:) is not copying
                    // Otherwise use init(bytesNoCopy:,count:,deallocator: .none)
                    from: inputData.subdata(in: frontmatterStartIndex..<frontmatterEndIndex)
                )
                assert(
                    frontmatter != nil,
                    "YAML decoder failed to decode frontmatter: \n\(String(data: inputData.subdata(in: frontmatterStartIndex..<frontmatterEndIndex), encoding: .utf8), default: "(error converting to string) raw data: \n\(inputData.subdata(in: frontmatterStartIndex..<frontmatterEndIndex))")"
                )
            } else {
                assertionFailure(
                    "Got a start fence to a frontmatter block without a closing fence. This is probably an error."
                )
                frontmatter = nil
            }
        } else {  // No starting fence
            // (or file so short that it can't contain a closing fence,
            // so we'll just let the markdown parser render an <hr> and nothing else)
            markdownStartIndex = 0
            frontmatter = nil
        }
    } else {
        markdownStartIndex = 0
        frontmatter = nil
    }

    guard markdownStartIndex < inputData.endIndex else {
        return (frontmatter, [])
    }

    let rawTextType = UnsafeMutablePointer<MD_HTML_RAW_TEXT_TYPE>.allocate(capacity: 1)
    rawTextType.initialize(to: MD_HTML_RAW_TEXT_TYPE_NONE)

    // MARK: Chunk processor
    func markdownChunkProcessor(
        chunkPointer: UnsafePointer<MD_CHAR>?,
        chunkLength: MD_SIZE,
        parsingObjectPointer: UnsafeMutableRawPointer?
    ) {
        guard let chunkPointer else {
            assertionFailure("Got null chunk pointer")
            return
        }

        let typedParsingObjectPointer = parsingObjectPointer!.assumingMemoryBound(
            to: ParsingObject.self)

        // DO NOT DO ANYTHING LIKE THIS, because it will copy the struct and thus write to a different buffer.
        // Take it from someone who found at the hard way...
        // var parsingObject = typedParsingObjectPointer.pointee

        // Deviously unsafe, but since we write into the FileHandle,
        // that already copies and gets the thing off our hands.
        // This just makes working with the data slightly easier, without allocating any new memory
        let chunkData = Data(
            bytesNoCopy: UnsafeMutableRawPointer(mutating: chunkPointer), count: Int(chunkLength),
            deallocator: .none)

        func findSubsitutions() -> [Range<UInt64>] {
            var substitutions = [Range<UInt64>]()

            var currStart: UInt64? = nil

            for (index, byte) in chunkData.enumerated() {
                if byte == Character("{").asciiValue!, 0 < index, chunkData[index - 1] == byte {
                    currStart = UInt64(index + 1)
                } else if let knownCurrStart = currStart, byte == Character("}").asciiValue!,
                    chunkData[index - 1] == byte
                {
                    substitutions.append(knownCurrStart..<UInt64(exactly: index - 1)!)
                    currStart = nil
                } else if byte == Character("\n").asciiValue! {
                    currStart = nil
                }
            }
            return substitutions
        }

        guard
            let startOffset = try? typedParsingObjectPointer.pointee.writerOffset(),
            (try? typedParsingObjectPointer.pointee.writerWrite(chunkData)) != nil,
            let endOffset = try? typedParsingObjectPointer.pointee.writerOffset()
        else {
            assertionFailure("Failure to write md4c html data.")
            // We will gracefully abort in regular mode
            return
        }

        if let state = typedParsingObjectPointer.pointee.state {
            // Process chunk data based on the state
            switch state {
            case .inLanguageCodeBlock(nil, nil):
                if chunkData.starts(with: ">".data(using: .utf8)!) {
                    // Opening <pre><code closed, so no language
                    typedParsingObjectPointer.pointee.state = nil

                    let lastIndex = typedParsingObjectPointer.pointee.content.endIndex - 1

                    switch lastIndex {
                    case 0...:
                        if case MarkdownContent.renderedHTML(let byteRange) =
                            typedParsingObjectPointer.pointee.content[lastIndex]
                        {
                            let newRange: Range<UInt64> = byteRange.lowerBound..<endOffset
                            typedParsingObjectPointer.pointee.content[lastIndex] = .renderedHTML(
                                byteRange: newRange)
                        } else {
                            assertionFailure(
                                "Unexpected content type preceded code (should have been rendered HTML)"
                            )
                            fallthrough  // We can gracefully continue by just appending a new part
                        }
                    default:
                        assert(lastIndex == -1)  // Shouldn't be anything else (except potentially in a fallthrough)
                        typedParsingObjectPointer.pointee.content.append(
                            .renderedHTML(byteRange: startOffset..<endOffset))
                    }
                } else if chunkData.starts(with: "\"".data(using: .utf8)!) {
                    assertionFailure("Got an empty language")
                    typedParsingObjectPointer.pointee.state = nil
                } else if !chunkData.starts(with: " ".data(using: .utf8)!) {  // Only happens when receiving ' class="language-'
                    let langId = String(data: chunkData, encoding: .utf8)!
                    typedParsingObjectPointer.pointee.state = .inLanguageCodeBlock(
                        language: langId, code: nil)
                }
            case .inLanguageCodeBlock(let language, nil):
                if chunkData.starts(with: ">".data(using: .utf8)!) {
                    typedParsingObjectPointer.pointee.state = .inLanguageCodeBlock(
                        language: language, code: Data())
                }
            // We can ignore anything else, though the only other thing should be a closing quote
            case .inLanguageCodeBlock(let language, let code) where language != nil && code != nil:
                if typedParsingObjectPointer.pointee.textType.pointee == MD_HTML_RAW_TEXT_TYPE_CODE
                {
                    typedParsingObjectPointer.pointee.state = .inLanguageCodeBlock(
                        language: language, code: code! + chunkData)
                } else {
                    typedParsingObjectPointer.pointee.content.append(
                        .codeBlock(.init(lang: language!, code: code!)))
                    typedParsingObjectPointer.pointee.state = nil
                }
            case .inMathChunk(let displayStyle, let data):
                if typedParsingObjectPointer.pointee.textType.pointee
                    == MD_HTML_RAW_TEXT_TYPE_LATEXMATH
                {
                    typedParsingObjectPointer.pointee.state = .inMathChunk(
                        displayStyle: displayStyle, data: data + chunkData)
                } else {
                    typedParsingObjectPointer.pointee.content.append(
                        MarkdownContent.mathChunk(.init(code: data, display: displayStyle)))
                    typedParsingObjectPointer.pointee.state = nil
                }
            default: fatalError("Internal error during state iteration: invalid state \(state)")
            }
        } else {
            if chunkData.elementsEqual("<pre><code".data(using: .utf8)!) {
                typedParsingObjectPointer.pointee.state = .inLanguageCodeBlock(
                    language: nil, code: nil)
            } else if chunkData.elementsEqual("<x-equation>".data(using: .utf8)!) {
                typedParsingObjectPointer.pointee.state = .inMathChunk(
                    displayStyle: .inline, data: Data())
            } else if chunkData.elementsEqual("<x-equation type=\"display\">".data(using: .utf8)!) {
                typedParsingObjectPointer.pointee.state = .inMathChunk(
                    displayStyle: .block, data: Data())
            } else if typedParsingObjectPointer.pointee.textType.pointee
                == MD_HTML_RAW_TEXT_TYPE_NORMAL
                || typedParsingObjectPointer.pointee.textType.pointee == MD_HTML_RAW_TEXT_TYPE_HTML
            {
                let substitutionRanges = findSubsitutions()

                var prevEnd: UInt64 = startOffset

                for range in substitutionRanges {
                    let asString = String(data: chunkData[range], encoding: .utf8)!

                    guard let subType = MarkdownContent.Embed.parse(from: asString) else {
                        continue  // We'll get it in either the next leftover html or the final append
                    }

                    let actualRange =
                        (range.lowerBound + startOffset)..<(range.upperBound + startOffset)

                    // The 2s account for the {{ and }}
                    if prevEnd < actualRange.lowerBound - 2 {
                        typedParsingObjectPointer.pointee.appendHTMLContent(
                            byteRange: prevEnd..<(actualRange.lowerBound - 2))
                    }
                    typedParsingObjectPointer.pointee.content.append(.embed(subType))
                    prevEnd = actualRange.upperBound + 2
                }

                // Append remaining HTML content
                if prevEnd < (UInt64(exactly: chunkData.count)! + startOffset) {
                    typedParsingObjectPointer.pointee.appendHTMLContent(
                        byteRange: prevEnd..<endOffset)
                }
            } else {
                typedParsingObjectPointer.pointee.appendHTMLContent(
                    byteRange: startOffset..<endOffset)
            }
        }
    }

    // MARK: md4c setup/config
    var parsingObject = ParsingObject(
        writerWrite: { try writer.write($0) },
        writerOffset: { try writer.offset() },
        textType: rawTextType
    )

    // Nice-to-have features
    var parserOptions =
        MD_FLAG_STRIKETHROUGH | MD_FLAG_TABLES | MD_FLAG_UNDERLINE | MD_FLAG_TASKLISTS
    // Used for math rendering
    parserOptions |= MD_FLAG_LATEXMATHSPANS

    #if DEBUG
        let debugFlag = UInt32(MD_HTML_FLAG_DEBUG)
    #else
        let debugFlag: Uint32 = 0
    #endif

    let md4cExitCode: Int32 = try inputData.withUnsafeBytes {
        (bufferPointer: UnsafeRawBufferPointer) in
        guard let bufferBaseAddress = bufferPointer.baseAddress else {
            throw MarkdownRenderingError.bufferAccessError
        }

        let markdownStartPointer = bufferBaseAddress + markdownStartIndex
        let markdownLength = bufferPointer.count - markdownStartIndex

        return md_html(
            markdownStartPointer,
            UInt32(markdownLength),
            markdownChunkProcessor,
            &parsingObject,
            rawTextType,
            UInt32(parserOptions),
            debugFlag
        )
    }

    guard md4cExitCode == 0 else {
        // The only thing it error with, according to doc comments
        assert(md4cExitCode == -1)
        throw MarkdownRenderingError.md4cError
    }

    return (frontmatter, parsingObject.content)
}
