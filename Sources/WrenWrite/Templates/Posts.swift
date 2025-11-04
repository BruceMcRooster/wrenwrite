import Foundation

extension Templates {
    struct Posts: Template {
        struct Context {
            let seo: SEO.Context
            let nav: Nav.Context
            let posts: [(title: String, date: Date, slug: String)]

            init(
                seo: SEO.Context, nav: Nav.Context,
                posts: [(title: String, date: Date, slug: String)]
            ) {
                self.seo = seo
                self.nav = nav
                self.posts = posts
            }
        }

        let context: Context

        func generate(into output: inout TemplateGenerationOutput) {
            Base(
                context: .init(
                    title: context.seo.title,
                    seo: SEO(context: context.seo).generate(into:),
                    heading: { output in
                        print(context.seo.title, to: &output)
                    },
                    nav: Nav(context: context.nav).generate(into:),
                    content: { output in
                        print("<ul>", to: &output)
                        for post in context.posts {
                            print(
                                """
                                <li>
                                    <i>
                                        <time datetime="\(post.date.ISO8601Format())" pubdate>
                                            \(post.date.formatted(date: .abbreviated, time: .omitted))
                                        </time>
                                    </i>
                                    <a href="/\(post.slug)">\(post.title)</a>
                                </li>
                                """, to: &output)
                        }
                        print("</ul>", to: &output)
                    },
                )
            ).generate(into: &output)
        }
    }
}
