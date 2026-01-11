import Foundation
import Blahtex

/// Renders some Blahtex (basically LaTeX) code to
func renderBlahtexToMathML(_ input: String, display: MarkdownContent.MathChunk.DisplayStyle) -> (htmlMathTag: String, didError: Bool) {
    let renderer = BlahtexRenderer()
    
    renderer.mathMLOptions.spacingControl = .moderate
    
    do {
        try renderer.processInput(input)
        
        let mathML = try renderer.getMathML()
        
        return (htmlMathTag: """
            <math xmlns="http://www.w3.org/1998/Math/MathML" display="\(display == .inline ? "inline" : "block")">\
            <semantics>\
            \(mathML)\
            <annotation encoding="application/x-tex">"\(input)"</annotation>\
            </semantics>\
            </math>
            """, didError: false)
    } catch let e {
        switch e {
        case let .inputError(error):
            return (htmlMathTag: """
                <span class="blahtex-error" \
                title="\(error.errorMessage()
                    .replacingOccurrences(of: "\"", with: "&quot;"))" \
                style="color:#cc0000">"\(input)"</span>
                """, didError: true)
        case let .otherError(errorMessage):
            assertionFailure("Unexpected error from Blahtex: \(errorMessage)")
            return (htmlMathTag: """
            <span class="blahtex-error" title="Unexpected internal Blahtex error (please file a bug report): \(errorMessage.replacingOccurrences(of: "\"", with: "&quot;"))" style="color:#cc0000">"\(input)"</span>
            """, didError: true)
        case .unconvertibleString:
            assertionFailure("Swift-C++ interoperability error during string conversion")
            return (htmlMathTag: """
                <span class="blahtex-error" title="Unexpected internal wstring error (please file a bug report)" style="color:#cc0000">"\(input)"</span>
                """, didError: true)
        }
    }
}
