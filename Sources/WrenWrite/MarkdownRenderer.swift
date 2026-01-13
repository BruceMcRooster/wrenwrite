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
    var partialHTML: Data?

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

enum HTMLRenderError: Error {
    /// The parser of HTML ran out of data before it reached a satisfactory closing tag/other state
    case outOfData
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

        func findEmbeds() -> [Range<UInt64>] {
            var embedRanges = [Range<UInt64>]()

            var currStart: UInt64? = nil

            for (index, byte) in chunkData.enumerated() {
                if byte == Character("{").asciiValue!, 0 < index,
                    chunkData[index - 1] == byte
                {
                    currStart = UInt64(index + 1)
                } else if let knownCurrStart = currStart,
                    byte == Character("}").asciiValue!,
                    chunkData[index - 1] == byte
                {
                    embedRanges.append(
                        knownCurrStart..<UInt64(exactly: index - 1)!
                    )
                    currStart = nil
                } else if byte == Character("\n").asciiValue! {
                    currStart = nil
                }
            }
            return embedRanges
        }

        func findURLsAndEmbedsIn(_ chunkData: Data) throws(HTMLRenderError) -> (
            urls: [Range<UInt64>], embeds: [Range<UInt64>]
        ) {
            var urlRanges = [Range<UInt64>]()
            var embedRanges = [Range<UInt64>]()

            var inScript: Bool = false
            var inStyle: Bool = false

            /// Tries to extract any urls from HTML tags, returning the tag name if successful
            /// Stores the end offset (one past the closing`>`) if the tag was actually an HTML tag stored
            func extractURLsHTMLTag(
                canCrossLines: Bool, doExtractURLs: Bool = true, beg: Int, end: inout Int
            ) throws(HTMLRenderError) -> (name: String, isCloser: Bool)? {
                var attr_state: Int8
                var off = beg

                /// Finds the first-past-the-end index of the next line ending (the starting `\r` or `\n` is at the given index)
                func findNextLineEnd() -> Int? {
                    for index in off..<chunkData.count
                    where chunkData[index] == Character("\n").asciiValue!
                        || chunkData[index] == Character("\r").asciiValue!
                    {
                        return index
                    }
                    return nil
                }

                var line_end = findNextLineEnd() ?? chunkData.count

                /// Gets the character at a given offset in ``chunkData``
                @inline(__always)
                func CH(_ off: Int) -> UInt8 {
                    return chunkData[off]
                }

                // This is not what md4c actually used this for, but it's regularly used this way to I kept it
                /// Gets the ascii codepoint for a character (should always be given a single ascii character as a string)
                @inline(__always)
                func _T(_ str: String) -> UInt8 {
                    assert(str.count == 1 && Character(str).isASCII)
                    return Character(str).asciiValue!
                }

                assert(CH(beg) == Character("<").asciiValue!)

                if off + 1 >= line_end { return nil }
                off += 1

                /* For parsing attributes, we need a little state automaton below.
                 * State -1: no attributes are allowed.
                 * State 0: attribute could follow after some whitespace.
                 * State 1: after a whitespace (attribute name may follow).
                 * State 2: after attribute name ('=' MAY follow).
                 * State 3: after '=' (value specification MUST follow).
                 * State 41: in middle of unquoted attribute value.
                 * State 42: in middle of single-quoted attribute value.
                 * State 43: in middle of double-quoted attribute value.
                 */
                attr_state = 0

                /// Whether or not to get the next attribute value
                var extractNextAttributeAsURL = false
                /// The start state of the currently-being-extracted value.
                /// If this has a value, ``extractNextAttributeAsURL`` should have been set to false,
                /// since the attribute was already discovered and is being processed
                var extractedAttributeStartIndex: Int? = nil

                if CH(off) == _T("/") {
                    /* Closer tag "</ ... >". No attributes may be present. */
                    attr_state = -1
                    off += 1
                }

                func ISALPHA(_ off: Int) -> Bool {
                    let char = chunkData[off]

                    switch char {
                    case _T("A")..._T("Z"),
                        _T("a")..._T("z"):
                        return true
                    default: return false
                    }
                }

                func ISALNUM(_ off: Int) -> Bool {
                    let char = chunkData[off]

                    switch char {
                    case _T("0")..._T("9"),
                        _T("A")..._T("Z"),
                        _T("a")..._T("z"):
                        return true
                    default: return false
                    }
                }

                func ISNEWLINE(_ off: Int) -> Bool {
                    let char = chunkData[off]
                    return char == _T("\r") || char == _T("\n")
                }

                func ISBLANK(_ off: Int) -> Bool {
                    let char = chunkData[off]
                    return char == _T(" ") || char == _T("\t")
                }

                func ISWHITESPACE(_ off: Int) -> Bool {
                    let char = chunkData[off]
                    // Swift strings don't support these escape sequences
                    return ISBLANK(off) || char == 11 /* \v */ || char == 12 /* \f */
                }

                @inline(__always)
                func ISANYOF(_ off: Int, _ pallete: String) -> Bool {
                    let char = chunkData[off]
                    return pallete.utf8.contains(char)
                }

                /* Tag name */
                if off >= line_end || !ISALPHA(off) {
                    return nil
                }
                let tagNameStart = off
                off += 1
                while off < line_end && (ISALNUM(off) || CH(off) == _T("-")) {
                    off += 1
                }
                // This can actually always be forcibly unwrapped,
                // since all characters are certain to be basic ASCII and thus easily parsed
                let tagName = String(data: chunkData[tagNameStart..<off], encoding: .utf8)!

                /* (Optional) attributes (if not closer), (optional) '/' (if not closer)
                 * and final '>'. */
                done: while true {
                    while off < line_end && !ISNEWLINE(off) {
                        if attr_state > 40 {
                            let wasVerbatim = attr_state == 41
                            if attr_state == 41 && (ISBLANK(off) || ISANYOF(off, "\"'=<>`")) {
                                attr_state = 0
                                // Put the char back for re-inspection in the new state.
                                off -= 1
                            } else if attr_state == 42 && CH(off) == _T("'") {
                                attr_state = 0
                            } else if attr_state == 43 && CH(off) == _T("\"") {
                                attr_state = 0
                            }

                            // We found the end of an attribute, we may need to extract it
                            if attr_state == 0 {
                                if doExtractURLs, let extractedAttributeStartIndex {
                                    urlRanges.append(
                                        UInt64(
                                            extractedAttributeStartIndex)..<UInt64(
                                                off + (wasVerbatim ? 1 : 0))  // Avoid chopping off last character if it was a verbatim url
                                    )
                                }
                                extractedAttributeStartIndex = nil
                            }

                            off += 1
                        } else if ISWHITESPACE(off) {
                            if attr_state == 0 {
                                attr_state = 1
                            }
                            off += 1
                        } else if attr_state <= 2 && CH(off) == _T(">") {
                            /* End. */
                            break done
                        } else if attr_state <= 2 && CH(off) == _T("/") && off + 1 < line_end
                            && CH(off + 1) == _T(">")
                        {
                            /* End with digraph '/>' */
                            off += 1
                            break done
                        } else if (attr_state == 1 || attr_state == 2)
                            && (ISALPHA(off) || CH(off) == _T("_") || CH(off) == _T(":"))
                        {
                            let attributeNameStart = off
                            off += 1
                            /* Attribute name */
                            while off < line_end && (ISALNUM(off) || ISANYOF(off, "_.:-")) {
                                off += 1
                            }
                            switch String(
                                data: chunkData[attributeNameStart..<off], encoding: .utf8)!
                            {
                            case "href", "src", "srcset", "poster":
                                extractNextAttributeAsURL = true
                            default:
                                // There is a chance something like `href` (without a value) gets kicked down the road until the next attribute, and we don't want to suddenly start parsing its value instead
                                extractNextAttributeAsURL = false
                            }
                            attr_state = 2
                        } else if attr_state == 2 && CH(off) == _T("=") {
                            /* Attribute assignment sign */
                            off += 1
                            attr_state = 3
                        } else if attr_state == 3 {
                            /* Expecting start of attribute value. */
                            if CH(off) == _T("\"") {
                                attr_state = 43
                            } else if CH(off) == _T("'") {
                                attr_state = 42
                            } else if !ISANYOF(off, "\"'=<>`") && !ISNEWLINE(off) {
                                attr_state = 41
                            } else {
                                return nil
                            }
                            off += 1
                            if extractNextAttributeAsURL {
                                // Subtract one for verbatim URLs so we don't chop off the leading character
                                extractedAttributeStartIndex = off - (attr_state == 41 ? 1 : 0)
                                extractNextAttributeAsURL = false
                            }
                        } else {
                            /* Anything unexpected. */
                            return nil
                        }
                    }

                    /* We have to be on a single line. See definition of start condition
                     * of HTML block, type 7. */
                    if !canCrossLines {
                        return nil
                    }

                    assert(off == line_end)
                    guard off < chunkData.count else {
                        throw .outOfData  // We've reached the end of the chunk, and can't go further, but weren't done
                    }

                    if attr_state == 0 || attr_state == 41 {
                        if doExtractURLs, attr_state == 41, let extractedAttributeStartIndex {
                            urlRanges.append(UInt64(extractedAttributeStartIndex)..<UInt64(off))
                        }
                        attr_state = 1
                    }

                    // Must seek *after* collecting a possible ending to unquoted urls,
                    // and we definitely know we're either going to a new line or throwing
                    // (so urlRanges doesnt' matter), so we can do the two in any order

                    if chunkData[off] == Character("\r").asciiValue! {
                        off += 1  // Double add to get past a \r\n
                    }
                    assert(
                        off > chunkData.endIndex || chunkData[off] == Character("\n").asciiValue!)
                    off += 1

                    guard off < chunkData.count else {
                        throw .outOfData
                    }

                    // We can't do this until after seeking, because otherwise it immediately see the "\n" that might have stopped us
                    line_end = findNextLineEnd() ?? chunkData.count
                }

                // done: (equivalent to the goto position)
                if off >= chunkData.count {
                    return nil
                }

                end = off + 1
                return (name: tagName, isCloser: attr_state == -1)
            }

            var currChunkIndex: Int = chunkData.startIndex

            var embedStart: Int? = nil

            while currChunkIndex < chunkData.count {
                assert(!(inScript && inStyle))

                guard !inScript && !inStyle else {
                    var foundCloser = false

                    let blockContentStart = currChunkIndex
                    var blockContentEnd = currChunkIndex

                    // Seek to closing </tag>
                    while currChunkIndex < chunkData.count {
                        defer { currChunkIndex += 1 }

                        if chunkData[currChunkIndex] == Character("<").asciiValue! {
                            var endIndex: Int = currChunkIndex
                            let beforeTagIndex = currChunkIndex - 1
                            // </script> must be on one line
                            if let (name, isCloser) = try extractURLsHTMLTag(
                                canCrossLines: false, doExtractURLs: false, beg: currChunkIndex,
                                end: &endIndex)
                            {
                                currChunkIndex = endIndex - 1  // -1 for Auto-increment in defer
                                if isCloser && name == ((inScript) ? "script" : "style") {
                                    foundCloser = true
                                    blockContentEnd = beforeTagIndex
                                    break
                                }
                            }
                        }
                    }

                    guard foundCloser else { throw .outOfData }

                    if inStyle, blockContentStart < blockContentEnd {  // check for `url` tag
                        if let fullContents = String(
                            data: chunkData[blockContentStart..<blockContentEnd], encoding: .utf8)
                        {
                            let utf8View = fullContents.utf8

                            // Based on https://stackoverflow.com/a/34166861
                            let urlFunctionRegex =
                                /(?s)url\s*\(\s*(?:'((?:\\.|[^\s'])*)'|"((?:\\.|[^\s"])*)"|((?:\\.|[^\s'"])*))\s*\)/
                            for match in fullContents.matches(of: urlFunctionRegex) {
                                guard
                                    let urlRange = match.output.1 ?? match.output.2
                                        ?? match.output.3
                                else { continue }

                                let start = utf8View.distance(
                                    from: utf8View.startIndex,
                                    to: urlRange.startIndex.samePosition(in: utf8View)!)
                                let end = utf8View.distance(
                                    from: utf8View.startIndex,
                                    to: urlRange.endIndex.samePosition(in: utf8View)!)

                                urlRanges.append(
                                    UInt64(
                                        blockContentStart + start)..<UInt64(blockContentStart + end)
                                )
                            }
                        } else {
                            assertionFailure("Failed to parse style tag content as UTF-8")
                        }  // We'll just fail silently, since this doesn't really matter
                    }

                    inScript = false
                    inStyle = false
                    continue
                }

                if chunkData[currChunkIndex] == Character("<").asciiValue! {
                    var end = currChunkIndex
                    if let (tagName, tagIsCloser) = try extractURLsHTMLTag(
                        canCrossLines: true, beg: currChunkIndex, end: &end)
                    {
                        embedStart = nil  // A tag should stop any embeds
                        currChunkIndex = end - 1  // -1 for increment after loop
                        if !tagIsCloser {
                            inScript = tagName == "script"
                            inStyle = tagName == "style"
                        }
                    }
                } else if chunkData[currChunkIndex] == Character("{").asciiValue!
                    && currChunkIndex + 1 < chunkData.count
                    && chunkData[currChunkIndex + 1] == Character("{").asciiValue!
                {
                    embedStart = currChunkIndex + 2
                    // Intentionally don't step forward, because that will catch {`{{` as the starter
                } else if let knownEmbedStart = embedStart,
                    chunkData[currChunkIndex] == Character("}").asciiValue!
                        && currChunkIndex + 1 < chunkData.count
                        && chunkData[currChunkIndex + 1] == Character("}").asciiValue!
                {
                    if knownEmbedStart < currChunkIndex - 1 {
                        embedRanges.append(UInt64(knownEmbedStart)..<UInt64(currChunkIndex))
                    }
                    embedStart = nil
                }

                currChunkIndex += 1
            }

