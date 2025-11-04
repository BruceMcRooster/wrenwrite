extension Templates {
    struct Nav: Template {
        struct Context {
            let items: [(title: String, slug: String)]
        }

        let context: Context

        func generate(into output: inout TemplateGenerationOutput) {
            print(#"<a href="/">Home</a>"#, to: &output)

            for item in context.items {
                print(#"<a href="/\#(item.slug)">\#(item.title)</a>"#, to: &output)
            }

            print(#"<a href="/blog">Blog</a>"#, to: &output)
        }
    }
}
