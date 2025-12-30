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
