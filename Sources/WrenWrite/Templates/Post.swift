import Foundation

extension Templates {
    struct Post: Template {
        struct Context {
            let blogTitle: String
            let seo: SEO.Context
            let nav: Nav.Context
            let title: String
            let publishedDate: Date
            let isPage: Bool
            let content: GeneratingCallback

            init(
                blogTitle: String, seo: SEO.Context, nav: Nav.Context, title: String,
                publishedDate: Date, isPage: Bool, content: @escaping GeneratingCallback
            ) {
                self.blogTitle = blogTitle
                self.seo = seo
                self.nav = nav
                self.title = title
                self.publishedDate = publishedDate
                self.isPage = isPage
                self.content = content
            }
        }

        let context: Context

        func generate(into output: inout TemplateGenerationOutput) {
            Base(
                context: .init(
                    title: context.blogTitle,
                    seo: SEO(context: context.seo).generate(into:),
                    heading: { output in
                        print(context.blogTitle, to: &output)
                    },
                    nav: Nav(context: context.nav).generate(into:),
                    content: { output in
                        if !context.isPage {
                            print(
                                """
                                <h1>\(context.title)</h1>
                                <p>
                                    <i>
                                        <time datetime="\(context.publishedDate.ISO8601Format())" pubdate>
                                            \(context.publishedDate.formatted(date: .abbreviated, time: .omitted))
                                        </time>
                                    </i>
                                </p>
                                """, to: &output)
                        }
                        if !context.isPage { print("<article>", to: &output) }
                        context.content(&output)
                        if !context.isPage { print("</article>", to: &output) }
                    }
                )
            ).generate(into: &output)
        }
    }
}
