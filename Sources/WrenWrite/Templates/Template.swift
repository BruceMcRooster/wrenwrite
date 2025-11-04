// TODO: change to `any TextOutputStream` when https://github.com/swiftlang/swift/issues/85143 is resolved
typealias TemplateGenerationOutput = BufferedFileOutput

protocol Template {
    associatedtype Context

    init(context: Context)

    func generate(into output: inout TemplateGenerationOutput)
}

typealias GeneratingCallback = (inout TemplateGenerationOutput) -> Void

enum Templates {}
