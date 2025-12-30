import Foundation

@main
struct WrenWrite {
    static func main() {
        let inputDir = URL(fileURLWithPath: ".", isDirectory: true)
        print("Generating site from \(inputDir.path)...")
        let outputDir = URL(fileURLWithPath: "./dist", isDirectory: true)
        print("Generating site into \(outputDir.path)...")
        do {
            try FileManager.default.removeItem(at: outputDir)
        } catch {
            // Ignore error
        }
        try! FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let homePage = try! String(contentsOf: inputDir.appending(path: "index.md"))
        let siteMetadata = homePage.firstMatch(of: /^---\s*[\s\S]*?\s*---/)!.output  // Based on https://www.bramadams.dev/202303061543/

        let siteTitle =
            siteMetadata
            .firstMatch(of: /title: (.+)/)!.output.1
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let siteDescription =
            siteMetadata
            .firstMatch(of: /description: (.+)/)?.output.1
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "A WrenWrite Site"
        let siteURL =
            siteMetadata
            .firstMatch(of: /url: (.+)/)?.output.1
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "https://example.com"

        let navItems = {
            do {
                let navData = try String(contentsOf: inputDir.appending(path: "nav.md"))
                let navItems = navData.matches(of: /\[(?<title>.+)\]\((?<url>.+)\)/)
                return navItems.map { match in
                    let output = match.output
                    return (
                        title: String(output.title),
                        slug: String(output.url)
                    )
                }
            } catch {
                return []
            }
        }()
        let navContext = Templates.Nav.Context(items: navItems)

        var allPosts: [(title: String, date: Date, slug: String)] = []

        let iterator = FileManager.default.enumerator(
            at: inputDir, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants])!
        for case let fileURL as URL in iterator {
            guard fileURL.pathExtension == "md" else { continue }
            guard
                fileURL.lastPathComponent != "nav.md"
                    && fileURL.lastPathComponent != "index.md"
            else { continue }
            let relativePath = fileURL.deletingPathExtension().path
                .replacingOccurrences(of: inputDir.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let outputFileURL = outputDir.appending(path: relativePath).appending(
                path: "index.html")
            try! FileManager.default.createDirectory(
                at: outputFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            let markdownData = try! String(contentsOf: fileURL)
            let metadataMatch = markdownData.firstMatch(of: /^---\s*[\s\S]*?\s*---/)
            let metadataText = metadataMatch?.output ?? ""

            let title =
                metadataText
                .firstMatch(of: /title: (.+)/)?.output.1
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled"
            let description =
                metadataText
                .firstMatch(of: /description: (.+)/)?.output.1
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? siteDescription
            let slug = relativePath
            let dateString =
                metadataText
                .firstMatch(of: /date: (.+)/)?.output.1
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            let publishedDate = dateFormatter.date(from: dateString) ?? Date()

            let isPage =
                metadataText
                .firstMatch(of: /isPage: (.+)/)?.output.1
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"

            if !isPage {
                allPosts.append((title: title, date: publishedDate, slug: slug))
            }

            let seoContext = Templates.SEO.Context(
                title: title,
                description: description,
                url: siteURL + "/" + slug
            )

            FileManager.default.createFile(atPath: outputFileURL.path(), contents: nil)
            let outputFileHandle = try! FileHandle(forWritingTo: outputFileURL)

            var output = TemplateGenerationOutput(
                writingTo: outputFileHandle, maxCapacity: 4096,
                handlingErrorsUsing: { e in fatalError("Template generation error: \(e)") })
            defer {
                output.flush()
                try! outputFileHandle.close()
            }

            Templates.Post(
                context: .init(
                    blogTitle: siteTitle,
                    seo: seoContext,
                    nav: navContext,
                    title: title,
                    publishedDate: publishedDate,
                    isPage: isPage
                ) { output in
                    #warning("Markdown rendering temporarily disabled")
                }
            ).generate(into: &output)
        }

        if !allPosts.isEmpty {
            allPosts.sort { $0.date < $1.date }

            try! FileManager.default.createDirectory(
                at: outputDir.appending(path: "blog"), withIntermediateDirectories: true)
            let blogIndexOutputFileURL = outputDir.appending(path: "blog/index.html")
            FileManager.default.createFile(atPath: blogIndexOutputFileURL.path(), contents: nil)
            let blogIndexOutputFileHandle = try! FileHandle(forWritingTo: blogIndexOutputFileURL)
            var blogIndexOutput = TemplateGenerationOutput(
                writingTo: blogIndexOutputFileHandle, maxCapacity: 4096,
                handlingErrorsUsing: { e in fatalError("Template generation error: \(e)") })
            defer {
                blogIndexOutput.flush()
                try! blogIndexOutputFileHandle.close()
            }

            Templates.Posts(
                context: .init(
                    seo: .init(
                        title: "Blog | " + siteTitle,
                        description: siteDescription, url: siteURL + "/blog"),
                    nav: navContext,
                    posts: allPosts
                )
            ).generate(into: &blogIndexOutput)
        }

        let homeOutputFileURL = outputDir.appending(path: "index.html")
        FileManager.default.createFile(atPath: homeOutputFileURL.path(), contents: nil)
        let homeOutputFileHandle = try! FileHandle(forWritingTo: homeOutputFileURL)
        var homeOutput = TemplateGenerationOutput(
            writingTo: homeOutputFileHandle, maxCapacity: 16,
            handlingErrorsUsing: { e in fatalError("Template generation error: \(e)") })
        defer {
            homeOutput.flush()
            try! homeOutputFileHandle.close()
        }

        Templates.Home(
            context: .init(
                seo: .init(
                    title: siteTitle,
                    description: siteDescription, url: siteURL
                ),
                nav: navContext,
                posts: allPosts,
                content: { output in
                    #warning("Markdown rendering temporarily disabled")
                }
            )
        ).generate(into: &homeOutput)

        print("Site generated at \(outputDir.path)")
    }
}
