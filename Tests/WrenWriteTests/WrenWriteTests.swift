import Foundation
import Testing

@testable import WrenWrite

@Suite("Markdown Rendering")
struct MarkdownRenderingTests {
    class Output: DataWriter {
        var data: Data = Data()

        var dataAsString: String {
            String(data: self.data, encoding: .utf8)!
        }

        func write(_ data: Data) throws {
            self.data.append(data)
        }
        func offset() throws -> UInt64 {
            return UInt64(exactly: self.data.count)!
        }
    }

    func getMarkdownContent(from markdown: Data, basedOn content: [MarkdownContent]) -> Data {
        let renderedHtmlRanges = content.compactMap({
            if case MarkdownContent.renderedHTML(let byteRange) = $0 {
                return byteRange
            } else {
                return nil
            }
        })

        return renderedHtmlRanges.reduce(Data(), { partial, range in partial + markdown[range] })
    }

    @Test func basicText() async throws {
        let output = Output()

        let markdown = "Hello World!".data(using: .utf8)!

        let result: (frontmatter: Int?, content: [MarkdownContent]) = try renderMarkdown(
            from: markdown, writer: output)

        #expect(output.dataAsString == "<p>Hello World!</p>\n")
        #expect(result.content.count == 1)
        #expect(
            String(
                data: getMarkdownContent(from: output.data, basedOn: result.content),
                encoding: .utf8) == String(data: output.data, encoding: .utf8))
        #expect(result.frontmatter == nil)
    }

    @Test func basicMarkdown() async throws {
        let output = Output()

        let markdown = "Hello *World*!\n\n* This\n* is\n* a \n* **test**".data(using: .utf8)!

        let result: (frontmatter: Int?, content: [MarkdownContent]) = try renderMarkdown(
            from: markdown, writer: output)

        #expect(
            output.dataAsString == """
                <p>Hello <em>World</em>!</p>
                <ul>
                <li>This</li>
                <li>is</li>
                <li>a</li>
                <li><strong>test</strong></li>
                </ul>\n
                """  // Trailing newline is very important
        )
        #expect(result.content.count == 1)
        #expect(
            String(
                data: getMarkdownContent(from: output.data, basedOn: result.content),
                encoding: .utf8) == String(data: output.data, encoding: .utf8))
        #expect(result.frontmatter == nil)
    }

    @Test func markdownWithSubstitutions() async throws {
        let output = Output()

        let markdown = "See my {{tags}} and my *{{invalid}} substitution*".data(using: .utf8)!

        let result: (frontmatter: Int?, content: [MarkdownContent]) = try renderMarkdown(
            from: markdown, writer: output)

        #expect(result.content.count == 3)
        #expect(
            String(
                data: getMarkdownContent(from: output.data, basedOn: result.content),
                encoding: .utf8) == """
                    <p>See my  and my <em>{{invalid}} substitution</em></p>

                    """
        )

        if case MarkdownContent.embed(let embed) = result.content[1] {
            let isTags: Bool =
                switch embed {
                case .tags: true
                default: false
                }
            #expect(isTags)
        } else {
            #expect(Bool(false), "Embed was not present in expected position, or was not an embed")
        }

        #expect(result.frontmatter == nil)
    }

    @Test func postFilters() async throws {
        let output = Output()

        let markdown = """
            {{posts|image:true|limit:3}}

            {{ posts | tag: beans, banana_pancakes, tacos | order:asc}}

            {{             posts  }}

            {{ posts|tag: taco, bean|,order:asc }}
            """.data(using: .utf8)!

        let result: (frontmatter: Int?, content: [MarkdownContent]) = try renderMarkdown(
            from: markdown, writer: output)

        #expect(result.content.count == 9)
        #expect(
            String(
                data: getMarkdownContent(from: output.data, basedOn: result.content),
                encoding: .utf8) == String(repeating: "<p></p>\n", count: 4)
        )

        for contentIndex in stride(from: 1, through: 7, by: 2) {
            let content = result.content[contentIndex]
            guard case .embed(let embed) = content else {
                #expect(Bool(false), "Index \(contentIndex) was not an embed")
                continue
            }
            guard case .posts(let filter) = embed else {
                #expect(Bool(false), "Index \(contentIndex) was not a posts embed")
                continue
            }

            switch contentIndex {
            case 1:
                #expect(filter.includeImages == true)
                #expect(filter.limit == 3)
            case 3:
                #expect(filter.postTags == ["beans", "banana_pancakes", "tacos"])
                #expect(filter.orderAscendingByDate == true)
            case 5:
                #expect(filter == MarkdownContent.Embed.PostListFilter())
            case 7:
                #expect(filter.postTags == ["taco", "bean"])
                #expect(filter.orderAscendingByDate == false)
            default:
                fatalError("Iterated to unexpected index")
            }
        }
    }

    @Test func codeBlocks() async throws {
        let output = Output()

        let markdown = """
            Next, I want to present my code block
            ```
            <div>
                "HTML escaped" & directly output
            </div>
            ```
            and my highlighted code block
            ```html
            <div>
                "Not escaped" & added as code block
            </div>
            ```
            *So **cool***!
            """.data(using: .utf8)!

        let result: (frontmatter: Int?, content: [MarkdownContent]) = try renderMarkdown(
            from: markdown, writer: output)

        #expect(result.content.count == 3)
        #expect(
            String(
                data: getMarkdownContent(from: output.data, basedOn: result.content),
                encoding: .utf8) == """
                    <p>Next, I want to present my code block</p>
                    <pre><code>&lt;div&gt;
                        &quot;HTML escaped&quot; &amp; directly output
                    &lt;/div&gt;
                    </code></pre>
                    <p>and my highlighted code block</p>
                    <p><em>So <strong>cool</strong></em>!</p>

                    """
        )

        guard case .codeBlock(let codeBlock) = result.content[1] else {
            #expect(Bool(false), "A code block was not the 2nd content element")
            return
        }
        #expect(
            String(data: codeBlock.code, encoding: .utf8) == """
                <div>
                    "Not escaped" & added as code block
                </div>

                """
        )
        #expect(codeBlock.lang == "html")
    }

    @Test func latexMath() async throws {
        let output = Output()

        let markdown = """
            Next, I want to present my inline $\\LaTeX$,

            and of course my block blahtex: $$
            \\sqrt{x^2\\alpha}
            < 5$$
            *So **cool***!
            """.data(using: .utf8)!

        let result: (frontmatter: Int?, content: [MarkdownContent]) = try renderMarkdown(
            from: markdown, writer: output)

        #expect(result.content.count == 5)
        #expect(
            String(
                data: getMarkdownContent(from: output.data, basedOn: result.content),
                encoding: .utf8) == """
                    <p>Next, I want to present my inline ,</p>
                    <p>and of course my block blahtex:\u{20}
                    <em>So <strong>cool</strong></em>!</p>

                    """  // Space character is written as \u{20} to avoid a formatter trimming the space
        )

        if case .mathChunk(let inlineMath) = result.content[1] {
            #expect(inlineMath.display == .inline)
            #expect(String(data: inlineMath.code, encoding: .utf8) == "\\LaTeX")
        } else {
            #expect(Bool(false), "A math chunk was not the 2nd content element")
        }

        if case .mathChunk(let inlineMath) = result.content[3] {
            #expect(inlineMath.display == .block)
            // Preceding whitespace because of newline
            #expect(String(data: inlineMath.code, encoding: .utf8) == " \\sqrt{x^2\\alpha} < 5")
        } else {
            #expect(Bool(false), "A math chunk was not the 4th content element")
        }
    }
    
    @Test func htmlURLs() async throws {
        let output = Output()

        let markdown = """
            This is a manually typed inline <a href="https://example.com">link</a> that should be caught

            This image has a `srcset`, and spans multiple lines

            <div>
                <img srcset="something.jpg
                    something-bigger.jpg">
            </div>

            These script and style tags link to external things

            <script src="myscript.js"></script>
            <link rel="stylesheet" href='mystyles.css'>

            And this `<video src="notaurl.mp4"></video>` doesn't have quotes on its `poster` link

            <div><video src='mymedia.mp4' poster=myposter.jpg><track label="English" kind="subtitles" srclang="en" src="subtitles.vtt" /></video></div>

            And finally (this may just blow things up), this block has a preceding space 😱,

              <img src="scared-face.png" />
            """.data(using: .utf8)!

        let result: (frontmatter: Int?, content: [MarkdownContent]) = try renderMarkdown(
            from: markdown, writer: output)

        #expect(
            String(
                data: getMarkdownContent(from: output.data, basedOn: result.content),
                encoding: .utf8) == """
                    <p>This is a manually typed inline <a href="">link</a> that should be caught</p>
                    <p>This image has a <code>srcset</code>, and spans multiple lines</p>
                    <div>
                        <img srcset="">
                    </div>
                    <p>These script and style tags link to external things</p>
                    <script src=""></script>
                    <link rel="stylesheet" href=''>
                    <p>And this <code>&lt;video src=&quot;notaurl.mp4&quot;&gt;&lt;/video&gt;</code> doesn't have quotes on its <code>poster</code> link</p>
                    <div><video src='' poster=><track label="English" kind="subtitles" srclang="en" src="" /></video></div>
                    <p>And finally (this may just blow things up), this block has a preceding space 😱,</p>
                      <img src="" />

                    """
        )

        #expect(result.content.count == 17)
        
        let allFoundURLStrings: Array<String> = result.content.compactMap { markdownContent in
            if case let .url(string) = markdownContent {
                string
            } else {
                nil
            }
        }
        
        print(allFoundURLStrings)
        
        for (index, desiredURLString) in [
            "https://example.com",
            "something.jpg\nsomething-bigger.jpg",
            "myscript.js",
            "mystyles.css",
            "mymedia.mp4",
            "myposter.jpg",
            "subtitles.vtt",
            "scared-face.png"
        ].enumerated() {
            let foundIndex = allFoundURLStrings.firstIndex(of: desiredURLString)
            
            if let foundIndex {
                #expect(foundIndex == index * 2 + 1)
            } else {
                #expect(Bool(false), "Did not find URL: \(desiredURLString)")
            }
        }
    }
}
