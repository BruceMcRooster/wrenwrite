import Foundation

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
        }
    }
}