            // We may still need to parse more
            if inScript || inStyle {
                throw .outOfData
            }

            return (urlRanges, embedRanges)
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

        // Ran out of HTML to fix some incomplete parse of it.
        // Shouldn't happen except on really heinous inputs
        if typedParsingObjectPointer.pointee.textType.pointee != MD_HTML_RAW_TEXT_TYPE_HTML,
            let partialHTML = typedParsingObjectPointer.pointee.partialHTML
        {
            // Treat what was leftover as just rendered HTML
            typedParsingObjectPointer.pointee.appendHTMLContent(
                byteRange: (startOffset - UInt64(partialHTML.count))..<startOffset)
            typedParsingObjectPointer.pointee.partialHTML = nil
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
            {
                let substitutionRanges = findEmbeds()

                var prevEnd: UInt64 = startOffset

                for range in substitutionRanges {
                    let asString = String(
                        data: chunkData[range],
                        encoding: .utf8
                    )!

                    guard
                        let subType = MarkdownContent.Embed.parse(
                            from: asString
                        )
                    else {
                        continue  // We'll get it in either the next leftover html or the final append
                    }

                    let actualRange =
                        (range.lowerBound + startOffset)..<(range.upperBound + startOffset)

                    // The 2s account for the {{ and }}
                    if prevEnd < actualRange.lowerBound - 2 {
                        typedParsingObjectPointer.pointee.appendHTMLContent(
                            byteRange: prevEnd..<(actualRange.lowerBound - 2)
                        )
                    }
                    typedParsingObjectPointer.pointee.content.append(
                        .embed(subType)
                    )
                    prevEnd = actualRange.upperBound + 2
                }

                // Append remaining HTML content
                if prevEnd < (UInt64(exactly: chunkData.count)! + startOffset) {
                    typedParsingObjectPointer.pointee.appendHTMLContent(
                        byteRange: prevEnd..<endOffset
                    )
                }
            } else if typedParsingObjectPointer.pointee.textType.pointee
                == MD_HTML_RAW_TEXT_TYPE_HTML
            {
                let fullChunkData: Data
                let fullChunkDataAbsoluteStart: UInt64

                if let existingHTML = typedParsingObjectPointer.pointee.partialHTML {
                    fullChunkData = existingHTML + chunkData
                    fullChunkDataAbsoluteStart = startOffset - UInt64(existingHTML.count)
                } else {
                    fullChunkData = chunkData
                    fullChunkDataAbsoluteStart = startOffset
                }

                guard let (staticURLRanges, embedRanges) = try? findURLsAndEmbedsIn(fullChunkData) else {
                    typedParsingObjectPointer.pointee.partialHTML = fullChunkData
                    return  // Wait for the next time around to try again with more complete HTML
                }

                // Need to make it mutable because we might have to insert into it
                // for srcset attributes that contain multiple URLs or other things that needs to be left along
                var urlRanges = consume staticURLRanges
                
                // Found successfully, so we need to cleanup
                typedParsingObjectPointer.pointee.partialHTML = nil

                var (urlIndex, embedIndex) = (0, 0)

                var prevEnd: UInt64 = fullChunkDataAbsoluteStart

                while urlIndex < urlRanges.count
                    || embedIndex < embedRanges.count
                {
                    let currRange: Range<UInt64>
                    let currContent: MarkdownContent
                    /// Indicates how much of a buffer to allow for around a range.
                    /// For example, an embed needs a buffer of 2 since it will be surrounded on either side by `{{` and `}}` (two chars).
                    let surroundingWidth: UInt64

                    if urlIndex < urlRanges.count
                        && (embedIndex == embedRanges.count
                            || urlRanges[urlIndex].startIndex < embedRanges[embedIndex].startIndex)
                    {
                        let urlRange = urlRanges[urlIndex]
                        urlIndex += 1

                        currRange = urlRange
                        var rawURLData = String(data: fullChunkData[urlRange], encoding: .utf8)!
                        
                        // MARK: Clean raw HTML URL
                        
                        // Based partially on https://html.spec.whatwg.org/#srcset-attributes.
                        // URL part just takes any character and allows for escaping.
                        let urls = rawURLData.matches(of: #/
                            (?s) # Allows for matching escaped newlines with \\. (turns on dot matching newline)
                            \s*
                                (?<url>(?:\\.|[^\\\s])+) # Allows for any character in url to be escaped
                            \s* # This not being a + should be fine, since previous part will greedily consume
                                (?<descriptor> # Grab (optional) descriptor
                                    \d+w # Either a width descriptor
                                        | # or a pixel density descriptor
                                    -? # Allow negative sign in floating point because browsers can be permissive, 
                                       # but technically invalid
                                    (?:
                                        \d+(?:\.\d+)? # Grab a digit before decimal point and after (e.g. 2.8)
                                            | # or
                                        \.\d+ # only a decimal point with digits after it (e.g. .8)
                                    ) # Specifies so as not to accept e5x or something (must have decimal part)
                                    (?:[eE][+-]?\d+)? # Optional exponent part
                                    x # x for pixel density descriptor
                                )? # Make sure this is greedy so we eat up these descriptors and don't capture them as urls
                            \s*
                        /#)
                        
                        // Check for less than because there's a chance my regex doesn't catch something, but we should still spit out
                        guard urls.count < 2 && (urls.count == 0 || urls[0].output.descriptor == nil) else { 
                            // Need to split up based on multiple URLs
                            
                            var currRegex = urls[urls.endIndex - 1]
                            // Go backwards so that as we append we eventually get the first ranges first
                            for i in stride(from: urls.endIndex - 1, through: 0, by: -1) {
                                currRegex = urls[i]
                                
                                let realURLLowerBound = UInt64(
                                    rawURLData.utf8.distance(
                                        from: rawURLData.utf8.startIndex, 
                                        to: currRegex.output.url.startIndex.samePosition(in: rawURLData.utf8)!
                                    )
                                ) + urlRange.startIndex
                                
                                let realURLUpperBound = UInt64(
                                    rawURLData.utf8.distance(
                                        from: rawURLData.utf8.startIndex, 
                                        to: currRegex.output.url.endIndex.samePosition(in: rawURLData.utf8)!
                                    )
                                ) + urlRange.startIndex
                                
                                urlRanges.insert(realURLLowerBound..<realURLUpperBound, at: urlIndex)
                            }
                            
                            continue // let processing continue happening with the new ranges
                        }
                        
                        // Potential TODO: could reinsert single urls (that we can pick up in regex)
                        // so that miscellaneous spacing/newlines are preserved.
                        // Not essential, though, since any essential spacing
                        // (that between multiple urls or between a url and its descriptor)
                        // will be handled properly.
                        // Would be purely to allow more user customization of the styling of their code.
                        
                        rawURLData = rawURLData.trimmingCharacters(in: .whitespacesAndNewlines)
                        // Remove escaped spaces and newlines
                        rawURLData = rawURLData.replacing(/\\\s/, with: "")
                        // De-escape any backslash-escaped characters
                        // Potential TODO: actual handle escaping the right things in the right places (e.g. only \" in double quotes),
                        // but this should do the trick for now
                        rawURLData = rawURLData.replacing(/\\(.)/, with: { $0.output.1 })
                        
                        currContent = .url(rawURLData)
                        surroundingWidth = 0
                    } else {
                        assert(embedIndex < embedRanges.count)
                        assert(
                            urlIndex == urlRanges.count
                                || embedRanges[embedIndex].startIndex
                                    < urlRanges[urlIndex].startIndex
                        )

                        let embedRange = embedRanges[embedIndex]
                        embedIndex += 1

                        let asString = String(data: fullChunkData[embedRange], encoding: .utf8)!

                        guard let embedType = MarkdownContent.Embed.parse(from: asString) else {
                            continue
                        }

                        currRange = embedRange
                        currContent = .embed(embedType)
                        surroundingWidth = 2
                    }

                    // Kooky to avoid Swift formatter screwing up the range syntax
                    let (actualRangeStart, actualRangeEnd) = (
                        currRange.startIndex + fullChunkDataAbsoluteStart,
                        currRange.endIndex + fullChunkDataAbsoluteStart
                    )
                    let actualRange = actualRangeStart..<actualRangeEnd

                    // The 2s account for the {{ and }}
                    if prevEnd < actualRange.lowerBound - surroundingWidth {
                        typedParsingObjectPointer.pointee.appendHTMLContent(
                            byteRange: prevEnd..<(actualRange.lowerBound - surroundingWidth)
                        )
                    }
                    typedParsingObjectPointer.pointee.content.append(
                        currContent
                    )
                    prevEnd = actualRange.upperBound + surroundingWidth
                }

                // Append remaining HTML content
                if prevEnd < (UInt64(exactly: fullChunkData.count)! + fullChunkDataAbsoluteStart) {
                    typedParsingObjectPointer.pointee.appendHTMLContent(
                        byteRange: prevEnd..<endOffset
                    )
                }
            } else if typedParsingObjectPointer.pointee.textType.pointee
                == MD_HTML_RAW_TEXT_TYPE_URL
            {
                typedParsingObjectPointer.pointee.content.append(
                    .url(
                        String(data: chunkData, encoding: .utf8)
                            ?? {
                                assertionFailure(
                                    "Could not parse url in \(startOffset..<endOffset)"
                                )
                                return ""
                            }()
                    )
                )
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
