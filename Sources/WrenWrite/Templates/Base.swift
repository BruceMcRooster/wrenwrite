extension Templates {
    struct Base: Template {
        struct Context {
            let title: String?
            let seo: GeneratingCallback?
            let heading: GeneratingCallback?
            let nav: GeneratingCallback?
            let content: GeneratingCallback?
            let footer: GeneratingCallback?

            init(
                title: String? = nil,
                seo: GeneratingCallback? = nil,
                heading: GeneratingCallback? = nil,
                nav: GeneratingCallback? = nil,
                content: GeneratingCallback? = nil,
                footer: GeneratingCallback? = nil
            ) {
                self.title = title
                self.seo = seo
                self.heading = heading
                self.nav = nav
                self.content = content
                self.footer = footer
            }
        }

        let context: Context

        func generate(into output: inout TemplateGenerationOutput) {
            print(
                """
                <!DOCTYPE html>
                <html lang="en">

                <head>
                  <meta charset="utf-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1">
                  <link rel="icon" href="data:;base64,iVBORw0KGgo=">
                  <title>\(context.title ?? "ˏ₍๏ɞ๏₎ˎ Wren Blog")</title>
                """, terminator: "", to: &output)

            if let seo = context.seo {
                seo(&output)
            }

            print(
                """
                  <style>
                    body {
                      font-family: 'Verdana', sans-serif;
                      margin: auto;
                      padding: 20px;
                      max-width: 720px;
                      text-align: left;
                      background-color: white;
                    }

                    a {
                      /* color: #eba613; */
                      color: #3273dc;
                    }

                    h2 a {
                      font-weight: 400;
                      color: #000;
                      text-decoration: none;
                    }

                    nav a {
                      margin-right: 10px;
                    }

                    ul li.task-list-item {
                      list-style-type: none;
                      input.task-list-item-checkbox {
                        margin: 0 .2em .25em -1.4em;
                        vertical-align: middle;
                      }
                    }

                    textarea {
                      width: 100%;
                      font-size: 0.9em;
                    }

                    table {
                      width: 100%;
                    }
                    img {
                      max-width: 100%;
                    }

                    footer {
                      padding: 25px;
                      text-align: center;
                    }
                  </style>
                </head>

                <body>
                  <header>
                    <h2>
                """, terminator: "", to: &output)

            if let heading = context.heading {
                heading(&output)
            }

            print(
                """
                    </h2>
                    <nav>
                """, terminator: "", to: &output)

            if let nav = context.nav {
                nav(&output)
            }

            print(
                """
                    </nav>
                  </header>
                  <main>
                """, terminator: "", to: &output)

            if let content = context.content {
                content(&output)
            }

            print(
                """
                  </main>
                  <footer>
                """, terminator: "", to: &output)

            if let footer = context.footer {
                footer(&output)
            }

            print(
                """
                  </footer>
                </body>

                </html>
                """, to: &output)
        }
    }
}
