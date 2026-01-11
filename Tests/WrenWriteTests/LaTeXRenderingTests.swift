import Foundation
import Testing

@testable import WrenWrite

@Suite("LaTeX Rendering")
struct LaTeXRenderingTests {
    
    static let okayInputs: [(latex: String, expectedMathML: String)] = [
        (
            "f(x) = \\int_{-\\infty}^\\infty f(\\hat\\xi)\\,e^{2 \\pi i \\xi x}\\,d\\xi",
            "<mrow><mi>f</mi><mo lspace=\"0\" rspace=\"0\" stretchy=\"false\">(</mo><mi>x</mi><mo lspace=\"0\" rspace=\"0.278em\" stretchy=\"false\">)</mo><mo lspace=\"0\" rspace=\"0.278em\">=</mo><msubsup><mo lspace=\"0\" rspace=\"0.167em\" stretchy=\"false\">&#x222b;</mo><mrow><mo lspace=\"0\" rspace=\"0\">-</mo><mi mathvariant=\"normal\">&#x221e;</mi></mrow><mi mathvariant=\"normal\">&#x221e;</mi></msubsup><mi>f</mi><mo lspace=\"0\" rspace=\"0\" stretchy=\"false\">(</mo><mover><mi>&#x3be;</mi><mo accent=\"true\">&#x302;</mo></mover><mo lspace=\"0\" rspace=\"0.167em\" stretchy=\"false\">)</mo><msup><mi>e</mi><mrow><mn>2</mn><mi>&#x3c0;</mi><mspace width=\"0\"/><mi>i</mi><mspace width=\"0\"/><mi>&#x3be;</mi><mspace width=\"0\"/><mi>x</mi></mrow></msup><mspace width=\"0.167em\"/><mi>d</mi><mspace width=\"0\"/><mi>&#x3be;</mi></mrow>"
        ),
        (
            """
            \\begin{bmatrix}
            \t\\sqrt{x^2+\\alpha} < 5 \\\\
            \t\\sqrt{x^2+\\alpha}
            \\end{bmatrix}
            """,
            "<mrow><mo stretchy=\"true\">[</mo><mrow><mstyle scriptlevel=\"0\"><mtable><mtr><mtd><msqrt><msup><mi>x</mi><mn>2</mn></msup><mo lspace=\"0.222em\" rspace=\"0.222em\">+</mo><mi>&#x3b1;</mi></msqrt><mo lspace=\"0.278em\" rspace=\"0.278em\">&lt;</mo><mn>5</mn></mtd></mtr><mtr><mtd><msqrt><msup><mi>x</mi><mn>2</mn></msup><mo lspace=\"0.222em\" rspace=\"0.222em\">+</mo><mi>&#x3b1;</mi></msqrt></mtd></mtr></mtable></mstyle></mrow><mo stretchy=\"true\">]</mo></mrow>"
        )
    ]
    
    @Test(arguments: okayInputs)
    func basicOkayInput(_ input: (latex: String, expectedMathML: String)) async throws {
        let mathML = try latexToMathML(input.latex)
        
        #expect(mathML == input.expectedMathML)
    }
}
