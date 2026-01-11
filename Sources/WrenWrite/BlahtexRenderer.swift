import Foundation
import Blahtex

struct BlahtexError: Error {
    let errorMessage: String
    let actualError: Blahtex.BlahtexRenderer.BlahtexError
}

/// Renders some Blahtex (basically LaTeX) code to MathML (does not include the surrounding `<math>` tag)
func latexToMathML(_ input: String) throws(BlahtexError) -> String {
    let renderer = BlahtexRenderer()
    
    // At least Safari, maybe others will mess up spacing without strict spacing control.
    // This outputs more verbose MathML where browsers might mess up spacing.
    renderer.mathMLOptions.spacingControl = .strict
    
    do {
        try renderer.processInput(input)
        
        let mathML = try renderer.getMathML()
        
        return mathML
    } catch let e {
        switch e {
        case let .inputError(error):
            throw .init(
                errorMessage: error.errorMessage(), 
                actualError: e
            )
        case let .otherError(errorMessage):
            assertionFailure("Unexpected error from Blahtex: \(errorMessage)")
            throw .init(
                errorMessage: "Unexpected internal Blahtex error (please file a bug report): \(errorMessage)", 
                actualError: e
            )
        case .unconvertibleString:
            assertionFailure("Swift-C++ interoperability error during string conversion")
            throw .init(
                errorMessage: "Unexpected internal wstring error (please file a bug report)", 
                actualError: e
            )
        }
    }
}

/// Takes MathML as an input and renders it into a full HTML `<math>` tag.
func renderMathML(
    latexCode: String, 
    mathML: String, 
    display: MarkdownContent.MathChunk.DisplayStyle
) -> String {
    return """
        <math xmlns="http://www.w3.org/1998/Math/MathML" display="\(display == .inline ? "inline" : "block")">\
        <semantics>\
        \(mathML)\
        <annotation encoding="application/x-tex">"\(latexCode)"</annotation>\
        </semantics>\
        </math>
        """
}

/// Takes a rendering error and outputs the corresponding HTML to display it.
func renderMathMLError(
    latexCode: String, 
    error: BlahtexError, 
    display: MarkdownContent.MathChunk.DisplayStyle
) -> String {
    return """
        <span display="\(display == .inline ? "inline" : "block")" style="color: #cc0000">\
        \(error.errorMessage.replacingOccurrences(of: "\"", with: "&quot;"))\
        </span>
        """
}
