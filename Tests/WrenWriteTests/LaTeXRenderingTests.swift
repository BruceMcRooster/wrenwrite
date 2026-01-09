import Foundation
import Testing

@testable import WrenWrite

@Suite("LaTeX Rendering")
struct LaTeXRenderingTests {
    @Test func basicOkayInput() async throws {
        let input = "f(x) = \\int_{-\\infty}^\\infty f(\\hat\\xi)\\,e^{2 \\pi i \\xi x}\\,d\\xi"

        let (output, didError) = renderBlahtexToMathML(input, display: .block)
        
        #expect(didError == false)
        
        #expect(output == """
            <math xmlns="http://www.w3.org/1998/Math/MathML" display="block">\
            <semantics>\
            <mrow><mi>f</mi><mo stretchy="false">(</mo><mi>x</mi><mo stretchy="false">)</mo><mo>=</mo><msubsup><mo stretchy="false">&#x222b;</mo><mrow><mo>-</mo><mi mathvariant="normal">&#x221e;</mi></mrow><mi mathvariant="normal">&#x221e;</mi></msubsup><mi>f</mi><mo stretchy="false">(</mo><mover><mi>&#x3be;</mi><mo accent="true">&#x302;</mo></mover><mo rspace="0.167em" stretchy="false">)</mo><msup><mi>e</mi><mrow><mn>2</mn><mi>&#x3c0;</mi><mi>i</mi><mi>&#x3be;</mi><mi>x</mi></mrow></msup><mspace width="0.167em"/><mi>d</mi><mi>&#x3be;</mi></mrow>\
            <annotation encoding="application/x-tex">"\(input)"</annotation>\
            </semantics>\
            </math>
            """)
    }
}
